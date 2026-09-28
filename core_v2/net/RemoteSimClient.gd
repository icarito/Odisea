extends Node

# RemoteSimClient.gd - FD-316: Render-slave component running on low-end host.
# Disables local physics simulation and interpolates incoming snapshots from RemoteSimHost.

signal snapshot_applied(tick)

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")

export var is_render_slave: bool = false
export var interp_buffer_ticks: int = 1

var _udp = PacketPeerUDP.new()
var _listening_port: int = 0
var _target_ip: String = ""
var _target_port: int = 10444
var _buffer: Array = [] # Sorted list of snapshots by tick
var _latest_applied_tick: int = -1
var _physics_was_active: bool = true
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
# segundo sigue (animaciones, particulas). Se restauran exactamente los nodos congelados.
var _frozen_nodes: Array = []
var _frozen_scene: Node = null

func _ready() -> void:
	# Aplicar el snapshot DESPUES de cualquier otro _process del frame (camara incluida):
	# la autoridad manda sobre lo que quede corriendo en local.
	process_priority = 1000
	set_process(false)

func start_render_slave(p_port: int = 10444, p_target_ip: String = "", p_target_port: int = 10444) -> bool:
	_listening_port = p_port
	_target_ip = p_target_ip
	_target_port = p_target_port
	if _listening_port > 0:
		var err = _udp.listen(_listening_port)
		if err != OK:
			printerr("[RemoteSimClient] UDP listen failed on port ", _listening_port, " err=", err)
			return false

	is_render_slave = true
	_engaged = false
	_buffer.clear()
	_latest_applied_tick = -1

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

func _get_player() -> Node:
	var session = get_node_or_null("/root/SessionManager")
	if session != null and "player" in session:
		return session.player
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
	if scene == _frozen_scene and is_instance_valid(scene) and not _frozen_nodes.empty():
		return
	_thaw_local_simulation()
	if scene != null and is_instance_valid(scene):
		_frozen_scene = scene
		_freeze_subtree(scene)
	# El player puede no colgar de current_scene (SessionManager lo resuelve aparte).
	var player = _get_player()
	if player != null and is_instance_valid(player) and player.is_physics_processing():
		player.set_physics_process(false)
		_frozen_nodes.append(player)

func _freeze_subtree(node: Node) -> void:
	if node == self:
		return
	# HoloTerminalV2 (pantallas y HUD del traje) usa _physics_process para presentacion:
	# transicion al HUD, cursor del shader, oclusion y anclaje a la camara activa.
	# Congelarlo dejaba las pantallas rosadas y sueltas de la camara.
	if node.is_physics_processing() and not (node is HoloTerminalV2):
		node.set_physics_process(false)
		_frozen_nodes.append(node)
	for child in node.get_children():
		_freeze_subtree(child)

func _thaw_local_simulation() -> void:
	for node in _frozen_nodes:
		if is_instance_valid(node):
			node.set_physics_process(true)
	_frozen_nodes.clear()
	_frozen_scene = null

func _disable_local_physics() -> void:
	PhysicsServer.set_active(false)

func _restore_local_physics() -> void:
	PhysicsServer.set_active(true)

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

func _process(_delta: float) -> void:
	if not is_render_slave:
		return

	_poll_udp()

	# El player pudo cambiar de escena (o no existir al arrancar el rol): reintentar
	# hasta que la autoridad de interaccion quede aplicada en la instancia actual.
	# Solo cuando el offload esta comprometido: antes, la interaccion es local.
	if _engaged and not _interaction_authority_is_current():
		_set_player_interaction_authoritative(true)
	# Mismo caso para el congelamiento: una escena nueva (cambio de nivel) nace simulando.
	if _engaged and (_frozen_scene == null or not is_instance_valid(_frozen_scene) or _frozen_scene != get_tree().current_scene):
		_freeze_local_simulation()

	# Los snapshots llegan a 60 Hz y el handheld dibuja a ~15-25 fps: consumir uno por
	# frame acumulaba hasta 30 de atraso (0.5 s) y luego pop_front descartaba a saltos
	# (camara atrasada y a tirones). Se aplica siempre el mas reciente y se descarta lo viejo.
	if not _buffer.empty():
		var newest = _buffer[_buffer.size() - 1]
		_apply_snapshot(newest)
		_latest_applied_tick = int(newest["tick"])
		_buffer.clear()
	_send_local_input()

func _send_local_input() -> void:
	if _target_ip == "" or _target_port <= 0:
		return

	var axes = {
		"move_x": Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		"move_y": Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	}
	var buttons = {
		"jump": Input.is_action_pressed("jump"),
		"interact": Input.is_action_pressed("interact")
	}

	var sim_input = RemoteProtocol.create_sim_input(axes, buttons, _latest_applied_tick)
	var bytes = RemoteProtocol.encode_json(sim_input).to_utf8()
	_udp.set_dest_address(_target_ip, _target_port)
	_udp.put_packet(bytes)

func _poll_udp() -> void:
	if _listening_port <= 0:
		return
	while _udp.get_available_packet_count() > 0:
		var packet_ip = _udp.get_packet_ip()
		var pkt = _udp.get_packet()
		var pkt_str = pkt.get_string_from_utf8()
		var dict = RemoteProtocol.decode_json(pkt_str)
		if dict.get("type", "") == "sim_snapshot":
			if packet_ip != "":
				_target_ip = packet_ip
			receive_snapshot(dict)

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
					node.call("set_remote_anim_state", Vector3(v_arr[0], v_arr[1], v_arr[2]), bool(state.get("g", false)))

	var globals: Dictionary = snapshot.get("globals", {})
	# FD-316: interaccion resuelta por la autoridad (prompt + path del interactuable).
	var inter = globals.get("interact", null)
	if inter is Dictionary:
		_apply_player_interaction(String(inter.get("prompt", "")), String(inter.get("path", "")))
	if globals.has("cam_t"):
		var camera = tree.root.get_viewport().get_camera()
		if camera != null and is_instance_valid(camera):
			camera.global_transform = RemoteProtocol.decode_transform(globals["cam_t"])
			if globals.has("cam_fov"):
				camera.fov = float(globals["cam_fov"])

	emit_signal("snapshot_applied", int(snapshot.get("tick", 0)))
