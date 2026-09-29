extends Node

# RemoteSimClient.gd - FD-316: Render-slave component running on low-end host.
# Disables local physics simulation and interpolates incoming snapshots from RemoteSimHost.

signal snapshot_applied(tick)

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")
var SimLogicFreeze = load("res://core_v2/net/SimLogicFreeze.gd")

export var is_render_slave: bool = false

var _udp = PacketPeerUDP.new()
var _listening_port: int = 0
var _target_ip: String = ""
var _target_port: int = 10444
# FD-316: token de la sesion. Firma cada sim_input y valida los snapshots: un peer LAN
# sin el token no puede suplantar a la autoridad ni cambiarle el destino al esclavo.
var _token: String = ""
# FD-316: seq monotono del esclavo. La autoridad descarta los seq <= al ultimo visto,
# asi un duplicado/reordenado de WiFi no suma dos veces el delta de camara.
var _seq: int = 0
# FD-316: latch corto de flancos. jump/interact viajan en un unico datagrama UDP; si el
# paquete del press se pierde no hay segundo intento. Se repite el true unos paquetes
# mas para sobrevivir a esa perdida (la autoridad deriva el flanco por transicion, asi
# que repetir no duplica la accion).
const FLANK_REPEAT_PACKETS := 3
var _jump_latch: int = 0
var _interact_latch: int = 0
var _buffer: Array = [] # Sorted list of snapshots by tick
var _latest_applied_tick: int = -1
# FD-316 (review bug 8): estado del PhysicsServer ANTES de que el offload lo apagara. No
# se re-prende incondicionalmente: otro sistema (p.ej. la sonda split_load_frame de
# SceneManager) pudo haberlo apagado a proposito.
var _physics_was_active: bool = true
# True solo si este componente apago el PhysicsServer: evita tocar el estado global del
# motor cuando el offload nunca se comprometio.
var _physics_disabled_by_offload: bool = false
# FD-316: fisica apagada/audio muteado/interaccion cedida recien con el PRIMER
# snapshot valido, no al promover. Promover solo abre el canal: mientras el sim host
# no cargue el nivel (sim_hello -> sim_ready) no llega nada y el handheld sigue
# jugando su simulacion local, sin teletransportes ni silencios en vano.
var _engaged: bool = false
# FD-316: el player puede no existir cuando arranca el rol (pairing en un menu o
# justo antes de que SceneManager lo instancie). Si eso pasa, el flag de autoridad
# nunca se aplica y el prompt no vuelve. Se reintenta hasta resolverlo.
var _interaction_authority_applied: bool = false
var _interaction_authority_player: Node = null
# FD-316: con el offload comprometido el handheld no simula NADA: apagar PhysicsServer
# frena los cuerpos del motor pero no los _physics_process de GDScript (controlador del
# Pilot y su CameraRig, props, plataformas, ascensores...), que seguian corriendo con el
# input local encima de cada snapshot ("doble simulacion") y gastando el CPU que el
# offload tiene que liberar. Por convencion del proyecto la logica vive en
# _physics_process y lo visual en _process: se congela el primero en todo el nivel y el
# segundo sigue (animaciones, particulas). El congelado vive en SimLogicFreeze,
# compartido con el stop blando del sim host.
var _freezer = SimLogicFreeze.new()

func _ready() -> void:
	# Aplicar el snapshot DESPUES de cualquier otro _process del frame (camara incluida):
	# la autoridad manda sobre lo que quede corriendo en local.
	process_priority = 1000
	set_process(false)

func start_render_slave(p_port: int = 10444, p_target_ip: String = "", p_target_port: int = 10444, p_token: String = "") -> bool:
	_listening_port = p_port
	_target_ip = p_target_ip
	_target_port = p_target_port
	_token = p_token
	if _listening_port > 0:
		var err = _udp.listen(_listening_port)
		if err != OK:
			printerr("[RemoteSimClient] UDP listen failed on port ", _listening_port, " err=", err)
			return false

	is_render_slave = true
	_engaged = false
	_buffer.clear()
	_latest_applied_tick = -1
	# Sesion nueva: el seq arranca de cero y no hay flancos latcheados de la anterior.
	_seq = 0
	_jump_latch = 0
	_interact_latch = 0
	_last_actor_states.clear()

	# El rol se abre solo para ESCUCHAR: fisica, audio e interaccion siguen locales
	# hasta que llegue el primer snapshot valido (FD-316 paso 3).

	set_process(true)
	return true

func stop_render_slave() -> void:
	is_render_slave = false
	_engaged = false
	set_process(false)
	if _listening_port > 0:
		_udp.close()
	_restore_local_physics()
	_thaw_local_simulation()
	_set_player_interaction_authoritative(false)
	_set_local_audio_muted(false)
	# La cache de estados por path se descarta al salir del rol: si no, una re-promocion
	# en otro nivel con los mismos paths no re-aplicaria el estado (review FD-316).
	_last_actor_states.clear()

# Primer snapshot valido de la autoridad: recien aca el esclavo deja de simular.
func _engage_offload() -> void:
	if _engaged:
		return
	_engaged = true
	# Disable physics server or local physics stepping to free CPU
	_disable_local_physics()
	_freeze_local_simulation()
	# FD-316: la interaccion la resuelve la autoridad; el host no escanea.
	_set_player_interaction_authoritative(true)
	# El que suena es el control remoto (el que simula); este host solo renderiza.
	_set_local_audio_muted(true)
	print("[RemoteSimClient] offload comprometido con el primer snapshot: fisica local apagada")

func is_engaged() -> bool:
	return _engaged

func _set_local_audio_muted(muted: bool) -> void:
	var audio = get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("set_render_slave_audio_muted"):
		audio.set_render_slave_audio_muted(muted)

# FD-316: una sola resolucion del jugador para todo el cliente (interaccion, congelado,
# input, rig y arm). El jugador del nivel (grupo "player" bajo current_scene) manda:
# SessionManager pisa player=null cuando el jugador no esta bajo current_scene, asi que el
# autoload es solo respaldo (ensayo local sin escena, tests). Antes habia dos funciones
# que resolvian distinto y podian congelar uno y animar otro (review FD-316).
func _get_player() -> Node:
	var tree = get_tree()
	if tree != null and tree.current_scene != null:
		for p in tree.get_nodes_in_group("player"):
			if is_instance_valid(p) and tree.current_scene.is_a_parent_of(p):
				return p
	var session = get_node_or_null("/root/SessionManager")
	if session != null and "player" in session:
		var p = session.player
		if p != null and is_instance_valid(p):
			return p
	return null

func _set_player_interaction_authoritative(on: bool) -> void:
	var player = _get_player()
	if player != null and is_instance_valid(player) and player.has_method("set_remote_interaction_authoritative"):
		player.call("set_remote_interaction_authoritative", on)
		_interaction_authority_applied = on
		_interaction_authority_player = player
	elif not on:
		_interaction_authority_applied = false
		_interaction_authority_player = null

# El rol debe volver a aplicarse si el player anterior desaparecio (cambio de escena):
# si no, la instancia nueva sigue con el scan local y sin prompt.
func _interaction_authority_is_current() -> bool:
	return _interaction_authority_applied and is_instance_valid(_interaction_authority_player)

func _apply_player_interaction(prompt: String, target_path: String) -> void:
	var player = _get_player()
	if player != null and is_instance_valid(player) and player.has_method("apply_remote_interaction_state"):
		player.call("apply_remote_interaction_state", prompt, target_path)

func _freeze_local_simulation() -> void:
	var scene = get_tree().current_scene if get_tree() != null else null
	if _freezer.frozen_root_is(scene):
		return
	# El player puede no colgar de current_scene (SessionManager lo resuelve aparte).
	_freezer.freeze(scene, _get_player())

func _thaw_local_simulation() -> void:
	_freezer.thaw()

func _disable_local_physics() -> void:
	if _physics_disabled_by_offload:
		return
	# Guardar el estado previo: al salir del rol se restaura EL MISMO, no un true ciego.
	_physics_was_active = _read_physics_active()
	_physics_disabled_by_offload = true
	PhysicsServer.set_active(false)

func _restore_local_physics() -> void:
	if not _physics_disabled_by_offload:
		return
	_physics_disabled_by_offload = false
	# Restaurar el estado previo, sin re-prender si este componente nunca lo apago.
	PhysicsServer.set_active(_physics_was_active)

# Godot 3 (y el binding de Box3D) no expone un getter del estado global del PhysicsServer:
# `is_active()` no existe. Si el motor algun dia lo expone se usa; mientras tanto se asume
# activo, que es el arranque normal del proyecto.
func _read_physics_active() -> bool:
	if PhysicsServer.has_method("is_active"):
		return PhysicsServer.is_active()
	return true

func receive_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.has("tick"):
		return
	# FD-316 paso 3: el primer snapshot valido compromete el offload. Antes de eso,
	# cualquier paquete no se aplica a un host congelado por error.
	if not _engaged:
		_engage_offload()
	var tick = int(snapshot["tick"])

	# Ignore duplicate or old snapshots
	if tick <= _latest_applied_tick:
		return

	# Insert snapshot in sorted order by tick
	var inserted = false
	for i in range(_buffer.size()):
		if int(_buffer[i]["tick"]) == tick:
			return # duplicate
		if int(_buffer[i]["tick"]) > tick:
			_buffer.insert(i, snapshot)
			inserted = true
			break
	if not inserted:
		_buffer.append(snapshot)

	# Keep buffer bounded (e.g., max 30 snapshots)
	while _buffer.size() > 30:
		_buffer.pop_front()

func _process(delta: float) -> void:
	if not is_render_slave:
		return

	_poll_udp()

	# El player pudo cambiar de escena (o no existir al arrancar el rol): reintentar
	# hasta que la autoridad de interaccion quede aplicada en la instancia actual.
	# Solo cuando el offload esta comprometido: antes, la interaccion es local.
	if _engaged and not _interaction_authority_is_current():
		_set_player_interaction_authoritative(true)
	# Mismo caso para el congelamiento: una escena nueva (cambio de nivel) nace simulando.
	# Con current_scene en null (mitad de transicion) no hay nada que congelar todavia.
	var current_scene = get_tree().current_scene
	if _engaged and current_scene != null and not _freezer.frozen_root_is(current_scene):
		_freeze_local_simulation()

	# Los snapshots llegan a 60 Hz y el handheld dibuja a ~15-25 fps: consumir uno por
	# frame acumulaba hasta 30 de atraso (0.5 s) y luego pop_front descartaba a saltos
	# (camara atrasada y a tirones). Se aplica siempre el mas reciente y se descarta lo viejo.
	if not _buffer.empty():
		var newest = _buffer[_buffer.size() - 1]
		_apply_snapshot(newest)
		_latest_applied_tick = int(newest["tick"])
		_buffer.clear()
	# El _physics_process del Pilot esta congelado: el animator se alimenta aca con la
	# velocidad de la autoridad que llego en el snapshot (si no, se queda en idle).
	if _engaged:
		var player = _get_player()
		if player != null and is_instance_valid(player) and player.has_method("step_remote_animator"):
			player.call("step_remote_animator", delta)
	_send_local_input()

func _send_local_input() -> void:
	if _target_ip == "" or _target_port <= 0:
		return
	var sim_input = _build_local_input()
	var bytes = RemoteProtocol.encode_json(sim_input).to_utf8()
	_udp.set_dest_address(_target_ip, _target_port)
	_udp.put_packet(bytes)

# FD-316 (review bug 5): si el handheld pauso su arbol (menu de pausa, pausa rapida), no
# debe mandar movimiento/camara: el Input singleton no se pausa y el sim host seguiria
# moviendo al personaje detras del menu. En pausa se manda un frame NEUTRO (y se limpian
# los latches de flanco) para que la autoridad suelte el input; al despausar vuelve el
# frame del provider. La notificacion del congelado del nivel la manda RemoteControlManager.
func _build_local_input() -> Dictionary:
	var axes := {"move_x": 0.0, "move_y": 0.0, "analog": false}
	var buttons := {"jump": false, "interact": false, "sprint": false, "crouch": false}
	var camera := {"x": 0.0, "y": 0.0, "zoom": 0.0}
	var tree = get_tree()
	var paused: bool = tree != null and tree.paused
	if paused:
		_jump_latch = 0
		_interact_latch = 0
	else:
		# FD-316: el handheld manda SU frame ya procesado por el InputProvider local: el
		# move_vec con curva/sensibilidad, el auto-sprint analogico (vive en el provider, por
		# eso solo caminaba) y la camara (mouse, stick, D-pad con rampa, touch). La autoridad
		# lo suma tal cual sobre SU frame local.
		var player := _get_player()
		if player != null and is_instance_valid(player):
			var provider = player.get("input_provider") if "input_provider" in player else null
			if provider != null and provider.has_method("get_input"):
				var frame = provider.call("get_input")
				if frame != null:
					axes["move_x"] = frame.move_vec.x
					axes["move_y"] = frame.move_vec.y
					axes["analog"] = frame.analog_move_active
					buttons["jump"] = frame.jump
					buttons["sprint"] = frame.sprint
					buttons["crouch"] = frame.crouch
					buttons["interact"] = frame.interact or frame.interact_held
					camera["x"] = frame.mouse_delta.x
					camera["y"] = frame.mouse_delta.y
					camera["zoom"] = frame.zoom_delta
		buttons = _latch_flanked_buttons(buttons)
	return RemoteProtocol.create_sim_input(axes, buttons, _latest_applied_tick, _token, camera, _next_seq())

# FD-316: latch corto de jump/interact. Si el press se pierde con su datagrama, los
# siguientes paquetes ya traerian false y el tap desaparecia (bug 2 del review FD-316).
# Se repite el true FLANK_REPEAT_PACKETS paquetes; la autoridad deriva el flanco por
# transicion (interact_was_down / _jump_was_pressed), asi que repetir no lo duplica.
func _latch_flanked_buttons(buttons: Dictionary) -> Dictionary:
	if bool(buttons.get("jump", false)):
		_jump_latch = FLANK_REPEAT_PACKETS
	if bool(buttons.get("interact", false)):
		_interact_latch = FLANK_REPEAT_PACKETS
	var out: Dictionary = buttons.duplicate()
	if _jump_latch > 0:
		out["jump"] = true
		_jump_latch -= 1
	if _interact_latch > 0:
		out["interact"] = true
		_interact_latch -= 1
	return out

func _next_seq() -> int:
	_seq += 1
	return _seq

# FD-316: el control manda su look ("mouse_delta"/"touch_camera") a ESTE handheld. Como
# render-esclavo no simula, no alcanza con aplicarlo a su player: se mete en el
# InputProvider local para que lo procese igual que su propio hardware y salga en el
# frame procesado que viaja a la autoridad (ver _send_local_input).
func queue_camera_input(dx: float, dy: float, zoom: float = 0.0, is_touch: bool = false) -> void:
	var player := _get_player()
	if player == null or not is_instance_valid(player):
		return
	var provider = player.get("input_provider") if "input_provider" in player else null
	if provider == null:
		return
	if is_touch:
		if provider.has_method("add_touch_camera_drag"):
			provider.call("add_touch_camera_drag", Vector2(dx, dy))
		if provider.has_method("add_touch_camera_zoom"):
			provider.call("add_touch_camera_zoom", zoom)
	elif "mouse_delta_accum" in provider:
		provider.mouse_delta_accum += Vector2(dx, dy)

func _poll_udp() -> void:
	if _listening_port <= 0:
		return
	while _udp.get_available_packet_count() > 0:
		var packet_ip = _udp.get_packet_ip()
		var pkt = _udp.get_packet()
		var pkt_str = pkt.get_string_from_utf8()
		var dict = RemoteProtocol.decode_json(pkt_str)
		_handle_udp_packet(packet_ip, dict)

# FD-316: un snapshot sin el token de la sesion se descarta por completo: no se aplica
# ni se adopta su IP de origen como destino (suplantacion del sim host, riesgo "Sin auth").
func _handle_udp_packet(packet_ip: String, dict: Dictionary) -> void:
	if String(dict.get("type", "")) != "sim_snapshot":
		return
	if not _snapshot_token_ok(dict):
		printerr("[RemoteSimClient] snapshot descartado: token invalido")
		return
	if packet_ip != "":
		_target_ip = packet_ip
	receive_snapshot(dict)

# Sin token fijado (legacy/tests) se acepta cualquier snapshot.
func _snapshot_token_ok(snapshot: Dictionary) -> bool:
	if _token == "":
		return true
	return String(snapshot.get("token", "")) == _token

func _apply_snapshot(snapshot: Dictionary) -> void:
	var tree = get_tree()
	if tree == null:
		return

	var scene = tree.current_scene
	if scene == null:
		return

	var entities: Dictionary = snapshot.get("entities", {})
	for path_str in entities:
		var node = scene.get_node_or_null(NodePath(path_str))
		if node == null:
			node = get_node_or_null(NodePath(path_str))
		if node != null and is_instance_valid(node) and node is Spatial:
			var state: Dictionary = entities[path_str]
			if state.has("t"):
				var target_transform = RemoteProtocol.decode_transform(state["t"])
				node.global_transform = target_transform
			if state.has("v"):
				node.visible = bool(state["v"])
			if state.has("l_energy") and node is Light:
				node.light_energy = float(state["l_energy"])
			# FD-316: el render-esclavo no simula; la velocidad/piso reales vienen de
			# la autoridad para que el animator elija walk/run/aire en vez de idle.
			if state.has("vel") and node.has_method("set_remote_anim_state"):
				var v_arr = state["vel"]
				if v_arr is Array and v_arr.size() >= 3:
					var wish := Vector3.ZERO
					var w_arr = state.get("wish", null)
					if w_arr is Array and w_arr.size() >= 3:
						wish = Vector3(w_arr[0], w_arr[1], w_arr[2])
					node.call("set_remote_anim_state", Vector3(v_arr[0], v_arr[1], v_arr[2]), bool(state.get("g", false)), wish)

	var globals: Dictionary = snapshot.get("globals", {})
	# FD-316: interaccion resuelta por la autoridad (prompt + path del interactuable).
	var inter = globals.get("interact", null)
	if inter is Dictionary:
		_apply_player_interaction(String(inter.get("prompt", "")), String(inter.get("path", "")))
	# FD-316: estado logico de los actores (interactuables: switch de luces, valvulas,
	# ascensores). Se aplica solo cuando CAMBIA, para no re-disparar restores cada tick.
	var states = globals.get("states", null)
	if states is Dictionary:
		_apply_actor_states(states)
	# FD-316: el rig completo y el largo del kinematic arm de la autoridad. Se aplica
	# ANTES de cam_t para que el padre quede consistente antes de fijar la camara.
	if globals.has("rig"):
		_apply_player_rig(globals["rig"])
	if globals.has("arm_len"):
		_apply_arm_length(float(globals["arm_len"]))
	if globals.has("cam_t"):
		var camera = tree.root.get_viewport().get_camera()
		if camera != null and is_instance_valid(camera):
			camera.global_transform = RemoteProtocol.decode_transform(globals["cam_t"])
			if globals.has("cam_fov"):
				camera.fov = float(globals["cam_fov"])

	emit_signal("snapshot_applied", int(snapshot.get("tick", 0)))

# La cadena del rig la define RemoteProtocol.RIG_CHAIN (host y esclavo comparten una sola):
# el rig del Pilot se replica entero para que el esclavo no se quede con la pose de spawn.
func _apply_player_rig(rig) -> void:
	if not (rig is Array):
		return
	var player = _get_player()
	if player == null or not is_instance_valid(player):
		return
	var count: int = int(min(rig.size(), RemoteProtocol.RIG_CHAIN.size()))
	for i in range(count):
		if rig[i] == null:
			continue
		var node = player.get_node_or_null(RemoteProtocol.RIG_CHAIN[i])
		if node != null and node is Spatial:
			node.global_transform = RemoteProtocol.decode_transform(rig[i])

func _apply_arm_length(length: float) -> void:
	if length < 0.0:
		return
	var player = _get_player()
	if player == null or not is_instance_valid(player):
		return
	var arm = player.get_node_or_null(RemoteProtocol.RIG_CHAIN[RemoteProtocol.RIG_CHAIN.size() - 1])
	if arm != null and "current_length" in arm:
		arm.current_length = length

# Restaura el estado logico de los actores replicados, solo si cambio desde la ultima
# aplicacion (el host manda el estado actual de todos; aca se filtra por diferencia).
var _last_actor_states: Dictionary = {}

func _apply_actor_states(states: Dictionary) -> void:
	var tree = get_tree()
	var scene = tree.current_scene if tree != null else null
	if scene == null:
		return
	for path_str in states:
		var incoming = states[path_str]
		var cached = _last_actor_states.get(path_str, null)
		if cached != null and _states_equal(cached, incoming):
			continue
		var node = scene.get_node_or_null(NodePath(path_str))
		if node == null:
			node = get_node_or_null(NodePath(path_str))
		if node != null and is_instance_valid(node) and node.has_method("restore_snapshot"):
			node.call("restore_snapshot", incoming)
			_last_actor_states[path_str] = incoming

func _states_equal(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _states_equal(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _states_equal(a[i], b[i]):
				return false
		return true
	if a is float and b is float:
		return is_equal_approx(a, b)
	return a == b
