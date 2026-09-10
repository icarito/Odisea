extends Node

# RemoteControlServer.gd - Handles WebSocket connections for control/handshake & UDP for high-frequency sensor streaming.

signal client_pair_requested(device_name, pin, callback)
signal client_connected(device_name)
signal client_disconnected(device_name)
signal input_received(input_type, payload)

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")

export var ws_port: int = 10443
export var sensor_udp_port: int = 10444
export var pairing_timeout: float = 30.0

var _ws_server = WebSocketServer.new()
var _sensor_udp = PacketPeerUDP.new()

var _server_started: bool = false
var _active_pin: String = ""
var _active_token: String = ""
# peer_id -> { device_name, paired: bool, token }
var _peers: Dictionary = {}
var _pairing_peer_id: int = -1
var _pairing_timer: float = 0.0

# Sensor streaming heartbeat tracking
var _last_sensor_timestamp: float = 0.0
var _sensor_active: bool = false
export var sensor_timeout: float = 2.0

func start_server(p_ws_port: int = 10443, p_sensor_port: int = 10444) -> bool:
	ws_port = p_ws_port
	sensor_udp_port = p_sensor_port

	_ws_server.connect("client_connected", self, "_on_ws_client_connected")
	_ws_server.connect("client_disconnected", self, "_on_ws_client_disconnected")
	_ws_server.connect("data_received", self, "_on_ws_data_received")

	var err = _ws_server.listen(ws_port)
	if err != OK:
		printerr("[RemoteControlServer] WebSocketServer failed to listen on port ", ws_port, " err=", err)
		return false

	var udp_err = _sensor_udp.listen(sensor_udp_port)
	if udp_err != OK:
		printerr("[RemoteControlServer] Sensor UDP failed to listen on port ", sensor_udp_port, " err=", udp_err)

	_server_started = true
	print("[RemoteControlServer] Control server listening WS port ", ws_port, ", UDP sensor port ", sensor_udp_port)
	return true

func stop_server() -> void:
	if not _server_started:
		return
	_ws_server.stop()
	_sensor_udp.close()
	_peers.clear()
	_server_started = false

func generate_pin() -> String:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var pin = ""
	for _i in range(6):
		pin += str(rng.randi_range(0, 9))
	return pin

func generate_token() -> String:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var token = ""
	for _i in range(32):
		token += chars[rng.randi_range(0, chars.length() - 1)]
	return token

func send_ui_directive(op: String, payload: Dictionary) -> void:
	var msg = RemoteProtocol.create_ui_message(op, payload)
	_broadcast_to_paired(RemoteProtocol.encode_json(msg))

func _broadcast_to_paired(json_str: String) -> void:
	for peer_id in _peers:
		if _peers[peer_id].get("paired", false):
			_ws_server.get_peer(peer_id).put_packet(json_str.to_utf8())

func _process(delta: float) -> void:
	if not _server_started:
		return

	_ws_server.poll()
	_process_sensor_udp(delta)

	if _pairing_peer_id != -1:
		_pairing_timer += delta
		if _pairing_timer >= pairing_timeout:
			_reject_pairing(_pairing_peer_id, "Timeout de emparejamiento (30 s)")

func _process_sensor_udp(delta: float) -> void:
	while _sensor_udp.get_available_packet_count() > 0:
		var pkt = _sensor_udp.get_packet()
		var pkt_str = pkt.get_string_from_utf8()
		var dict = RemoteProtocol.decode_json(pkt_str)
		if dict.get("type", "") == "input":
			var token = dict.get("token", "")
			if token == _active_token and _active_token != "":
				_last_sensor_timestamp = OS.get_ticks_msec() / 1000.0
				_sensor_active = true
				emit_signal("input_received", dict.get("input_type", ""), dict.get("payload", {}))

	if _sensor_active and ((OS.get_ticks_msec() / 1000.0) - _last_sensor_timestamp) > sensor_timeout:
		_sensor_active = false
		print("[RemoteControlServer] Sensor stream active timeout (>2s). Device inactive.")

func _on_ws_client_connected(id: int, _protocol: String) -> void:
	print("[RemoteControlServer] WS client connected ID ", id)
	_peers[id] = {"device_name": "Dispositivo Móvil", "paired": false, "token": ""}

func _on_ws_client_disconnected(id: int, _was_clean_close: bool) -> void:
	print("[RemoteControlServer] WS client disconnected ID ", id)
	var device_name = _peers.get(id, {}).get("device_name", "Desconocido")
	_peers.erase(id)
	if id == _pairing_peer_id:
		_pairing_peer_id = -1
	emit_signal("client_disconnected", device_name)

func _on_ws_data_received(id: int) -> void:
	var packet = _ws_server.get_peer(id).get_packet()
	var pkt_str = packet.get_string_from_utf8()
	var dict = RemoteProtocol.decode_json(pkt_str)
	var type = dict.get("type", "")

	match type:
		"pair_request":
			_handle_pair_request(id, dict)
		"input":
			_handle_input(id, dict)
		"ping":
			_ws_server.get_peer(id).put_packet(RemoteProtocol.encode_json(RemoteProtocol.create_pong()).to_utf8())

func _handle_pair_request(id: int, dict: Dictionary) -> void:
	var device_name = dict.get("device_name", "Dispositivo Móvil")
	_peers[id]["device_name"] = device_name

	if _pairing_peer_id != -1 and _pairing_peer_id != id:
		_send_pair_result(id, false, "", "Servidor ocupado con otra solicitud")
		return

	_active_pin = generate_pin()
	_pairing_peer_id = id
	_pairing_timer = 0.0

	# Enviar pair_pin al cliente antes de emitir la señal para el diálogo en el host
	if _ws_server.has_peer(id):
		var pin_msg = RemoteProtocol.create_pair_pin(_active_pin)
		_ws_server.get_peer(id).put_packet(RemoteProtocol.encode_json(pin_msg).to_utf8())

	var cb = funcref(self, "_on_pairing_decision")

	emit_signal("client_pair_requested", device_name, _active_pin, cb)

func _on_pairing_decision(accepted: bool) -> void:
	if _pairing_peer_id == -1:
		return
	var peer_id = _pairing_peer_id
	_pairing_peer_id = -1

	if accepted:
		_active_token = generate_token()
		_peers[peer_id]["paired"] = true
		_peers[peer_id]["token"] = _active_token
		_send_pair_result(peer_id, true, _active_token, "")
		emit_signal("client_connected", _peers[peer_id]["device_name"])
	else:
		_reject_pairing(peer_id, "Rechazado por el host")

func _reject_pairing(peer_id: int, reason: String) -> void:
	_send_pair_result(peer_id, false, "", reason)
	if _peers.has(peer_id):
		_peers[peer_id]["paired"] = false

func _send_pair_result(peer_id: int, ok: bool, token: String, reason: String) -> void:
	if _ws_server.has_peer(peer_id):
		var res = RemoteProtocol.create_pair_result(ok, token, reason)
		_ws_server.get_peer(peer_id).put_packet(RemoteProtocol.encode_json(res).to_utf8())

func _handle_input(id: int, dict: Dictionary) -> void:
	var token = dict.get("token", "")
	if not _peers.get(id, {}).get("paired", false) or token != _active_token or _active_token == "":
		return

	emit_signal("input_received", dict.get("input_type", ""), dict.get("payload", {}))
