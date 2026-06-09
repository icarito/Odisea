extends Reference

const PEER_PORT := 4999
const SERVER_PORT := 5001
const HEARTBEAT_INTERVAL_MS := 100
const RECONNECT_INTERVAL_MS := 2000
# Dev-only fallback secret; PRODUCTION must set ODISEA_BRIDGE_TOKEN in the environment.
const DEV_DEFAULT_TOKEN := "odisea-dev-insecure"
const DEFAULT_CENTRAL := "35.182.238.36:5003"

var _thread: Thread
var _stop_thread := false
var _mutex := Mutex.new()

var _client: WebSocketClient
var _server: WebSocketServer
var _server_enabled := false

var _command_queue # Reference to ANNAV2_CommandQueue
var _is_connected := false
var _peer_url := ""
var _central_url := ""
var _bridge_token := ""
var _central_enabled := true

var player_id := ""
var session_id := ""
var game_version := "0.1.0"

var _last_telemetry := {}
var _heartbeat_counter := 0
var _heartbeat_interval_ms := 100
var _throttle_tier := 3

func update_heartbeat_params(interval_ms: int, tier: int):
	_mutex.lock()
	_heartbeat_interval_ms = interval_ms
	_throttle_tier = tier
	_mutex.unlock()

func _init():
	_client = WebSocketClient.new()
	_client.connect("connection_established", self, "_on_connected")
	_client.connect("connection_closed", self, "_on_disconnected")
	_client.connect("connection_error", self, "_on_disconnected")
	_client.connect("data_received", self, "_on_data")

	# WebSocketServer is not instantiable on HTML5 (a browser can't be a server) and is only
	# used when explicitly enabled, so create it lazily and never on web.
	_server_enabled = OS.get_environment("ANNA_V2_SERVER_ENABLED") in ["1", "true", "yes", "on"]
	if _server_enabled and not OS.has_feature("web"):
		_server = WebSocketServer.new()
	else:
		_server_enabled = false

	_bridge_token = OS.get_environment("ODISEA_BRIDGE_TOKEN")
	if _bridge_token == "":
		_bridge_token = DEV_DEFAULT_TOKEN
	var central_env = OS.get_environment("ANNA_V2_CENTRAL")
	if central_env == "":
		central_env = DEFAULT_CENTRAL
	_central_url = "ws://" + central_env + "/ws"
	# Privacy/production: set ANNA_V2_NO_CENTRAL=1 to never phone home to the central.
	_central_enabled = not (OS.get_environment("ANNA_V2_NO_CENTRAL") in ["1", "true", "yes", "on"])

func start(command_queue, p_id, s_id, g_ver):
	_command_queue = command_queue
	player_id = p_id
	session_id = s_id
	game_version = g_ver

	_thread = Thread.new()
	_thread.start(self, "_thread_func")

func stop():
	_mutex.lock()
	_stop_thread = true
	_mutex.unlock()
	if _thread:
		_thread.wait_to_finish()

func update_telemetry(data: Dictionary):
	_mutex.lock()
	_last_telemetry = data
	_mutex.unlock()

func _thread_func(_userdata):
	var last_heartbeat = 0
	var last_reconnect = 0

	if _server_enabled:
		_server.listen(SERVER_PORT)
		print("[ANNAV2] WebSocket server listening on port ", SERVER_PORT)

	while true:
		_mutex.lock()
		var should_stop = _stop_thread
		_mutex.unlock()
		if should_stop:
			break

		var now = OS.get_ticks_msec()

		if not _is_connected:
			if now - last_reconnect > RECONNECT_INTERVAL_MS:
				_attempt_connection()
				last_reconnect = now
		else:
			_mutex.lock()
			var interval = _heartbeat_interval_ms
			var tier = _throttle_tier
			_mutex.unlock()
			
			if interval > 0 and now - last_heartbeat > interval:
				_send_heartbeat(tier)
				last_heartbeat = now

		_client.poll()
		if _server_enabled:
			_server.poll()

		OS.delay_msec(10)

	_client.disconnect_from_host()
	if _server_enabled:
		_server.stop()

func _attempt_connection():
	if _peer_url == "":
		_peer_url = _discover_peer()

	if _peer_url != "":
		print("[ANNAV2] Attempting to connect to peer: ", _peer_url)
		_client.connect_to_url(_peer_url)

func _discover_peer() -> String:
	# 1. Check ENV override
	var env_bridge = OS.get_environment("ANNA_V2_BRIDGE")
	if env_bridge != "":
		return "ws://" + env_bridge + "/ws"

	# 2. HTML5 check (URL params handled by Autoload and passed here)
	if OS.has_feature("web"):
		# Default for web if not specified
		return "ws://localhost:4999/ws"

	# 3. Try localhost
	if _check_port("127.0.0.1", PEER_PORT):
		return "ws://127.0.0.1:4999/ws"

	# 4. Try own local IP addresses (faster than subnet scan)
	var addresses = IP.get_local_addresses()
	for addr in addresses:
		if addr.find(":") != -1: continue # Skip IPv6
		if addr.begins_with("127."): continue
		if addr.begins_with("169.254"): continue # Skip link-local

		if _check_port(addr, PEER_PORT):
			return "ws://" + addr + ":4999/ws"

	# 5. Optional full subnet scan (slow, enabled by env)
	var allow_full_scan = OS.get_environment("ANNA_V2_FULL_SCAN") in ["1", "true", "yes", "on"]
	if allow_full_scan:
		for addr in addresses:
			if addr.find(":") != -1: continue
			if addr.begins_with("127."): continue
			if addr.begins_with("169.254"): continue

			var parts = addr.split(".")
			if parts.size() != 4: continue

			var base = parts[0] + "." + parts[1] + "." + parts[2] + "."
			for i in range(1, 255):
				_mutex.lock()
				var should_stop = _stop_thread
				_mutex.unlock()
				if should_stop: return ""

				var target = base + str(i)
				if target == addr: continue # already checked
				if _check_port(target, PEER_PORT):
					return "ws://" + target + ":4999/ws"

	# No local peer found: fall back to the central node so telemetry still flows for
	# observability. Auth uses ODISEA_BRIDGE_TOKEN (dev default if unset) — see docs for
	# production hardening (ANNA_V2_CENTRAL to override the host, ANNA_V2_NO_CENTRAL to opt out).
	if not _central_enabled:
		return ""
	print("[ANNAV2] No local peer found; falling back to central: ", _central_url)
	return _central_url

func _check_port(ip: String, port: int) -> bool:
	var tcp = StreamPeerTCP.new()
	var err = tcp.connect_to_host(ip, port)
	if err != OK: return false

	var start_time = OS.get_ticks_msec()
	while tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and OS.get_ticks_msec() - start_time < 50:
		OS.delay_msec(1)

	var ok = tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED
	tcp.disconnect_from_host()
	return ok

func _on_connected(_protocol = ""):
	_is_connected = true
	# Send JSON as TEXT frames (WS convention); avoids peers that only handle text.
	_client.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	print("[ANNAV2] Connected to peer")
	_send_handshake()

func _on_disconnected(_was_clean = false):
	_is_connected = false
	print("[ANNAV2] Disconnected from peer")

func _on_data():
	var packet = _client.get_peer(1).get_packet()
	var text = packet.get_string_from_utf8()
	var result = JSON.parse(text)
	if result.error == OK and typeof(result.result) == TYPE_DICTIONARY:
		var msg = result.result
		var type = msg.get("type")
		if type == "handshake_ack":
			print("[ANNAV2] Handshake ACK received")
		elif type == "command":
			var action = msg.get("action")
			var args = msg.get("args", {})
			var cmd_id = msg.get("id", "unknown")
			_command_queue.push({
				"action": action,
				"args": args,
				"id": cmd_id
			})

func _send_handshake():
	var platform = "desktop"
	if OS.has_feature("web"): platform = "web"
	elif OS.has_feature("android"): platform = "android"
	elif OS.has_feature("ios"): platform = "ios"

	var msg = {
		"type": "handshake",
		"platform": platform,
		"player_id": player_id,
		"session_id": session_id
	}
	# Token is required by the central node; the local peer ignores it. peer_id lets the
	# central attribute the connection.
	if _bridge_token != "":
		msg["token"] = _bridge_token
		msg["peer_id"] = player_id
	_send_json(msg)

func _send_heartbeat(tier: int):
	_mutex.lock()
	var player_data = _last_telemetry.get("player", {})
	_mutex.unlock()

	_heartbeat_counter += 1

	var msg = {
		"schema_version": 1,
		"type": "heartbeat",
		"player_id": player_id,
		"session_id": session_id,
		"host": OS.get_name(),
		"godot_version": Engine.get_version_info().string,
		"game_version": game_version,
		"platform": OS.get_name(),
		"timestamp": OS.get_unix_time()
	}
	
	var player_msg = {
		"fps": player_data.get("fps", 0)
	}
	
	if tier >= 2 and _heartbeat_counter % 10 == 0:
		player_msg["position"] = player_data.get("position", [0, 0, 0])
		player_msg["yaw"] = player_data.get("yaw", 0.0)
		player_msg["scene"] = player_data.get("scene", "")
		player_msg["zone"] = player_data.get("zone", "")
		
	if tier >= 3 and _heartbeat_counter % 100 == 0:
		player_msg["velocity"] = player_data.get("velocity", [0, 0, 0])
		player_msg["pitch"] = player_data.get("pitch", 0.0)
		player_msg["roll"] = player_data.get("roll", 0.0)
		player_msg["mode"] = player_data.get("mode", "standard")
		player_msg["tick"] = player_data.get("tick", 0)
		player_msg["memory_mb"] = player_data.get("memory_mb", 0.0)
		
	msg["player"] = player_msg
	_send_json(msg)

func _send_json(msg: Dictionary):
	if _is_connected:
		_client.get_peer(1).put_packet(JSON.print(msg).to_utf8())

func send_command_response(response: Dictionary):
	_send_json(response)
