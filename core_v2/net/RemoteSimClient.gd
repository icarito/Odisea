extends Node

# RemoteSimClient.gd - FD-316: Render-slave component running on low-end host.
# Disables local physics simulation and interpolates incoming snapshots from RemoteSimHost.

signal snapshot_applied(tick)

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")

export var is_render_slave: bool = false
export var interp_buffer_ticks: int = 1

var _udp = PacketPeerUDP.new()
var _listening_port: int = 0
var _buffer: Array = [] # Sorted list of snapshots by tick
var _latest_applied_tick: int = -1
var _physics_was_active: bool = true

func _ready() -> void:
	set_process(false)

func start_render_slave(p_port: int = 10444) -> bool:
	_listening_port = p_port
	if _listening_port > 0:
		var err = _udp.listen(_listening_port)
		if err != OK:
			printerr("[RemoteSimClient] UDP listen failed on port ", _listening_port, " err=", err)
			return false

	is_render_slave = true
	_buffer.clear()
	_latest_applied_tick = -1

	# Disable physics server or local physics stepping to free CPU
	_disable_local_physics()

	set_process(true)
	return true

func stop_render_slave() -> void:
	is_render_slave = false
	set_process(false)
	if _listening_port > 0:
		_udp.close()
	_restore_local_physics()

func _disable_local_physics() -> void:
	PhysicsServer.set_active(false)

func _restore_local_physics() -> void:
	PhysicsServer.set_active(true)

func receive_snapshot(snapshot: Dictionary) -> void:
	if not snapshot.has("tick"):
		return
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

	if _buffer.size() < interp_buffer_ticks + 1:
		# Wait until buffer has enough ticks to interpolate
		if not _buffer.empty():
			_apply_snapshot(_buffer[0])
		return

	# Interpolate between snapshot[0] and snapshot[1]
	var snap_a = _buffer[0]
	var snap_b = _buffer[1]

	# Apply snapshot B (or lerp if needed)
	_apply_snapshot(snap_b)
	_latest_applied_tick = int(snap_b["tick"])
	_buffer.pop_front()

func _poll_udp() -> void:
	if _listening_port <= 0:
		return
	while _udp.get_available_packet_count() > 0:
		var pkt = _udp.get_packet()
		var pkt_str = pkt.get_string_from_utf8()
		var dict = RemoteProtocol.decode_json(pkt_str)
		if dict.get("type", "") == "sim_snapshot":
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

	var globals: Dictionary = snapshot.get("globals", {})
	if globals.has("cam_t"):
		var camera = tree.root.get_viewport().get_camera()
		if camera != null and is_instance_valid(camera):
			camera.global_transform = RemoteProtocol.decode_transform(globals["cam_t"])
			if globals.has("cam_fov"):
				camera.fov = float(globals["cam_fov"])

	emit_signal("snapshot_applied", int(snapshot.get("tick", 0)))
