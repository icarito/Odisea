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

func _ready() -> void:
	set_physics_process(false)

func start_simulation(p_target_ip: String, p_target_port: int, p_token: String = "") -> void:
	target_ip = p_target_ip
	target_port = p_target_port
	_token = p_token
	_current_tick = 0
	active = true
	set_physics_process(true)

func stop_simulation() -> void:
	active = false
	set_physics_process(false)
	_udp.close()

func _physics_process(_delta: float) -> void:
	if not active:
		return
	_current_tick += 1
	var snapshot = capture_snapshot()
	emit_signal("snapshot_generated", snapshot)
	if target_ip != "" and target_port > 0:
		send_snapshot_udp(snapshot)

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
			entities[path_str] = state

	var globals: Dictionary = {
		"scene": scene_path
	}

	# Capture viewport camera state
	var camera = tree.root.get_viewport().get_camera()
	if camera != null and is_instance_valid(camera):
		globals["cam_t"] = RemoteProtocol.encode_transform(camera.global_transform)
		globals["cam_fov"] = camera.fov

	return RemoteProtocol.create_sim_snapshot(_current_tick, OS.get_ticks_msec(), entities, globals, _token)

func send_snapshot_udp(snapshot: Dictionary) -> void:
	if target_ip == "" or target_port <= 0:
		return
	var json_str = RemoteProtocol.encode_json(snapshot)
	var bytes = json_str.to_utf8()
	_udp.set_dest_address(target_ip, target_port)
	_udp.put_packet(bytes)
