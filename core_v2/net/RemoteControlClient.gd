extends Node

# RemoteControlClient.gd - Client running on phone/tablet to connect to ODISEA host.

signal connection_state_changed(status_text, is_connected)
signal pair_pin_received(pin)
signal pair_result_received(ok, reason)
signal ui_directive_received(op, payload)

var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")

export var sensor_send_interval: float = 0.033 # ~30 Hz
export var reconnect_delay: float = 2.0
export var sensor_streaming_enabled: bool = false
# Sin PIN del host en este plazo (reconectando cada reconnect_delay), el emparejamiento
# falla con motivo en vez de quedar "Conectando..." para siempre.
export var pairing_response_timeout: float = 15.0
# Con el PIN ya mostrado, el host tiene 30 s para decidir (RemoteControlServer.pairing_timeout)
# y avisa al vencer; esto cubre que el host se cierre sin avisar.
export var pairing_decision_timeout: float = 35.0

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
var _pairing_pending: bool = false
var _pairing_pin_received: bool = false
var _pairing_timer: float = 0.0
var _pairing_pin: String = ""

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

# Punto de entrada unico para emparejar: conecta si hace falta y deja el pedido pendiente.
func pair_with(p_ip: String, p_ws_port: int, p_sensor_port: int, p_device_name: String) -> void:
	if not _is_connected or _host_ip != p_ip or _ws_port != p_ws_port:
		if _ws_client.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
			_ws_client.disconnect_from_host()
		_is_connected = false
		_is_paired = false
		connect_to_host(p_ip, p_ws_port, p_sensor_port, p_device_name)
	request_pairing()

# El pedido queda pendiente hasta que el host conteste: si todavia no hay conexion, sale
# en _on_ws_connected, y cada reconexion lo reenvia mientras no haya PIN.
func request_pairing(pin: String = "") -> void:
	_pairing_pending = true
	_pairing_pin_received = false
	_pairing_timer = 0.0
	_pairing_pin = pin
	_send_pair_request()

func _send_pair_request() -> void:
	if not _is_connected:
		return
	var msg = RemoteProtocol.create_pair_request(_device_name, _pairing_pin)
	_ws_client.get_peer(1).put_packet(RemoteProtocol.encode_json(msg).to_utf8())

func _fail_pairing(reason: String) -> void:
	_pairing_pending = false
	disconnect_from_host()
	emit_signal("pair_result_received", false, reason)

func send_touch_input(payload: Dictionary) -> void:
	send_input("touch", payload)

func send_input_data(payload: Dictionary) -> void:
	send_input("input_data", payload)

# Por WebSocket (TCP) y no por el UDP de sensores: un key-up perdido o desordenado deja
# la tecla pegada en el host.
func send_input(input_type: String, payload: Dictionary) -> void:
	if not _is_paired:
		return
	var msg = RemoteProtocol.create_input_message(input_type, payload, _session_token)
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
	# Una reconexion ya programada volvia a conectar despues de desconectar a proposito.
	_is_reconnecting = false
	_pairing_pending = false
	_is_connected = false
	_is_paired = false
	_ws_client.disconnect_from_host()
	emit_signal("connection_state_changed", "Desconectado", false)

func _process(delta: float) -> void:
	if _ws_client.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		_ws_client.poll()

	if _pairing_pending:
		_pairing_timer += delta
		if _pairing_pin_received and _pairing_timer >= pairing_decision_timeout:
			_fail_pairing("el otro dispositivo dejó de responder")
		elif not _pairing_pin_received and _pairing_timer >= pairing_response_timeout:
			_fail_pairing("el otro dispositivo no responde. Revise que la partida siga abierta y que ambos estén en la misma red wifi")

	if _is_reconnecting:
		_reconnect_timer += delta
		if _reconnect_timer >= reconnect_delay:
			_reconnect_timer = 0.0
			_is_reconnecting = false
			_do_connect()

	if _is_paired and sensor_streaming_enabled:
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
	emit_signal("connection_state_changed", "Conectado", true)
	# Reintento: cada (re)conexion reenvia el pedido mientras el host no haya contestado.
	if _pairing_pending and not _pairing_pin_received:
		_send_pair_request()

func _on_ws_closed(_was_clean_close: bool) -> void:
	_is_connected = false
	_is_paired = false
	print("[RemoteControlClient] Connection closed")
	# Con el PIN ya en pantalla del host no se reenvia: saldria un segundo dialogo alla.
	if _pairing_pending and _pairing_pin_received:
		_fail_pairing("se cortó la conexión con el otro dispositivo")
	elif _auto_reconnect:
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
	_handle_message(RemoteProtocol.decode_json(pkt.get_string_from_utf8()))

func _handle_message(dict: Dictionary) -> void:
	match dict.get("type", ""):
		"pair_pin":
			var pin = String(dict.get("pin", ""))
			_pairing_pin_received = true
			_pairing_timer = 0.0
			emit_signal("pair_pin_received", pin)
		"pair_result":
			if bool(dict.get("ok", false)):
				_pairing_pending = false
				_session_token = String(dict.get("token", ""))
				_is_paired = true
				emit_signal("connection_state_changed", "Emparejado y conectado", true)
				emit_signal("pair_result_received", true, "")
			else:
				# Desconecta: el proximo intento arranca limpio, sin reconexiones de este.
				_fail_pairing(String(dict.get("reason", "")))
		"ui":
			emit_signal("ui_directive_received", String(dict.get("op", "")), dict.get("payload", {}))
		"ping":
			var pong = RemoteProtocol.create_pong()
			_ws_client.get_peer(1).put_packet(RemoteProtocol.encode_json(pong).to_utf8())
