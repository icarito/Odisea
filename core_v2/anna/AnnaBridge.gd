extends Node

const PORT = 5000
const MAX_READ_BYTES_PER_TICK = 16384
var _server: TCP_Server
var _peers := []
var _interface: Node
var _peer_buffers := {} # { peer_instance_id: String }

# RL State
var _rl_mode := false
var _rl_waiting_for_physics := 0
var _rl_pending_peer: StreamPeerTCP = null
var _rl_last_action_id := -1

func _ready():
	# Check for RL Mode environment variable
	var rl_env = OS.get_environment("ANNA_RL_MODE")
	if rl_env == "1" or rl_env.to_lower() == "true":
		_rl_mode = true
		print("[ANNA] RL Training Mode ENABLED. Lock-step synchronization active.")
		# Ensure this node processes even when tree is paused
		pause_mode = Node.PAUSE_MODE_PROCESS
		# Note: We defer pausing until the scene is loaded in _process

	_interface = preload("res://core_v2/anna/AnnaInterface.gd").new()
	add_child(_interface)

	_server = TCP_Server.new()
	var port_str = OS.get_environment("ANNA_PORT")
	var port = PORT
	if port_str.is_valid_integer():
		port = int(port_str)

	var err = _server.listen(port)
	if err != OK:
		print("[ANNA] Failed to listen on port %d" % port)
	else:
		print("[ANNA] Listening on port %d" % port)

var _rl_initialized := false
var _rl_init_frames := 0

func _process(_delta):
	# RL Lock-Step Logic
	if _rl_mode:
		if not _rl_initialized:
			if get_tree().current_scene:
				_rl_init_frames += 1
				if _rl_init_frames > 10:
					_rl_initialized = true
					get_tree().paused = true
					print("[ANNA] RL Mode: Scene loaded and stabilized. Pausing tree.")
			else:
				return

		if _rl_waiting_for_physics > 0:
			# We are currently advancing physics frames
			# Physics process runs because get_tree().paused is false (or will run)
			# But wait, we need to count PHYSICS frames, not _process frames.
			# _process runs every frame. Physics runs on fixed tick.
			# If we are waiting for physics, we should check if physics frames advanced?
			# Or we can just decrement here if we assume 1:1 or close enough?
			# Actually, reliable way is to check Engine.get_physics_frames()
			pass
		else:
			_process_tcp_rl()

func _physics_process(_delta):
	# Async Mode
	if not _rl_mode:
		_process_tcp_async()
	else:
		# RL Mode: If we are here, it means physics is running (paused = false)
		if _rl_waiting_for_physics > 0:
			_rl_waiting_for_physics -= 1
			if _rl_waiting_for_physics <= 0:
				# We have advanced enough frames. Pause immediately.
				# We must defer the pause to end of frame? No, immediate is fine.
				get_tree().paused = true
				call_deferred("_send_rl_response")

func _process_tcp_async():
	_accept_clients()
	for peer in _peers:
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_handle_peer_async(peer)
	_cleanup_clients()

func _process_tcp_rl():
	_accept_clients()
	# In RL mode, we only process one command at a time from one peer (usually)
	for peer in _peers:
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_handle_peer_rl(peer)
			if _rl_waiting_for_physics > 0:
				break # Stop processing other peers if we started a step
	_cleanup_clients()

func _accept_clients():
	while _server != null and _server.is_connection_available():
		var peer = _server.take_connection()
		if peer:
			_peers.append(peer)
			print("[ANNA] Client connected: %s" % peer.get_connected_host())

func _cleanup_clients():
	var active_peers = []
	for peer in _peers:
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			active_peers.append(peer)
		else:
			print("[ANNA] Client disconnected")
			var pid = peer.get_instance_id()
			if _peer_buffers.has(pid):
				_peer_buffers.erase(pid)
	_peers = active_peers

func _exit_tree():
	for peer in _peers:
		if peer and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
	_peers.clear()
	_peer_buffers.clear()
	if _server:
		_server.stop()

# --- ASYNC MODE ---
func _handle_peer_async(peer: StreamPeerTCP):
	# Send Observation (Every frame)
	var obs = _build_observation_payload()
	var json_str = JSON.print(obs)
	peer.put_data((json_str + "\n").to_utf8())

	# Receive Action
	var lines = _read_lines(peer)
	for line in lines:
		if line.strip_edges() != "":
			var parse = JSON.parse(line)
			if parse.error == OK and typeof(parse.result) == TYPE_DICTIONARY:
				_interface.apply_action(parse.result)

# --- RL MODE ---
func _handle_peer_rl(peer: StreamPeerTCP):
	var lines = _read_lines(peer)
	for line in lines:
		if line.strip_edges() == "": continue

		var parse = JSON.parse(line)
		if parse.error != OK or typeof(parse.result) != TYPE_DICTIONARY:
			print("[ANNA-RL] Malformed JSON: ", line)
			continue

		var cmd = parse.result
		var type = str(cmd.get("type", "UNKNOWN"))

		if type == "RESET":
			_interface.reset_rl_env()
			var obs = _interface.get_rl_observation()
			var response = {"obs": obs, "reward": 0.0, "done": false, "info": {}}
			peer.put_data((JSON.print(response) + "\n").to_utf8())

		elif type == "STEP":
			var action = int(cmd.get("action", 0))
			_interface.apply_rl_action(action)

			_rl_pending_peer = peer
			_rl_waiting_for_physics = 1 # Run 1 physics frame
			get_tree().paused = false # Unpause to let physics run
			return # Stop processing commands until done

func _send_rl_response():
	if not is_instance_valid(_rl_pending_peer):
		_rl_pending_peer = null
		return

	var obs = _interface.get_rl_observation()
	var reward = _interface.get_rl_reward()
	var done = _interface.check_done()

	var response = {
		"obs": obs,
		"reward": reward,
		"done": done,
		"info": {}
	}

	if _rl_pending_peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_rl_pending_peer.put_data((JSON.print(response) + "\n").to_utf8())

	_rl_pending_peer = null

# --- HELPERS ---
func _read_lines(peer: StreamPeerTCP) -> Array:
	var bytes = peer.get_available_bytes()
	if bytes <= 0:
		return []

	var chunk = peer.get_utf8_string(min(bytes, MAX_READ_BYTES_PER_TICK))
	var pid = peer.get_instance_id()

	if not _peer_buffers.has(pid):
		_peer_buffers[pid] = ""
	_peer_buffers[pid] += chunk

	var complete_lines = []
	while "\n" in _peer_buffers[pid]:
		var parts = _peer_buffers[pid].split("\n", true, 1)
		var line = parts[0]
		_peer_buffers[pid] = parts[1]
		complete_lines.append(line)

	return complete_lines

func _build_observation_payload() -> Dictionary:
	var obs = _interface.get_observation()
	if typeof(obs) != TYPE_DICTIONARY:
		obs = {}
	var anna_meta = obs.get("anna", {})
	if typeof(anna_meta) != TYPE_DICTIONARY:
		anna_meta = {}
	anna_meta["peer_count"] = _peers.size()
	obs["anna"] = anna_meta
	return obs
