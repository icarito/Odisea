extends Node

# RemoteSimHost.gd - FD-316: Headless/Authority simulation runner on remote controller.
# Runs 60Hz physics + logic simulation and broadcasts tick snapshots over UDP.

signal snapshot_generated(snapshot)

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")

export var target_ip: String = ""
export var target_port: int = 10444
export var sim_fps: int = 60
export var active: bool = false

var _udp = PacketPeerUDP.new()
var _current_tick: int = 0
var _token: String = ""
var _tracked_group: String = "replay_sync"

# Deterministic input queue: list of input entries ordered by target tick
var _input_queue: Array = []
# Tracked latest input state from handheld client
var _client_input_state: Dictionary = {}

func _ready() -> void:
	set_physics_process(false)

func start_simulation(p_target_ip: String, p_target_port: int, p_token: String = "") -> void:
	target_ip = p_target_ip
	target_port = p_target_port
	_token = p_token
	_current_tick = 0
	if target_port > 0:
		_udp.listen(target_port)
	active = true
	set_physics_process(true)

func stop_simulation() -> void:
	active = false
	set_physics_process(false)
	_udp.close()

func _physics_process(_delta: float) -> void:
	if not active:
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

func capture_snapshot() -> Dictionary:
	var tree = get_tree()
	if tree == null:
		return {}

	var scene = tree.current_scene
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

	# Capture viewport camera state
	var camera = tree.root.get_viewport().get_camera()
	if camera != null and is_instance_valid(camera):
		globals["cam_t"] = RemoteProtocol.encode_transform(camera.global_transform)
		globals["cam_fov"] = camera.fov

	return RemoteProtocol.create_sim_snapshot(_current_tick, OS.get_ticks_msec(), entities, globals, _token)

func _capture_interaction_state() -> Dictionary:
	var session = get_node_or_null("/root/SessionManager")
	var player: Node = null
	if session != null and "player" in session:
		player = session.player
	if player != null and is_instance_valid(player) and player.has_method("get_interaction_state"):
		return player.call("get_interaction_state")
	return {"prompt": "", "path": ""}

func send_snapshot_udp(snapshot: Dictionary) -> void:
	if target_ip == "" or target_port <= 0:
		return
	var json_str = RemoteProtocol.encode_json(snapshot)
	var bytes = json_str.to_utf8()
	_udp.set_dest_address(target_ip, target_port)
	_udp.put_packet(bytes)
