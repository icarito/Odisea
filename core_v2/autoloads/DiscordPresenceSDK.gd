extends Node

# DiscordPresenceSDK.gd
# Pure GDScript IPC Client for Discord Rich Presence.
# Communicates with local Discord desktop client via local IPC socket (Unix Domain Socket / Windows Named Pipe).
# Zero external native C++/GDExtension/GDNative dependencies.

const DEFAULT_APP_ID := "1342571230000000000" # Target Application ID (overridable)

enum Opcode {
	HANDSHAKE = 0,
	FRAME = 1,
	CLOSE = 2,
	PING = 3,
	PONG = 4
}

var _app_id: String = DEFAULT_APP_ID
var _is_connected: bool = false
var _peer: StreamPeer = null
var _file_peer: File = null # Fallback / Windows named pipe handle if applicable
var _nonce_counter: int = 0
var _ipc_path: String = ""

# Mock mode for testing/headless CI
var _mock_mode: bool = false
var _last_mock_activity: Dictionary = {}

func set_app_id(app_id: String) -> void:
	_app_id = app_id

func is_connected_to_discord() -> bool:
	return _is_connected or _mock_mode

func enable_mock_mode(enabled: bool = true) -> void:
	_mock_mode = enabled
	if enabled:
		_is_connected = true

func get_last_mock_activity() -> Dictionary:
	return _last_mock_activity

func connect_to_discord() -> bool:
	if _mock_mode:
		_is_connected = true
		return true

	if _is_connected:
		return true

	_ipc_path = _find_discord_ipc_path()
	if _ipc_path == "":
		return false

	if _ipc_path.begins_with("\\\\") or _ipc_path.find("pipe") != -1:
		# Windows Named Pipe
		var file = File.new()
		var err = file.open(_ipc_path, File.READ_WRITE)
		if err != OK:
			return false
		_file_peer = file
		_is_connected = true
	else:
		# POSIX Unix Domain Socket
		if ClassDB.class_exists("StreamPeerUnix"):
			var unix_peer = ClassDB.instance("StreamPeerUnix") as StreamPeer
			if unix_peer and unix_peer.has_method("connect_to_path"):
				var err = unix_peer.call("connect_to_path", _ipc_path)
				if err == OK:
					_peer = unix_peer
					_is_connected = true
		if not _is_connected:
			# Fallback via File if StreamPeerUnix is not available
			var file = File.new()
			if file.file_exists(_ipc_path):
				var err = file.open(_ipc_path, File.READ_WRITE)
				if err == OK:
					_file_peer = file
					_is_connected = true

	if not _is_connected:
		return false

	# Send Opcode 0 HANDSHAKE
	var handshake_payload = {
		"v": 1,
		"client_id": _app_id
	}
	if not _send_packet(Opcode.HANDSHAKE, handshake_payload):
		disconnect_from_discord()
		return false

	# Read handshake response if available
	_read_available_data()
	return true

func disconnect_from_discord() -> void:
	if _mock_mode:
		_is_connected = false
		return

	if _is_connected and (_peer != null or _file_peer != null):
		_send_packet(Opcode.CLOSE, {})

	if _peer != null:
		if _peer.has_method("close"):
			_peer.call("close")
		_peer = null

	if _file_peer != null:
		_file_peer.close()
		_file_peer = null

	_is_connected = false

func set_activity(activity_dict: Dictionary) -> bool:
	if _mock_mode:
		_last_mock_activity = activity_dict.duplicate(true)
		return true

	if not _is_connected:
		if not connect_to_discord():
			return false

	_nonce_counter += 1
	var payload = {
		"cmd": "SET_ACTIVITY",
		"args": {
			"pid": OS.get_process_id(),
			"activity": activity_dict
		},
		"nonce": str(_nonce_counter)
	}

	return _send_packet(Opcode.FRAME, payload)

func clear_activity() -> bool:
	if _mock_mode:
		_last_mock_activity = {}
		return true

	if not _is_connected:
		return true

	_nonce_counter += 1
	var payload = {
		"cmd": "SET_ACTIVITY",
		"args": {
			"pid": OS.get_process_id(),
			"activity": null
		},
		"nonce": str(_nonce_counter)
	}

	return _send_packet(Opcode.FRAME, payload)

func _send_packet(opcode: int, payload: Dictionary) -> bool:
	if not _is_connected:
		return false

	var json_str = JSON.print(payload)
	var utf8_bytes = json_str.to_utf8()
	var payload_len = utf8_bytes.size()

	var header = StreamPeerBuffer.new()
	header.big_endian = false
	header.put_u32(opcode)
	header.put_u32(payload_len)

	var header_bytes = header.data_array

	if _peer != null:
		var err1 = _peer.put_data(header_bytes)
		var err2 = _peer.put_data(utf8_bytes)
		if err1 != OK or err2 != OK:
			disconnect_from_discord()
			return false
		return true
	elif _file_peer != null:
		_file_peer.store_buffer(header_bytes)
		_file_peer.store_buffer(utf8_bytes)
		_file_peer.flush()
		return true

	return false

func _read_available_data() -> void:
	# Drain input buffer non-blocking
	if _peer != null and _peer.has_method("get_available_bytes"):
		var avail = int(_peer.call("get_available_bytes"))
		if avail > 0:
			_peer.get_data(avail)

func _find_discord_ipc_path() -> String:
	var f = File.new()

	if OS.get_name() == "Windows":
		for i in range(10):
			var pipe_path = "\\\\.\\pipe\\discord-ipc-" + str(i)
			if f.file_exists(pipe_path):
				return pipe_path
		return ""

	# Linux / macOS / POSIX
	var search_dirs = []
	var xdg_runtime = OS.get_environment("XDG_RUNTIME_DIR")
	if xdg_runtime != "":
		search_dirs.append(xdg_runtime)

	var tmpdir = OS.get_environment("TMPDIR")
	if tmpdir != "":
		search_dirs.append(tmpdir)

	search_dirs.append("/tmp")
	search_dirs.append("/var/tmp")

	for dir_path in search_dirs:
		if dir_path == "":
			continue
		for i in range(10):
			var socket_path = dir_path.plus_file("discord-ipc-" + str(i))
			if f.file_exists(socket_path):
				return socket_path

	return ""
