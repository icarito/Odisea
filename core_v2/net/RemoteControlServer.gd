extends Node

# RemoteControlServer.gd - Handles WebSocket connections for control/handshake & UDP for high-frequency sensor streaming.

signal client_pair_requested(device_name, pin, callback)
signal client_connected(device_name)
signal client_disconnected(device_name)
signal input_received(input_type, payload)
signal ui_directive_received(op, payload)
# Un control emparejado dejo de hablar (ni pings) sin cerrar la conexion: wifi caido.
# Lo que tenia apretado hay que soltarlo ya, no cuando TCP se rinda minutos despues.
signal client_stalled(device_name)

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")

export var ws_port: int = 10443
export var sensor_udp_port: int = 10444
export var pairing_timeout: float = 30.0
# El control manda un ping por segundo (RemoteControlClient.heartbeat_interval).
export var client_stall_timeout: float = 3.0

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

# En _ready y no en start_server: el host se apaga y se prende en cada ida y vuelta
# entre el menu y el juego, y reconectar tiraba "already connected" cada vez.
func _ready() -> void:
	_ws_server.connect("client_connected", self, "_on_ws_client_connected")
	_ws_server.connect("client_disconnected", self, "_on_ws_client_disconnected")
	_ws_server.connect("data_received", self, "_on_ws_data_received")

func start_server(p_ws_port: int = 10443, p_sensor_port: int = 10444) -> bool:
	ws_port = p_ws_port
	sensor_udp_port = p_sensor_port

	var err = _ws_server.listen(ws_port)
	if err != OK:
		printerr("[RemoteControlServer] WebSocketServer failed to listen on port ", ws_port, " err=", err)
		return false

	var udp_err = _sensor_udp.listen(sensor_udp_port)
	if udp_err != OK:
		printerr("[RemoteControlServer] Sensor UDP failed to listen on port ", sensor_udp_port, " err=", udp_err)

	_server_started = true
	return true

func stop_server() -> void:
	if not _server_started:
		return
	# Ultimo mensaje: el control sabe que la partida se cerro a proposito y no se queda
	# reintentando. El poll lo empuja al socket antes de que stop() lo cierre.
	_broadcast_to_paired(RemoteProtocol.encode_json(RemoteProtocol.create_session_end()))
	_ws_server.poll()
	_ws_server.stop()
	_sensor_udp.close()
	_peers.clear()
	# Una sesion cerrada no se puede retomar con su token.
	_active_token = ""
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

func send_ui_directive(op: String, payload) -> void:
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
			_reject_pairing(_pairing_peer_id, "nadie respondió la solicitud a tiempo")
			# Sin esto el rechazo se reenviaba cada frame hasta que el dialogo cerraba.
			_pairing_peer_id = -1

	_check_stalled_peers()

func _check_stalled_peers() -> void:
	var now: int = OS.get_ticks_msec()
	for peer_id in _peers:
		var peer: Dictionary = _peers[peer_id]
		if peer.get("paired", false) and not peer.get("stalled", false) \
				and now - int(peer.get("last_rx", now)) > int(client_stall_timeout * 1000.0):
			peer["stalled"] = true
			emit_signal("client_stalled", peer.get("device_name", ""))

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

func _on_ws_client_connected(id: int, _protocol: String) -> void:
	_peers[id] = {"device_name": "Dispositivo Móvil", "paired": false, "token": "", "last_rx": OS.get_ticks_msec(), "stalled": false}

func _on_ws_client_disconnected(id: int, _was_clean_close: bool) -> void:
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
	if _peers.has(id):
		_peers[id]["last_rx"] = OS.get_ticks_msec()
		_peers[id]["stalled"] = false

	match type:
		"pair_request":
			_handle_pair_request(id, dict)
		"resume":
			_handle_resume(id, dict)
		"input":
			_handle_input(id, dict)
		"ui":
			_handle_ui_directive(id, dict)
		"ping":
			_ws_server.get_peer(id).put_packet(RemoteProtocol.encode_json(RemoteProtocol.create_pong()).to_utf8())

# Control que vuelve tras un corte sin aviso: con el token vigente sigue la misma sesion,
# sin PIN ni dialogo. La conexion vieja (si el host nunca vio que se cayo) se descarta.
func _handle_resume(id: int, dict: Dictionary) -> void:
	var token := String(dict.get("token", ""))
	if token == "" or token != _active_token or not _peers.has(id):
		_send_pair_result(id, false, "", "la sesión ya no existe")
		return
	for other_id in _peers.keys():
		if other_id != id and _peers[other_id].get("token", "") == token:
			_peers.erase(other_id)
			if _ws_server.has_peer(other_id):
				_ws_server.disconnect_peer(other_id)
	_peers[id]["paired"] = true
	_peers[id]["token"] = token
	_send_pair_result(id, true, token, "")
	emit_signal("client_connected", _peers[id]["device_name"])

func _handle_pair_request(id: int, dict: Dictionary) -> void:
	var device_name = dict.get("device_name", "Dispositivo Móvil")
	_peers[id]["device_name"] = device_name

	if _pairing_peer_id != -1 and _pairing_peer_id != id:
		_send_pair_result(id, false, "", "el otro dispositivo está atendiendo otra solicitud")
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
		_reject_pairing(peer_id, "la solicitud fue rechazada en el otro dispositivo")

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

func _handle_ui_directive(id: int, dict: Dictionary) -> void:
	var token = dict.get("token", "")
	if not _peers.get(id, {}).get("paired", false):
		return
	if _active_token != "" and token != "" and token != _active_token:
		return

	emit_signal("ui_directive_received", String(dict.get("op", "")), dict.get("payload", {}))
