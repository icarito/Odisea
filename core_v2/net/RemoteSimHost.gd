extends Node

# RemoteSimHost.gd - FD-316: Headless/Authority simulation runner on remote controller.
# Runs 60Hz physics + logic simulation and broadcasts tick snapshots over UDP.

signal snapshot_generated(snapshot)

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")

export var target_ip: String = ""
export var target_port: int = 10444
export var sim_fps: int = 60
export var active: bool = false

# FD-316: la autoridad solo emite cuando el nivel pedido por el render-esclavo
# (sim_hello) esta cargado y tiene jugador. Antes de eso capture_snapshot no tiene
# nada que mostrar: el esclavo no debe recibir basura de RemoteControlHome.
var sim_ready: bool = false
# Nivel de simulacion: se instancia en un Viewport propio con UPDATE_DISABLED, SIN
# own_world (comparte el mundo/fisica principal, ver FD-316 "Decision de
# implementacion"). current_scene del control queda intacto: RemoteControlHome sigue
# siendo la pantalla y el gamepad del sim host.
var _sim_viewport: Viewport = null
var _sim_level: Node = null
var _sim_player: Node = null

var _udp = PacketPeerUDP.new()
var _current_tick: int = 0
var _token: String = ""
var _tracked_group: String = "replay_sync"

# Deterministic input queue: list of input entries ordered by target tick
var _input_queue: Array = []
# Tracked latest input state from handheld client
var _client_input_state: Dictionary = {}
# Que accion del InputMap quedo "apretada" por el ultimo estado del cliente, para soltarla
# cuando deje de estar en el payload (si no, un boton se queda pegado si el cliente se cae
# sin avisar). eje -> {pos, neg}: axes del sim_input mapean a un par de acciones direccionales.
const _CLIENT_AXIS_ACTIONS := {
	"move_x": {"pos": "move_right", "neg": "move_left"},
	"move_y": {"pos": "move_backward", "neg": "move_forward"}
}
var _client_actions_pressed: Dictionary = {}

func _ready() -> void:
	set_physics_process(false)

func start_simulation(p_target_ip: String, p_target_port: int, p_token: String = "") -> void:
	target_ip = p_target_ip
	target_port = p_target_port
	_token = p_token
	_current_tick = 0
	# Re-promocion sin stop limpio: nivel viejo fuera antes de escuchar de nuevo.
	_unload_sim_level()
	if target_port > 0:
		_udp.listen(target_port)
	active = true
	set_physics_process(true)

func stop_simulation() -> void:
	active = false
	set_physics_process(false)
	_udp.close()
	_release_client_input()
	_unload_sim_level()

# --- FD-316: carga del nivel del handheld en el sim host (offload real) ---

# Recibe el sim_hello del render-esclavo: carga su nivel sin reemplazar la UI del
# control, aplica semilla y estado de spawn, y recien entonces habilita la emision.
func load_sim_level(hello: Dictionary) -> bool:
	if not active:
		printerr("[RemoteSimHost] sim_hello ignorado: simulacion no activa")
		return false
	var scene_path := String(hello.get("scene", "")).strip_edges()
	if scene_path == "" or not scene_path.begins_with("res://"):
		printerr("[RemoteSimHost] sim_hello sin escena valida: '", scene_path, "'")
		return false
	if not ResourceLoader.exists(scene_path):
		printerr("[RemoteSimHost] sim_hello: escena inexistente en este build: ", scene_path)
		return false
	var packed = load(scene_path)
	if packed == null or not (packed is PackedScene):
		printerr("[RemoteSimHost] sim_hello: el recurso no es PackedScene: ", scene_path)
		return false
	# Determinismo: la semilla viaja en sim_hello y se fija ANTES de instanciar, para
	# que los sistemas del nivel (p.ej. RandomLeakSeeder) deriven lo mismo que en el
	# esclavo. Nunca se sortea aca.
	var session = get_node_or_null("/root/SessionManager")
	var run_seed := int(hello.get("run_seed", 0))
	if session != null and "run_seed" in session and run_seed != 0:
		session.run_seed = run_seed
		print("[RemoteSimHost] run_seed del esclavo aplicado: ", run_seed)
	var level = packed.instance()
	if level == null:
		printerr("[RemoteSimHost] no se pudo instanciar ", scene_path)
		return false
	print("[RemoteSimHost] cargando nivel del handheld (sin render): ", scene_path)
	return _attach_sim_level(level, hello)

# Monta level_root como nivel de simulacion (seam de test: load_sim_level lo llama
# con la escena ya instanciada). Devuelve true si quedo listo para emitir.
func _attach_sim_level(level_root: Node, hello: Dictionary = {}) -> bool:
	_unload_sim_level()
	if level_root == null:
		return false
	var vp := Viewport.new()
	vp.name = "SimViewport"
	# Sin render y con listener propio: el nivel existe para simular y sonar, no para
	# dibujar (ver FD-316 "Decision de implementacion" para por que comparte mundo).
	vp.render_target_update_mode = Viewport.UPDATE_DISABLED
	vp.audio_listener_enable_3d = true
	add_child(vp)
	vp.add_child(level_root)
	_sim_viewport = vp
	_sim_level = level_root
	_sim_player = _ensure_sim_player()
	_apply_spawn_state(hello)
	# FD-316 paso 3: sim_ready = nivel listo Y con jugador. Sin jugador no hay nada
	# que simular: no se emite y el esclavo nunca deja su simulacion local.
	sim_ready = _sim_player != null
	if not sim_ready:
		printerr("[RemoteSimHost] nivel sin jugador: la simulacion queda en espera (no se emite)")
	else:
		print("[RemoteSimHost] sim_ready: nivel montado con jugador")
	return sim_ready

# El spawn lo resuelve el mismo camino que un F6: SceneManager busca SpawnPointV2 e
# instancia Pilot_v2 si el nivel no lo trae incrustado (solo lectura: no tocamos el
# autoload). Si no hay spawn point no hay jugador: queda sin sim_ready.
func _ensure_sim_player() -> Node:
	if _sim_level == null or not is_instance_valid(_sim_level):
		return null
	var existing = _find_player_under(_sim_level)
	if existing != null:
		return existing
	var sm = get_node_or_null("/root/SceneManager")
	if sm != null and sm.has_method("_ensure_player_in_current_scene"):
		sm._ensure_player_in_current_scene(_sim_level)
		return _find_player_under(_sim_level)
	return null

func _find_player_under(root: Node) -> Node:
	if root == null or not is_instance_valid(root):
		return null
	if root.is_in_group("player"):
		return root
	for pilot in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(pilot) and root.is_a_parent_of(pilot):
			return pilot
	return null

# Estado de spawn del esclavo: snapshot completo del controlador si viajo (checkpoint,
# mismo restore_snapshot que entre escenas), si no posicion+yaw directos.
func _apply_spawn_state(hello: Dictionary) -> void:
	if _sim_player == null or not is_instance_valid(_sim_player):
		return
	var checkpoint: Dictionary = hello.get("checkpoint", {}) if hello.get("checkpoint") is Dictionary else {}
	var player_snapshot: Dictionary = checkpoint.get("player_snapshot", {}) if checkpoint.get("player_snapshot", {}) is Dictionary else {}
	if not player_snapshot.empty() and _sim_player.has_method("restore_snapshot"):
		_sim_player.call("restore_snapshot", player_snapshot)
		return
	var spawn: Dictionary = hello.get("spawn", {}) if hello.get("spawn") is Dictionary else {}
	if not spawn.has("position"):
		return
	var pos_arr: Array = spawn["position"]
	if pos_arr is Array and pos_arr.size() >= 3:
		var t: Transform = _sim_player.global_transform
		t.origin = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		if spawn.has("yaw"):
			t.basis = Basis(Vector3.UP, float(spawn["yaw"]))
		if _sim_player.has_method("teleport_to"):
			_sim_player.call("teleport_to", t)
		elif _sim_player is Spatial:
			(_sim_player as Spatial).global_transform = t

func _unload_sim_level() -> void:
	sim_ready = false
	_sim_player = null
	_sim_level = null
	if _sim_viewport != null and is_instance_valid(_sim_viewport):
		_sim_viewport.queue_free()
	_sim_viewport = null

func _physics_process(_delta: float) -> void:
	if not active:
		return
	# Sin nivel del esclavo cargado (sim_hello pendiente) no hay tick ni emision:
	# capture_snapshot sobre RemoteControlHome no sirve a nadie (FD-316 paso 3).
	if not sim_ready:
		return
	_sample_and_queue_local_input()
	_poll_udp_input()
	_current_tick += 1
	_process_input_queue_for_tick(_current_tick)
	var snapshot = capture_snapshot()
	emit_signal("snapshot_generated", snapshot)
	if target_ip != "" and target_port > 0:
		send_snapshot_udp(snapshot)

func _sample_and_queue_local_input() -> void:
	var axes = {
		"move_x": Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		"move_y": Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	}
	var buttons = {
		"jump": Input.is_action_pressed("jump"),
		"interact": Input.is_action_pressed("interact")
	}
	var sim_input = RemoteProtocol.create_sim_input(axes, buttons, _current_tick + 1, _token)
	receive_sim_input(sim_input, "remote_local")

func receive_sim_input(input_dict: Dictionary, source_id: String = "remote") -> void:
	var target_tick = int(input_dict.get("last_tick", _current_tick))
	if target_tick <= 0:
		target_tick = _current_tick

	var entry = {
		"tick": target_tick,
		"source": source_id,
		"axes": input_dict.get("axes", {}),
		"buttons": input_dict.get("buttons", {})
	}

	var inserted = false
	for i in range(_input_queue.size()):
		if int(_input_queue[i]["tick"]) > target_tick:
			_input_queue.insert(i, entry)
			inserted = true
			break
	if not inserted:
		_input_queue.append(entry)

func _poll_udp_input() -> void:
	while _udp.get_available_packet_count() > 0:
		var pkt = _udp.get_packet()
		var pkt_str = pkt.get_string_from_utf8()
		var dict = RemoteProtocol.decode_json(pkt_str)
		if dict.get("type", "") == "sim_input":
			receive_sim_input(dict, "client")

func _process_input_queue_for_tick(tick: int) -> void:
	var idx = 0
	while idx < _input_queue.size():
		var entry = _input_queue[idx]
		if int(entry["tick"]) <= tick:
			_apply_sim_input_entry(entry)
			_input_queue.remove(idx)
		else:
			idx += 1

func _apply_sim_input_entry(entry: Dictionary) -> void:
	if String(entry.get("source", "")) == "client":
		_client_input_state = entry
		# Sin esto el input del render-esclavo (p.ej. los botones del Anbernic) quedaba
		# encolado y nunca llegaba a moverle el player a la autoridad: caminaba solo,
		# no en la sim, así que jamás se acercaba a un interactuable (FD-316).
		_apply_client_input_to_engine(entry)

# El sim_input del cliente entra como si fuera hardware local del control remoto: las
# mismas acciones del InputMap que lee _sample_and_queue_local_input().
func _apply_client_input_to_engine(entry: Dictionary) -> void:
	var axes: Dictionary = entry.get("axes", {})
	var buttons: Dictionary = entry.get("buttons", {})
	var wanted: Dictionary = {}
	for axis_name in _CLIENT_AXIS_ACTIONS:
		var v := float(axes.get(axis_name, 0.0))
		var actions: Dictionary = _CLIENT_AXIS_ACTIONS[axis_name]
		if v > 0.1:
			wanted[actions["pos"]] = v
		elif v < -0.1:
			wanted[actions["neg"]] = -v
	for action_name in buttons:
		if InputMap.has_action(action_name) and bool(buttons[action_name]):
			wanted[action_name] = 1.0
	for action_name in wanted:
		Input.action_press(action_name, wanted[action_name])
	for action_name in _client_actions_pressed:
		if not wanted.has(action_name):
			Input.action_release(action_name)
	_client_actions_pressed = wanted

func _release_client_input() -> void:
	for action_name in _client_actions_pressed:
		Input.action_release(action_name)
	_client_actions_pressed = {}

func capture_snapshot() -> Dictionary:
	var tree = get_tree()
	if tree == null:
		return {}

	# FD-316: con nivel de simulacion montado, las rutas de entidades son relativas a
	# EL (el esclavo las resuelve contra SU current_scene, que es el mismo nivel).
	# Fallback legacy: lo que el host tenga como current_scene.
	var scene: Node = _sim_level if _sim_level != null and is_instance_valid(_sim_level) else tree.current_scene
	var scene_path = scene.filename if scene != null else ""

	var entities: Dictionary = {}

	# Track replay_sync nodes or Spatials in tree
	var sync_nodes = tree.get_nodes_in_group(_tracked_group)
	if sync_nodes.empty() and scene != null:
		# Fallback: track player and root spatials if replay_sync empty
		sync_nodes = []
		var player = tree.get_nodes_in_group("player")
		sync_nodes.append_array(player)

	for node in sync_nodes:
		if is_instance_valid(node) and node is Spatial:
			# Con nivel de simulacion, solo nodos de ese nivel viajan (el resto del
			# arbol del control no existe en el esclavo).
			if _sim_level != null and is_instance_valid(_sim_level) \
					and not _sim_level.is_a_parent_of(node) and node != _sim_level:
				continue
			var path_str = String(scene.get_path_to(node)) if scene != null else String(node.get_path())
			var state = {
				"t": RemoteProtocol.encode_transform(node.global_transform),
				"v": node.visible
			}
			if node is Light:
				state["l_energy"] = node.light_energy
			# FD-316: la velocidad y el piso del jugador viajan para que el
			# render-esclavo anime walk/run/aire: alla no hay simulacion local.
			if node.is_in_group("player"):
				var node_velocity = node.get("velocity")
				if node_velocity is Vector3:
					state["vel"] = [node_velocity.x, node_velocity.y, node_velocity.z]
					state["g"] = bool(node.call("is_effectively_grounded")) if node.has_method("is_effectively_grounded") else false
			entities[path_str] = state

	var globals: Dictionary = {
		"scene": scene_path
	}
	# FD-316: la interaccion es parte de la simulacion. El host render-esclavo no
	# simula fisica, asi que su Area de interaccion no se actualiza; la autoridad
	# resuelve el interactuable y manda prompt+path en cada snapshot.
	globals["interact"] = _capture_interaction_state()

	# Capture camera state: la del nivel simulado (viewport oculto), no la del UI.
	var camera: Camera = null
	if _sim_viewport != null and is_instance_valid(_sim_viewport):
		camera = _sim_viewport.get_camera()
	if camera == null:
		camera = tree.root.get_viewport().get_camera()
	if camera != null and is_instance_valid(camera):
		globals["cam_t"] = RemoteProtocol.encode_transform(camera.global_transform)
		globals["cam_fov"] = camera.fov

	return RemoteProtocol.create_sim_snapshot(_current_tick, OS.get_ticks_msec(), entities, globals, _token)

func _capture_interaction_state() -> Dictionary:
	# Con nivel simulado, la interaccion se lee del jugador de ESE nivel: el
	# SessionManager del control no lo encuentra (no esta bajo current_scene) y
	# _find_player lo pisaria a null en cada tick.
	var player: Node = _sim_player if _sim_player != null and is_instance_valid(_sim_player) else null
	if player == null:
		var session = get_node_or_null("/root/SessionManager")
		if session != null and "player" in session:
			player = session.player
	if player != null and is_instance_valid(player) and player.has_method("get_interaction_state"):
		var state: Dictionary = player.call("get_interaction_state")
		# El path nace absoluto en el arbol del control; el esclavo lo resuelve
		# contra su escena: recortar el prefijo del nivel simulado.
		if _sim_level != null and is_instance_valid(_sim_level) and state.get("path", "") != "":
			var prefix := String(_sim_level.get_path()) + "/"
			var path := String(state["path"])
			if path.begins_with(prefix):
				state["path"] = path.substr(prefix.length())
		return state
	return {"prompt": "", "path": ""}

func send_snapshot_udp(snapshot: Dictionary) -> void:
	if target_ip == "" or target_port <= 0:
		return
	var json_str = RemoteProtocol.encode_json(snapshot)
	var bytes = json_str.to_utf8()
	_udp.set_dest_address(target_ip, target_port)
	_udp.put_packet(bytes)
