extends Node

const PORT = 5000
const MAX_READ_BYTES_PER_TICK = 16384
const RL_UNCAPPED_PHYSICS_FPS = 2000
const RL_MAX_PHYSICS_FPS_HARD_CAP = 10000
const RL_DEFAULT_POLL_SLEEP_USEC = 1000
const RL_BINARY_OBS_FLOATS = 13 # 12 obs + reward
const RL_BINARY_OBS_SIZE = RL_BINARY_OBS_FLOATS * 4 + 1 # + done byte
const MCP_RESULT_TYPE = "mcp_result"
const MCP_ERROR_TYPE = "mcp_error"
var _server: TCP_Server
var _peers := []
var _interface: Node
var _peer_buffers := {} # { peer_instance_id: String }
var _rl_peer_states := {} # { peer_instance_id: Dictionary }
var is_rl_mode := false
var _rl_read_timeout_ms := 15000
var _rl_poll_sleep_usec := RL_DEFAULT_POLL_SLEEP_USEC
var _rl_binary_protocol := false
var _rl_blocking_sync := false
var _rl_blocking_poll_usec := 10
var _rl_profile_enabled := false
var _rl_profile_every_steps := 500
var _rl_profile_step_count := 0
var _rl_profile_us_obs := 0
var _rl_profile_us_send := 0
var _rl_profile_us_wait := 0
var _rl_profile_us_apply := 0
var _rl_profile_ms_physics := 0.0
var _rl_profile_ms_process := 0.0
var _rl_profile_to_file := false
var _rl_profile_file_path := "user://anna_rl_profile.log"
var _rl_exit_on_disconnect := false
var _rl_exit_disconnect_grace_ms := 1500
var _rl_had_connected_peer := false
var _rl_disconnected_since_ms := -1

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
		_rl_binary_protocol = OS.get_environment("ANNA_RL_BINARY_PROTOCOL").to_lower() in ["1", "true", "yes", "on"]
		_rl_blocking_sync = OS.get_environment("ANNA_RL_BLOCKING_SYNC").to_lower() in ["1", "true", "yes", "on"]
		_rl_profile_enabled = OS.get_environment("ANNA_RL_PROFILE").to_lower() in ["1", "true", "yes", "on"]
		_rl_profile_to_file = OS.get_environment("ANNA_RL_PROFILE_TO_FILE").to_lower() in ["1", "true", "yes", "on"]
		var profile_file_env = OS.get_environment("ANNA_RL_PROFILE_FILE_PATH")
		if profile_file_env.strip_edges() != "":
			_rl_profile_file_path = profile_file_env
		var profile_every_env = OS.get_environment("ANNA_RL_PROFILE_EVERY")
		if profile_every_env.is_valid_integer():
			_rl_profile_every_steps = max(50, int(profile_every_env))
		print("[ANNA] RL Lock-Step Mode Enabled")
		OS.set_use_vsync(false)
		var disable_idle_sleep_env = OS.get_environment("ANNA_RL_DISABLE_CPU_SLEEP").to_lower()
		if disable_idle_sleep_env in ["1", "true", "yes", "on"]:
			OS.set_low_processor_usage_mode(false)
			OS.set_low_processor_usage_mode_sleep_usec(0)
		var target_fps = 0
		var target_fps_env = OS.get_environment("ANNA_RL_TARGET_FPS")
		if target_fps_env.is_valid_integer():
			target_fps = max(0, int(target_fps_env))
		Engine.target_fps = target_fps
		var physics_fps = 60
		var physics_fps_cap = RL_UNCAPPED_PHYSICS_FPS
		var physics_fps_cap_env = OS.get_environment("ANNA_RL_PHYSICS_FPS_CAP")
		if physics_fps_cap_env.is_valid_integer():
			physics_fps_cap = clamp(int(physics_fps_cap_env), RL_UNCAPPED_PHYSICS_FPS, RL_MAX_PHYSICS_FPS_HARD_CAP)
		var physics_fps_env = OS.get_environment("ANNA_RL_PHYSICS_FPS")
		if physics_fps_env.is_valid_integer():
			var requested_physics_fps = int(physics_fps_env)
			if requested_physics_fps <= 0:
				physics_fps = physics_fps_cap
			else:
				physics_fps = max(30, min(requested_physics_fps, physics_fps_cap))
		Engine.iterations_per_second = physics_fps
		var max_physics_steps = -1
		var max_steps_env = OS.get_environment("ANNA_RL_MAX_PHYSICS_STEPS_PER_FRAME")
		if max_steps_env.is_valid_integer():
			max_physics_steps = max(8, int(max_steps_env))
		if max_physics_steps > 0 and ProjectSettings.has_setting("physics/common/max_physics_steps_per_frame"):
			ProjectSettings.set_setting("physics/common/max_physics_steps_per_frame", max_physics_steps)
		var jitter_fix = -1.0
		var jitter_fix_env = OS.get_environment("ANNA_RL_PHYSICS_JITTER_FIX")
		if jitter_fix_env.is_valid_float():
			jitter_fix = clamp(float(jitter_fix_env), 0.0, 1.0)
		if jitter_fix >= 0.0 and ProjectSettings.has_setting("physics/common/physics_jitter_fix"):
			ProjectSettings.set_setting("physics/common/physics_jitter_fix", jitter_fix)
		var max_steps_msg = "default"
		if max_physics_steps > 0:
			max_steps_msg = str(max_physics_steps)
		var jitter_msg = "default"
		if jitter_fix >= 0.0:
			jitter_msg = "%.3f" % jitter_fix
		print("[ANNA] RL engine: target_fps=%d physics=%dHz max_phys_steps=%s jitter_fix=%s" % [
			target_fps, physics_fps, max_steps_msg, jitter_msg
		])
		var read_timeout_env = OS.get_environment("ANNA_RL_READ_TIMEOUT_MS")
		if read_timeout_env.is_valid_integer():
			_rl_read_timeout_ms = max(1000, int(read_timeout_env))
		var poll_sleep_env = OS.get_environment("ANNA_RL_POLL_SLEEP_USEC")
		if poll_sleep_env.is_valid_integer():
			_rl_poll_sleep_usec = max(0, int(poll_sleep_env))
		elif disable_idle_sleep_env in ["1", "true", "yes", "on"]:
			_rl_poll_sleep_usec = 0
			var blocking_poll_env = OS.get_environment("ANNA_RL_BLOCKING_POLL_USEC")
			if blocking_poll_env.is_valid_integer():
				_rl_blocking_poll_usec = max(0, int(blocking_poll_env))
			var exit_on_disconnect_env = OS.get_environment("ANNA_RL_EXIT_ON_DISCONNECT").to_lower()
			if exit_on_disconnect_env in ["0", "false", "no", "off"]:
				_rl_exit_on_disconnect = false
			var exit_grace_env = OS.get_environment("ANNA_RL_EXIT_ON_DISCONNECT_GRACE_MS")
			if exit_grace_env.is_valid_integer():
				_rl_exit_disconnect_grace_ms = max(0, int(exit_grace_env))
			print("[ANNA] RL poll sleep=%dus timeout=%dms" % [_rl_poll_sleep_usec, _rl_read_timeout_ms])
			print("[ANNA] RL sync mode=%s" % ["blocking" if _rl_blocking_sync else "nonblocking"])
			if _rl_blocking_sync:
				print("[ANNA] RL blocking poll=%dus timeout=%dms" % [_rl_blocking_poll_usec, _rl_read_timeout_ms])
			print("[ANNA] RL protocol=%s" % ["binary" if _rl_binary_protocol else "json"])
			print("[ANNA] RL exit_on_disconnect=%s grace_ms=%d" % [str(_rl_exit_on_disconnect), _rl_exit_disconnect_grace_ms])
			if _rl_profile_enabled:
				print("[ANNA] RL profiling enabled (every %d steps)" % _rl_profile_every_steps)
				if _rl_profile_to_file:
					_append_text_line(_rl_profile_file_path, "[ANNA][RL_PROFILE] start")

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
			if is_rl_mode:
				_rl_had_connected_peer = true
				_rl_disconnected_since_ms = -1
			print("[ANNA] Client connected: %s" % peer.get_connected_host())

	# Process peers
	var active_peers = []
	for peer in _peers:
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if is_rl_mode:
				if _rl_blocking_sync:
					_handle_rl_peer_sync_blocking(peer)
				else:
					_handle_rl_peer_sync_nonblocking(peer)
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
			if _rl_peer_states.has(pid):
				_rl_peer_states.erase(pid)
		_peers = active_peers
		_maybe_exit_rl_on_disconnect()

func _exit_tree():
	for peer in _peers:
		if peer and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
	_peers.clear()
	_peer_buffers.clear()
	_rl_peer_states.clear()
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

func _new_rl_peer_state() -> Dictionary:
	return {
		"waiting_action": false,
		"waiting_since_ms": 0,
		"wait_start_us": 0,
		"obs_us": 0,
		"send_us": 0
	}

func _handle_rl_peer_sync_blocking(peer: StreamPeerTCP) -> void:
	if _rl_binary_protocol:
		_handle_rl_peer_sync_binary_blocking(peer)
	else:
		_handle_rl_peer_sync_json_blocking(peer)

func _handle_rl_peer_sync_json_blocking(peer: StreamPeerTCP) -> void:
	var t_obs_0 = OS.get_ticks_usec()
	var obs = _interface.get_rl_observation()
	var t_obs_1 = OS.get_ticks_usec()
	_send_json(peer, obs)
	var t_send_1 = OS.get_ticks_usec()

	while true:
		var t_wait_0 = OS.get_ticks_usec()
		var msg = _read_json_message_blocking(peer)
		var t_wait_1 = OS.get_ticks_usec()
		if msg == null:
			_disconnect_peer(peer)
			return

		var wait_us = max(0, t_wait_1 - t_wait_0)
		var cmd_value = ""
		if msg.has("command"):
			cmd_value = str(msg["command"]).to_upper()
		elif msg.has("type"):
			cmd_value = str(msg["type"]).to_upper()

		if cmd_value == "RESET":
			print("[ANNA] Resetting Simulation via TCP Command")
			_interface.reset_simulation()
			var t_reset_obs_0 = OS.get_ticks_usec()
			var reset_obs = _interface.get_rl_observation()
			var t_reset_obs_1 = OS.get_ticks_usec()
			reset_obs["reward"] = 0.0
			reset_obs["done"] = false
			_send_json(peer, reset_obs)
			var t_reset_send_1 = OS.get_ticks_usec()
			t_obs_0 = t_reset_obs_0
			t_obs_1 = t_reset_obs_1
			t_send_1 = t_reset_send_1
			continue

		if msg.has("action"):
			var action_idx = int(msg["action"])
			var t_apply_0 = OS.get_ticks_usec()
			_interface.apply_rl_action(action_idx)
			var apply_us = OS.get_ticks_usec() - t_apply_0
			_rl_profile_add(
				t_obs_1 - t_obs_0,
				t_send_1 - t_obs_1,
				wait_us,
				apply_us
			)
			break

		print("[ANNA] Unknown RL command: ", msg)

func _read_json_message_blocking(peer: StreamPeerTCP):
	var pid = peer.get_instance_id()
	if not _peer_buffers.has(pid):
		_peer_buffers[pid] = ""

	var started_ms := OS.get_ticks_msec()
	while not "\n" in _peer_buffers[pid]:
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return null
		if _rl_read_timeout_ms > 0 and OS.get_ticks_msec() - started_ms > _rl_read_timeout_ms:
			print("[ANNA] RL read timeout (%dms), dropping peer." % _rl_read_timeout_ms)
			return null

		var bytes = peer.get_available_bytes()
		if bytes > 0:
			var chunk = peer.get_utf8_string(min(bytes, MAX_READ_BYTES_PER_TICK))
			_peer_buffers[pid] += chunk
		elif _rl_blocking_poll_usec > 0:
			OS.delay_usec(_rl_blocking_poll_usec)

	var parts = _peer_buffers[pid].split("\n", true, 1)
	var line = parts[0]
	_peer_buffers[pid] = parts[1]

	if line.strip_edges() == "":
		return {}

	var parse = JSON.parse(line)
	if parse.error == OK and typeof(parse.result) == TYPE_DICTIONARY:
		return parse.result
	print("[ANNA] JSON Parse Error: ", line)
	return {}

func _handle_rl_peer_sync_binary_blocking(peer: StreamPeerTCP) -> void:
	var t_obs_0 = OS.get_ticks_usec()
	var obs = _interface.get_rl_observation()
	var t_obs_1 = OS.get_ticks_usec()
	_send_rl_binary_observation(peer, obs)
	var t_send_1 = OS.get_ticks_usec()

	while true:
		var t_wait_0 = OS.get_ticks_usec()
		var cmd = _read_binary_command_blocking(peer)
		var t_wait_1 = OS.get_ticks_usec()
		if cmd < 0:
			_disconnect_peer(peer)
			return

		var wait_us = max(0, t_wait_1 - t_wait_0)
		if cmd == 255:
			_interface.reset_simulation()
			var t_reset_obs_0 = OS.get_ticks_usec()
			var reset_obs = _interface.get_rl_observation()
			var t_reset_obs_1 = OS.get_ticks_usec()
			reset_obs["reward"] = 0.0
			reset_obs["done"] = false
			_send_rl_binary_observation(peer, reset_obs)
			var t_reset_send_1 = OS.get_ticks_usec()
			t_obs_0 = t_reset_obs_0
			t_obs_1 = t_reset_obs_1
			t_send_1 = t_reset_send_1
			continue

		var t_apply_0 = OS.get_ticks_usec()
		_interface.apply_rl_action(cmd)
		var apply_us = OS.get_ticks_usec() - t_apply_0
		_rl_profile_add(
			t_obs_1 - t_obs_0,
			t_send_1 - t_obs_1,
			wait_us,
			apply_us
		)
		break

func _read_binary_command_blocking(peer: StreamPeerTCP) -> int:
	var started_ms := OS.get_ticks_msec()
	while true:
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return -1
		if _rl_read_timeout_ms > 0 and OS.get_ticks_msec() - started_ms > _rl_read_timeout_ms:
			print("[ANNA] RL read timeout (%dms), dropping peer." % _rl_read_timeout_ms)
			return -1

		var available = peer.get_available_bytes()
		if available > 0:
			var read = peer.get_data(1)
			if read[0] != OK:
				return -1
			var payload: PoolByteArray = read[1]
			if payload.size() >= 1:
				return int(payload[0])
		elif _rl_blocking_poll_usec > 0:
			OS.delay_usec(_rl_blocking_poll_usec)
	return -1

func _handle_rl_peer_sync_nonblocking(peer: StreamPeerTCP):
	if _rl_binary_protocol:
		_handle_rl_peer_sync_binary_nonblocking(peer)
		return

	var pid = peer.get_instance_id()
	if not _rl_peer_states.has(pid):
		_rl_peer_states[pid] = _new_rl_peer_state()
	var state: Dictionary = _rl_peer_states[pid]

	if not bool(state.get("waiting_action", false)):
		_rl_send_observation_json(peer, state)
		return

	if _rl_is_wait_timed_out(state):
		print("[ANNA] RL read timeout (%dms), dropping peer." % _rl_read_timeout_ms)
		_disconnect_peer(peer)
		return

	var t_read = OS.get_ticks_usec()
	var msg = _try_read_json_message_nonblocking(peer)
	if msg == null:
		return

	var wait_us = max(0, t_read - int(state.get("wait_start_us", t_read)))
	var cmd_value = ""
	if msg.has("command"):
		cmd_value = str(msg["command"]).to_upper()
	elif msg.has("type"):
		cmd_value = str(msg["type"]).to_upper()

	if cmd_value == "RESET":
		print("[ANNA] Resetting Simulation via TCP Command")
		_interface.reset_simulation()
		_rl_send_observation_json(peer, state, true)
		return

	if msg.has("action"):
		var action_idx = int(msg["action"])
		var t_apply_0 = OS.get_ticks_usec()
		_interface.apply_rl_action(action_idx)
		var apply_us = OS.get_ticks_usec() - t_apply_0
		_rl_profile_add(
			int(state.get("obs_us", 0)),
			int(state.get("send_us", 0)),
			wait_us,
			apply_us
		)
		_rl_send_observation_json(peer, state)
		return

	print("[ANNA] Unknown RL command: ", msg)

func _rl_send_observation_json(peer: StreamPeerTCP, state: Dictionary, force_reset_reward := false) -> void:
	var t0 = OS.get_ticks_usec()
	var obs = _interface.get_rl_observation()
	var t1 = OS.get_ticks_usec()
	if force_reset_reward:
		obs["reward"] = 0.0
		obs["done"] = false
	_send_json(peer, obs)
	var t2 = OS.get_ticks_usec()
	state["waiting_action"] = true
	state["waiting_since_ms"] = OS.get_ticks_msec()
	state["wait_start_us"] = t2
	state["obs_us"] = t1 - t0
	state["send_us"] = t2 - t1
	_rl_peer_states[peer.get_instance_id()] = state

func _rl_is_wait_timed_out(state: Dictionary) -> bool:
	if _rl_read_timeout_ms <= 0:
		return false
	var since_ms = int(state.get("waiting_since_ms", 0))
	if since_ms <= 0:
		return false
	return (OS.get_ticks_msec() - since_ms) > _rl_read_timeout_ms

func _try_read_json_message_nonblocking(peer: StreamPeerTCP):
	var pid = peer.get_instance_id()
	if not _peer_buffers.has(pid):
		_peer_buffers[pid] = ""

	var bytes = peer.get_available_bytes()
	if bytes > 0:
		var chunk = peer.get_utf8_string(min(bytes, MAX_READ_BYTES_PER_TICK))
		_peer_buffers[pid] += chunk

	if not "\n" in _peer_buffers[pid]:
		return null

	var parts = _peer_buffers[pid].split("\n", true, 1)
	var line = parts[0]
	_peer_buffers[pid] = parts[1]

	if line.strip_edges() == "":
		return {}

	var parse = JSON.parse(line)
	if parse.error == OK and typeof(parse.result) == TYPE_DICTIONARY:
		return parse.result
	print("[ANNA] JSON Parse Error: ", line)
	return {}

func _send_json(peer: StreamPeerTCP, data: Dictionary):
	var json_str = JSON.print(data)
	peer.put_data((json_str + "\n").to_utf8())

func _handle_rl_peer_sync_binary_nonblocking(peer: StreamPeerTCP):
	var pid = peer.get_instance_id()
	if not _rl_peer_states.has(pid):
		_rl_peer_states[pid] = _new_rl_peer_state()
	var state: Dictionary = _rl_peer_states[pid]

	if not bool(state.get("waiting_action", false)):
		_rl_send_observation_binary(peer, state)
		return

	if _rl_is_wait_timed_out(state):
		print("[ANNA] RL read timeout (%dms), dropping peer." % _rl_read_timeout_ms)
		_disconnect_peer(peer)
		return

	var available = peer.get_available_bytes()
	if available <= 0:
		return

	var read = peer.get_data(1)
	if read[0] != OK:
		_disconnect_peer(peer)
		return
	var payload: PoolByteArray = read[1]
	if payload.size() < 1:
		return

	var cmd = int(payload[0])
	var t_read = OS.get_ticks_usec()
	var wait_us = max(0, t_read - int(state.get("wait_start_us", t_read)))
	if cmd == 255:
		_interface.reset_simulation()
		_rl_send_observation_binary(peer, state, true)
		return

	var t_apply_0 = OS.get_ticks_usec()
	_interface.apply_rl_action(cmd)
	var apply_us = OS.get_ticks_usec() - t_apply_0
	_rl_profile_add(
		int(state.get("obs_us", 0)),
		int(state.get("send_us", 0)),
		wait_us,
		apply_us
	)
	_rl_send_observation_binary(peer, state)

func _rl_send_observation_binary(peer: StreamPeerTCP, state: Dictionary, force_reset_reward := false) -> void:
	var t0 = OS.get_ticks_usec()
	var obs = _interface.get_rl_observation()
	var t1 = OS.get_ticks_usec()
	if force_reset_reward:
		obs["reward"] = 0.0
		obs["done"] = false
	_send_rl_binary_observation(peer, obs)
	var t2 = OS.get_ticks_usec()
	state["waiting_action"] = true
	state["waiting_since_ms"] = OS.get_ticks_msec()
	state["wait_start_us"] = t2
	state["obs_us"] = t1 - t0
	state["send_us"] = t2 - t1
	_rl_peer_states[peer.get_instance_id()] = state

func _send_rl_binary_observation(peer: StreamPeerTCP, data: Dictionary):
	var obs_raw = data.get("obs", [])
	var obs_array: Array = obs_raw if typeof(obs_raw) == TYPE_ARRAY else []
	var stream := StreamPeerBuffer.new()
	stream.big_endian = true
	for i in range(12):
		var v := 0.0
		if i < obs_array.size():
			v = float(obs_array[i])
		stream.put_float(v)
	stream.put_float(float(data.get("reward", 0.0)))
	stream.put_u8(1 if bool(data.get("done", false)) else 0)
	var payload: PoolByteArray = stream.data_array
	if payload.size() < RL_BINARY_OBS_SIZE:
		payload.resize(RL_BINARY_OBS_SIZE)
	peer.put_data(payload)

func _rl_profile_add(obs_us: int, send_us: int, wait_us: int, apply_us: int) -> void:
	if not _rl_profile_enabled:
		return
	_rl_profile_step_count += 1
	_rl_profile_us_obs += obs_us
	_rl_profile_us_send += send_us
	_rl_profile_us_wait += wait_us
	_rl_profile_us_apply += apply_us
	_rl_profile_ms_physics += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	_rl_profile_ms_process += float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	if _rl_profile_step_count % _rl_profile_every_steps != 0:
		return
	var n = float(_rl_profile_every_steps)
	var line = "[ANNA][RL_PROFILE] obs=%.1fus send=%.1fus wait=%.1fus apply=%.1fus total=%.1fus physics=%.3fms process=%.3fms ips=%d" % [
		_rl_profile_us_obs / n,
		_rl_profile_us_send / n,
		_rl_profile_us_wait / n,
		_rl_profile_us_apply / n,
		(_rl_profile_us_obs + _rl_profile_us_send + _rl_profile_us_wait + _rl_profile_us_apply) / n,
		_rl_profile_ms_physics / n,
		_rl_profile_ms_process / n,
		int(Engine.iterations_per_second)
	]
	print(line)
	if _rl_profile_to_file:
		_append_text_line(_rl_profile_file_path, line)
	_rl_profile_us_obs = 0
	_rl_profile_us_send = 0
	_rl_profile_us_wait = 0
	_rl_profile_us_apply = 0
	_rl_profile_ms_physics = 0.0
	_rl_profile_ms_process = 0.0

func _append_text_line(path: String, line: String) -> void:
	var f := File.new()
	var err = ERR_CANT_OPEN
	if f.file_exists(path):
		err = f.open(path, File.READ_WRITE)
		if err == OK:
			f.seek_end()
	else:
		err = f.open(path, File.WRITE)
	if err != OK:
		return
	f.store_line(line)
	f.close()

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
	_rl_peer_states[new_peer.get_instance_id()] = _new_rl_peer_state()

func _disconnect_peer(peer: StreamPeerTCP) -> void:
	if not peer:
		return
	var pid = peer.get_instance_id()
	if _peer_buffers.has(pid):
		_peer_buffers.erase(pid)
	if _rl_peer_states.has(pid):
		_rl_peer_states.erase(pid)
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.disconnect_from_host()

func _maybe_exit_rl_on_disconnect() -> void:
	if not is_rl_mode or not _rl_exit_on_disconnect:
		return
	if not _rl_had_connected_peer:
		return
	if _peers.size() > 0:
		_rl_disconnected_since_ms = -1
		return
	var now_ms = OS.get_ticks_msec()
	if _rl_disconnected_since_ms < 0:
		_rl_disconnected_since_ms = now_ms
		return
	var disconnected_for = now_ms - _rl_disconnected_since_ms
	if disconnected_for < _rl_exit_disconnect_grace_ms:
		return
	print("[ANNA] RL peer disconnected for %dms; exiting runtime (no live fallback)." % disconnected_for)
	_rl_exit_on_disconnect = false
	call_deferred("_quit_runtime_after_disconnect")

func _quit_runtime_after_disconnect() -> void:
	var tree = get_tree()
	if tree:
		tree.quit()
