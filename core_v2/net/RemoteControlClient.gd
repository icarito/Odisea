extends Node

# RemoteControlClient.gd - Client running on phone/tablet to connect to ODISEA host.

signal connection_state_changed(status_text, is_connected)
signal pair_result_received(ok, reason)
signal ui_directive_received(op, payload)

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")

export var sensor_send_interval: float = 0.033 # ~30 Hz
export var reconnect_delay: float = 2.0

var _ws_client = WebSocketClient.new()
var _sensor_udp = PacketPeerUDP.new()

var _host_ip: String = ""
var _ws_port: int = 10443
var _sensor_port: int = 10444
var _device_name: String = "Mobile Device"
var _session_token: String = ""

var _is_connected: bool = false
var _is_paired: bool = false
var _is_reconnecting: bool = false
var _auto_reconnect: bool = true
var _reconnect_timer: float = 0.0
var _sensor_timer: float = 0.0

func _ready():
	_ws_client.connect("connection_established", self, "_on_ws_connected")
	_ws_client.connect("connection_closed", self, "_on_ws_closed")
	_ws_client.connect("connection_error", self, "_on_ws_error")
	_ws_client.connect("data_received", self, "_on_ws_data_received")

func is_connected_to_host() -> bool:
	return _is_connected

func connect_to_host(p_ip: String, p_ws_port: int = 10443, p_sensor_port: int = 10444, p_device_name: String = "Mobile Device") -> void:
	_host_ip = p_ip
	_ws_port = p_ws_port
	_sensor_port = p_sensor_port
	_device_name = p_device_name
	_auto_reconnect = true
	_do_connect()

func _do_connect() -> void:
	emit_signal("connection_state_changed", "Conectando...", false)
	var url = "ws://%s:%d" % [_host_ip, _ws_port]
	var err = _ws_client.connect_to_url(url)
	if err != OK:
		emit_signal("connection_state_changed", "Error de conexión", false)
		_schedule_reconnect()

func request_pairing(pin: String) -> void:
	if not _is_connected:
		return
	var msg = RemoteProtocol.create_pair_request(_device_name, pin)
	_ws_client.get_peer(1).put_packet(RemoteProtocol.encode_json(msg).to_utf8())

func send_touch_input(payload: Dictionary) -> void:
	if not _is_paired:
		return
	var msg = RemoteProtocol.create_input_message("touch", payload, _session_token)
	_ws_client.get_peer(1).put_packet(RemoteProtocol.encode_json(msg).to_utf8())

func send_sensor_input(input_type: String, payload: Dictionary) -> void:
	if not _is_paired:
		return
	var msg = RemoteProtocol.create_input_message(input_type, payload, _session_token)
	var bytes = RemoteProtocol.encode_json(msg).to_utf8()
	_sensor_udp.set_dest_address(_host_ip, _sensor_port)
	_sensor_udp.put_packet(bytes)

func disconnect_from_host() -> void:
	_auto_reconnect = false
	_is_connected = false
	_is_paired = false
	_ws_client.disconnect_from_host()
	emit_signal("connection_state_changed", "Desconectado", false)

func _process(delta: float) -> void:
	if _ws_client.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		_ws_client.poll()

	if _is_reconnecting:
		_reconnect_timer += delta
		if _reconnect_timer >= reconnect_delay:
			_reconnect_timer = 0.0
			_is_reconnecting = false
			_do_connect()

	if _is_paired:
		_sample_and_send_sensors(delta)

func _sample_and_send_sensors(delta: float) -> void:
	_sensor_timer += delta
	if _sensor_timer >= sensor_send_interval:
		_sensor_timer = 0.0

		# Sample accelerometer & gyroscope from OS
		var accel = Input.get_accelerometer()
		var gyro = Input.get_gyroscope()

		if accel != Vector3.ZERO:
			send_sensor_input("accel", {"x": accel.x, "y": accel.y, "z": accel.z})
		if gyro != Vector3.ZERO:
			send_sensor_input("gyro", {"x": gyro.x, "y": gyro.y, "z": gyro.z})

func _on_ws_connected(_protocol: String) -> void:
	print("[RemoteControlClient] WebSocket connected to ", _host_ip)
	_is_connected = true
	emit_signal("connection_state_changed", "Conectado. Ingrese PIN", true)

func _on_ws_closed(_was_clean_close: bool) -> void:
	_is_connected = false
	_is_paired = false
	print("[RemoteControlClient] Connection closed")
	if _auto_reconnect:
		emit_signal("connection_state_changed", "Reconectando...", false)
		_schedule_reconnect()
	else:
		emit_signal("connection_state_changed", "Desconectado", false)

func _on_ws_error() -> void:
	_is_connected = false
	_is_paired = false
	print("[RemoteControlClient] Connection error")
	if _auto_reconnect:
		emit_signal("connection_state_changed", "Reconectando...", false)
		_schedule_reconnect()

func _schedule_reconnect() -> void:
	_is_reconnecting = true
	_reconnect_timer = 0.0

func _on_ws_data_received() -> void:
	var pkt = _ws_client.get_peer(1).get_packet()
	var pkt_str = pkt.get_string_from_utf8()
	var dict = RemoteProtocol.decode_json(pkt_str)
	var type = dict.get("type", "")

	match type:
		"pair_result":
			var ok = bool(dict.get("ok", false))
			if ok:
				_session_token = String(dict.get("token", ""))
				_is_paired = true
				emit_signal("connection_state_changed", "Emparejado y conectado", true)
			else:
				_is_paired = false
				emit_signal("connection_state_changed", "Error de emparejamiento", true)
			emit_signal("pair_result_received", ok, String(dict.get("reason", "")))
		"ui":
			emit_signal("ui_directive_received", String(dict.get("op", "")), dict.get("payload", {}))
		"ping":
			var pong = RemoteProtocol.create_pong()
			_ws_client.get_peer(1).put_packet(RemoteProtocol.encode_json(pong).to_utf8())
