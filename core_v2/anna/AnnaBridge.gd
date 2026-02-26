extends Node

const PORT = 5000
const MAX_READ_BYTES_PER_TICK = 16384
const RL_UNCAPPED_PHYSICS_FPS = 2000
const RL_DEFAULT_POLL_SLEEP_USEC = 1000
const MCP_RESULT_TYPE = "mcp_result"
const MCP_ERROR_TYPE = "mcp_error"
var _server: TCP_Server
var _peers := []
var _interface: Node
var _peer_buffers := {} # { peer_instance_id: String }
var is_rl_mode := false
var _rl_read_timeout_ms := 15000
var _rl_poll_sleep_usec := RL_DEFAULT_POLL_SLEEP_USEC

func _ready():
	_interface = preload("res://core_v2/anna/AnnaInterface.gd").new()
	add_child(_interface)

	_server = TCP_Server.new()
	var port_str = OS.get_environment("ANNA_PORT")
	var port = PORT
	if port_str.is_valid_integer():
		port = int(port_str)

	# Check RL Mode
	var rl_mode_env = OS.get_environment("ANNA_RL_MODE")
	if rl_mode_env == "1" or rl_mode_env.to_lower() == "true":
		is_rl_mode = true
		print("[ANNA] RL Lock-Step Mode Enabled")
		OS.set_use_vsync(false)
		var disable_idle_sleep_env = OS.get_environment("ANNA_RL_DISABLE_CPU_SLEEP").to_lower()
		if disable_idle_sleep_env in ["1", "true", "yes", "on"]:
			OS.set_low_processor_usage_mode(false)
			OS.set_low_processor_usage_mode_sleep_usec(0)
		Engine.target_fps = 0
		var physics_fps = 60
		var physics_fps_env = OS.get_environment("ANNA_RL_PHYSICS_FPS")
		if physics_fps_env.is_valid_integer():
			var requested_physics_fps = int(physics_fps_env)
			if requested_physics_fps <= 0:
				physics_fps = RL_UNCAPPED_PHYSICS_FPS
			else:
				physics_fps = max(30, min(requested_physics_fps, RL_UNCAPPED_PHYSICS_FPS))
		Engine.iterations_per_second = physics_fps
		print("[ANNA] VSync disabled, FPS unlocked, physics=%dHz for RL training" % physics_fps)
		var read_timeout_env = OS.get_environment("ANNA_RL_READ_TIMEOUT_MS")
		if read_timeout_env.is_valid_integer():
			_rl_read_timeout_ms = max(1000, int(read_timeout_env))
		var poll_sleep_env = OS.get_environment("ANNA_RL_POLL_SLEEP_USEC")
		if poll_sleep_env.is_valid_integer():
			_rl_poll_sleep_usec = max(0, int(poll_sleep_env))
		elif disable_idle_sleep_env in ["1", "true", "yes", "on"]:
			_rl_poll_sleep_usec = 0
		print("[ANNA] RL poll sleep=%dus timeout=%dms" % [_rl_poll_sleep_usec, _rl_read_timeout_ms])

	var err = _server.listen(port)
	if err != OK:
		print("[ANNA] Failed to listen on port %d" % port)
	else:
		print("[ANNA] Listening on port %d" % port)

func _physics_process(_delta):
	# Accept new connections
	while _server != null and _server.is_connection_available():
		var peer = _server.take_connection()
		if peer:
			peer.set_no_delay(true) # Important for RL latency
			if is_rl_mode:
				_replace_rl_peer(peer)
			else:
				_peers.append(peer)
			print("[ANNA] Client connected: %s" % peer.get_connected_host())

	# Process peers
	var active_peers = []
	for peer in _peers:
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if is_rl_mode:
				_handle_rl_peer_sync(peer)
			else:
				_handle_peer(peer)

			# Check again if still connected after handling (might have disconnected in RL loop)
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

# --- STANDARD ASYNC MODE ---

func _handle_peer(peer: StreamPeerTCP):
	# Send Observation
	var obs = _build_observation_payload()
	var json_str = JSON.print(obs)
	# Append newline for delimiter
	peer.put_data((json_str + "\n").to_utf8())

	# Receive Action (Buffering)
	var bytes = peer.get_available_bytes()
	if bytes > 0:
		var chunk = peer.get_utf8_string(min(bytes, MAX_READ_BYTES_PER_TICK))
		var pid = peer.get_instance_id()

		if not _peer_buffers.has(pid):
			_peer_buffers[pid] = ""
		_peer_buffers[pid] += chunk

		# Process complete lines
		while "\n" in _peer_buffers[pid]:
			var parts = _peer_buffers[pid].split("\n", true, 1) # Split at first newline
			var line = parts[0]
			_peer_buffers[pid] = parts[1] # Remainder

			if line.strip_edges() != "":
				var parse = JSON.parse(line)
				if parse.error == OK and typeof(parse.result) == TYPE_DICTIONARY:
					_on_data_received(peer, parse.result)
				else:
					print("[ANNA] Malformed JSON action received: ", line.substr(0, 50))

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

# --- RL LOCK-STEP MODE ---

func _handle_rl_peer_sync(peer: StreamPeerTCP):
	# 1. Send Observation (Current State)
	var obs = _interface.get_rl_observation()
	_send_json(peer, obs)

	# 2. Block until Action or Reset command received
	while true:
		var msg = _read_json_message_blocking(peer)
		if msg == null:
			# Connection likely closed or error
			_disconnect_peer(peer)
			return

		var cmd_value = ""
		if msg.has("command"):
			cmd_value = str(msg["command"]).to_upper()
		elif msg.has("type"):
			cmd_value = str(msg["type"]).to_upper()

		if cmd_value == "RESET":
			# Handle Reset immediately
			print("[ANNA] Resetting Simulation via TCP Command")
			_interface.reset_simulation()
			# IMPORTANT: Send fresh observation for the reset state
			obs = _interface.get_rl_observation()
			# Reset reward to 0 for the first frame after reset
			obs["reward"] = 0.0
			obs["done"] = false
			_send_json(peer, obs)
			# Continue waiting for the first action of the new episode
			continue

		elif msg.has("action"):
			var action_idx = int(msg["action"])
			_interface.apply_rl_action(action_idx)
			# Done processing this frame
			break

		else:
			print("[ANNA] Unknown RL command: ", msg)
			# For robustness, we treat unknown commands as no-op and wait for next
			# Or break to avoid freeze?
			# Ideally, wait for valid action.
			pass

func _read_json_message_blocking(peer: StreamPeerTCP):
	var pid = peer.get_instance_id()
	if not _peer_buffers.has(pid):
		_peer_buffers[pid] = ""

	var started_ms := OS.get_ticks_msec()
	# Loop until we have a full line
	while not "\n" in _peer_buffers[pid]:
		# Check connection status
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return null
		if OS.get_ticks_msec() - started_ms > _rl_read_timeout_ms:
			print("[ANNA] RL read timeout (%dms), dropping peer." % _rl_read_timeout_ms)
			return null

		var bytes = peer.get_available_bytes()
		if bytes > 0:
			var chunk = peer.get_utf8_string(bytes) # Read all available
			_peer_buffers[pid] += chunk
		else:
			# Optional polling backoff; set to 0 for max-throughput RL runs.
			if _rl_poll_sleep_usec > 0:
				OS.delay_usec(_rl_poll_sleep_usec)

	# Extract line
	var parts = _peer_buffers[pid].split("\n", true, 1)
	var line = parts[0]
	_peer_buffers[pid] = parts[1]

	if line.strip_edges() == "":
		return {} # Empty line, maybe just newline sent?

	var parse = JSON.parse(line)
	if parse.error == OK and typeof(parse.result) == TYPE_DICTIONARY:
		return parse.result
	else:
		print("[ANNA] JSON Parse Error: ", line)
		return {}

func _send_json(peer: StreamPeerTCP, data: Dictionary):
	var json_str = JSON.print(data)
	peer.put_data((json_str + "\n").to_utf8())

func _on_data_received(peer: StreamPeerTCP, message: Dictionary) -> void:
	var mcp_req = _normalize_mcp_request(message)
	if bool(mcp_req.get("is_mcp", false)):
		var cmd = str(mcp_req.get("command", ""))
		var args = mcp_req.get("args", {})
		if typeof(args) != TYPE_DICTIONARY:
			args = {}
		var result = _run_mcp_command(cmd, args)
		_send_mcp_result(peer, mcp_req, result)
		return
	_interface.apply_action(message)

func _normalize_mcp_request(message: Dictionary) -> Dictionary:
	var req = {
		"is_mcp": false,
		"id": message.get("id", ""),
		"command": "",
		"args": {}
	}
	var payload: Dictionary = message
	var msg_type = str(message.get("type", "")).to_lower()
	if msg_type == "mcp_cmd":
		req["is_mcp"] = true
		if typeof(message.get("payload", {})) == TYPE_DICTIONARY:
			payload = message.get("payload", {})
	elif message.has("resource") and str(message.get("resource", "")).begins_with("odisea://"):
		req["is_mcp"] = true
	elif message.has("tool"):
		req["is_mcp"] = true
	elif message.has("action") and _is_known_mcp_command(str(message["action"])):
		req["is_mcp"] = true
	else:
		return req

	if message.has("request_id"):
		req["id"] = message["request_id"]
	if payload.has("request_id"):
		req["id"] = payload["request_id"]
	if payload.has("id"):
		req["id"] = payload["id"]

	var command = ""
	if payload.has("action"):
		command = str(payload["action"])
	elif payload.has("tool"):
		command = str(payload["tool"])
	elif payload.has("name"):
		command = str(payload["name"])
	elif payload.has("resource"):
		command = str(payload["resource"])
	req["command"] = command

	var args = {}
	if typeof(payload.get("args", null)) == TYPE_DICTIONARY:
		args = payload["args"]
	elif typeof(payload.get("arguments", null)) == TYPE_DICTIONARY:
		args = payload["arguments"]
	else:
		args = payload.duplicate(true)
	if typeof(args) == TYPE_DICTIONARY:
		args.erase("action")
		args.erase("tool")
		args.erase("name")
		args.erase("resource")
		args.erase("id")
		args.erase("request_id")
		args.erase("args")
		args.erase("arguments")
	req["args"] = args
	return req

func _is_known_mcp_command(cmd: String) -> bool:
	var normalized = cmd.to_lower()
	return normalized in [
		"get_tree",
		"inspect",
		"inspect_node",
		"oys_inject",
		"execute_oys",
		"capture_vision",
		"query_codex_docs",
		"odisea://scene/hierarchy",
		"odisea://simulation/telemetry",
		"odisea://olcs/logic-state"
	]

func _run_mcp_command(command: String, args: Dictionary) -> Dictionary:
	var cmd = command.strip_edges().to_lower()
	if cmd == "get_tree" or cmd == "scene_hierarchy" or cmd == "odisea://scene/hierarchy":
		return {
			"ok": true,
			"data": _interface.get_scene_hierarchy_resource(
				args.get("max_depth", args.get("depth_limit", 4)),
				args.get("max_children", args.get("child_limit", 24))
			)
		}

	if cmd == "simulation_telemetry" or cmd == "get_telemetry" or cmd == "odisea://simulation/telemetry":
		return {
			"ok": true,
			"data": _interface.get_simulation_telemetry_resource()
		}

	if cmd == "logic_state" or cmd == "olcs_logic_state" or cmd == "odisea://olcs/logic-state":
		return {
			"ok": true,
			"data": _interface.get_olcs_logic_state_resource()
		}

	if cmd == "inspect" or cmd == "inspect_node":
		var path = str(args.get("node_path", args.get("path", "")))
		var payload = _interface.inspect_node(path)
		return {
			"ok": bool(payload.get("ok", false)),
			"data": payload
		}

	if cmd == "oys_inject" or cmd == "execute_oys":
		var script_command = str(args.get("script_command", args.get("command", "")))
		var payload = _interface.execute_oys(script_command)
		return {
			"ok": bool(payload.get("ok", false)),
			"data": payload
		}

	if cmd == "capture_vision":
		return {
			"ok": true,
			"data": _interface.capture_vision(args)
		}

	if cmd == "query_codex_docs":
		var topic = str(args.get("topic", args.get("q", "")))
		return {
			"ok": true,
			"data": _interface.query_codex_docs(topic, int(args.get("max_matches", 20)))
		}

	return {
		"ok": false,
		"error": "unknown_mcp_command",
		"command": command
	}

func _send_mcp_result(peer: StreamPeerTCP, request: Dictionary, result: Dictionary) -> void:
	var ok = bool(result.get("ok", false))
	var payload = {
		"type": MCP_RESULT_TYPE if ok else MCP_ERROR_TYPE,
		"id": request.get("id", ""),
		"ok": ok
	}
	if ok:
		payload["data"] = result.get("data", {})
	else:
		payload["error"] = result.get("error", "mcp_failed")
		payload["command"] = result.get("command", request.get("command", ""))
		if result.has("data"):
			payload["data"] = result["data"]
	_send_json(peer, payload)

func _replace_rl_peer(new_peer: StreamPeerTCP) -> void:
	for peer in _peers:
		_disconnect_peer(peer)
	_peers.clear()
	_peers.append(new_peer)

func _disconnect_peer(peer: StreamPeerTCP) -> void:
	if not peer:
		return
	var pid = peer.get_instance_id()
	if _peer_buffers.has(pid):
		_peer_buffers.erase(pid)
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.disconnect_from_host()
