extends Node

# RemoteControlClient.gd - Client running on phone/tablet to connect to ODISEA host.

signal connection_state_changed(status_text, is_connected)
signal pair_pin_received(pin)
signal pair_result_received(ok, reason)
signal ui_directive_received(op, payload)
# Sesion emparejada:
# - connection_lost: se corto sin aviso del host (wifi, etc.); se reintenta con el mismo
#   token hasta session_resume_timeout.
# - connection_restored: el host acepto el token y la sesion sigue.
# - session_ended: el host cerro la partida (mensaje session_end), rechazo el token, o
#   vencio el plazo de reintento.
signal connection_lost()
signal connection_restored()
signal session_ended(reason)

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
# Un wifi que se cae no cierra el TCP: sin latido el control nunca se enteraria. El host
# contesta cada ping con un pong; sin nada del host en heartbeat_timeout, se da por cortado.
export var heartbeat_interval: float = 1.0
export var heartbeat_timeout: float = 3.0
# Cuanto se reintenta recuperar una sesion cortada sin aviso antes de darla por perdida.
export var session_resume_timeout: float = 30.0

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
var _resuming: bool = false
var _resume_timer: float = 0.0
var _heartbeat_timer: float = 0.0
var _last_rx_msec: int = 0
var _host_id: String = ""
var _resumable_token: String = ""
# Ultimo estado de pausa que aviso el host (ui op "host_paused").
var host_paused: bool = false

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
# p_host_id es la clave de discovery del host: con ella se lo reconoce si vuelve a
# anunciarse despues de un corte (can_resume).
func pair_with(p_ip: String, p_ws_port: int, p_sensor_port: int, p_device_name: String, p_host_id: String = "") -> void:
	_host_id = p_host_id
	_resumable_token = ""
	host_paused = false
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
	_resuming = false
	_pairing_pending = true
	_pairing_pin_received = false
	_pairing_timer = 0.0
	_pairing_pin = pin
	_send_pair_request()

func _send_pair_request() -> void:
	_send(RemoteProtocol.create_pair_request(_device_name, _pairing_pin))

func _send(msg: Dictionary) -> void:
	if not _is_connected or _ws_client.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		return
	_ws_client.get_peer(1).put_packet(RemoteProtocol.encode_json(msg).to_utf8())

func is_resuming() -> bool:
	return _resuming

func get_resume_time_left() -> float:
	return max(0.0, session_resume_timeout - _resume_timer)

# Una sesion que se dio por perdida por falta de conexion (nadie la cerro) queda
# guardada: si ese mismo host vuelve a anunciarse, se retoma sola con el token, sin PIN.
func can_resume(session: Dictionary) -> bool:
	return _resumable_token != "" and _host_id != "" and not _resuming and not _is_paired \
		and String(session.get("key", "")) == _host_id

func resume_session(session: Dictionary) -> void:
	_session_token = _resumable_token
	_resumable_token = ""
	_resuming = true
	_resume_timer = 0.0
	connect_to_host(String(session.get("ip", "")), int(session.get("ws_port", 10443)), int(session.get("sensor_port", 10444)), _device_name)

# Cerrar el panel del control remoto a mitad de un emparejamiento corta los reintentos;
# no toca una sesion guardada para retomar.
func cancel_pairing() -> void:
	if _pairing_pending:
		disconnect_from_host()

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
	_send(RemoteProtocol.create_input_message(input_type, payload, _session_token))

func send_ui_directive(op: String, payload) -> void:
	if not _is_paired:
		return
	var msg = RemoteProtocol.create_ui_message(op, payload)
	msg["token"] = _session_token
	_send(msg)

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
	_resuming = false
	# Salir a proposito del control remoto: no se retoma solo despues.
	_resumable_token = ""
	_is_connected = false
	_is_paired = false
	_ws_client.disconnect_from_host()
	emit_signal("connection_state_changed", "Desconectado", false)

func _process(delta: float) -> void:
	if _ws_client.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		_ws_client.poll()

	if _is_paired and _is_connected:
		_heartbeat_timer += delta
		if _heartbeat_timer >= heartbeat_interval:
			_heartbeat_timer = 0.0
			_send(RemoteProtocol.create_ping())
		if OS.get_ticks_msec() - _last_rx_msec > int(heartbeat_timeout * 1000.0):
			# Conexion colgada: se cierra de este lado y se reintenta con el token.
			_ws_client.disconnect_from_host()
			_is_connected = false
			_is_paired = false
			_lose_connection()

	if _resuming:
		_resume_timer += delta
		if _resume_timer >= session_resume_timeout:
			# Nadie cerro la sesion: si el host vuelve a anunciarse, se retoma sola.
			_end_session("No se pudo recuperar la conexión con el otro dispositivo.", true)

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
	_is_connected = true
	_last_rx_msec = OS.get_ticks_msec()
	emit_signal("connection_state_changed", "Conectado", true)
	if _resuming:
		_send(RemoteProtocol.create_resume(_session_token))
	# Reintento: cada (re)conexion reenvia el pedido mientras el host no haya contestado.
	elif _pairing_pending and not _pairing_pin_received:
		_send_pair_request()

func _on_ws_closed(_was_clean_close: bool) -> void:
	var was_paired: bool = _is_paired
	_is_connected = false
	_is_paired = false
	# Un cierre a proposito del host llega antes como session_end; esto es un corte.
	if was_paired:
		_lose_connection()
	elif _resuming:
		_schedule_reconnect()
	# Con el PIN ya en pantalla del host no se reenvia: saldria un segundo dialogo alla.
	elif _pairing_pending and _pairing_pin_received:
		_fail_pairing("se cortó la conexión con el otro dispositivo")
	elif _auto_reconnect:
		emit_signal("connection_state_changed", "Reconectando...", false)
		_schedule_reconnect()
	else:
		emit_signal("connection_state_changed", "Desconectado", false)

func _on_ws_error() -> void:
	var was_paired: bool = _is_paired
	_is_connected = false
	_is_paired = false
	if was_paired:
		_lose_connection()
	elif _resuming or _auto_reconnect:
		emit_signal("connection_state_changed", "Reconectando...", false)
		_schedule_reconnect()

func _lose_connection() -> void:
	if not _resuming:
		_resuming = true
		_resume_timer = 0.0
		emit_signal("connection_state_changed", "Sin conexión, reintentando...", false)
		emit_signal("connection_lost")
	_schedule_reconnect()

func _end_session(reason: String, resumable: bool = false) -> void:
	_auto_reconnect = false
	_is_reconnecting = false
	_resuming = false
	_is_paired = false
	_resumable_token = _session_token if resumable else ""
	_session_token = ""
	if _ws_client.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		_ws_client.disconnect_from_host()
	_is_connected = false
	emit_signal("connection_state_changed", "Sesión terminada", false)
	emit_signal("session_ended", reason)

func _schedule_reconnect() -> void:
	_is_reconnecting = true
	_reconnect_timer = 0.0

func _on_ws_data_received() -> void:
	var pkt = _ws_client.get_peer(1).get_packet()
	_last_rx_msec = OS.get_ticks_msec()
	_handle_message(RemoteProtocol.decode_json(pkt.get_string_from_utf8()))

func _handle_message(dict: Dictionary) -> void:
	match dict.get("type", ""):
		"pair_pin":
			var pin = String(dict.get("pin", ""))
			_pairing_pin_received = true
			_pairing_timer = 0.0
			emit_signal("pair_pin_received", pin)
		"session_end":
			_end_session("El otro dispositivo cerró la partida.")
		"pair_result":
			if _resuming:
				_handle_resume_result(bool(dict.get("ok", false)))
			elif bool(dict.get("ok", false)):
				_pairing_pending = false
				_session_token = String(dict.get("token", ""))
				_is_paired = true
				emit_signal("connection_state_changed", "Emparejado y conectado", true)
				emit_signal("pair_result_received", true, "")
			else:
				# Desconecta: el proximo intento arranca limpio, sin reconexiones de este.
				_fail_pairing(String(dict.get("reason", "")))
		"ui":
			var op := String(dict.get("op", ""))
			var payload = dict.get("payload", {})
			if op == "host_paused" and payload is Dictionary:
				# Guardado: puede llegar mientras la pantalla del control todavia carga.
				host_paused = bool(payload.get("paused", false))
			emit_signal("ui_directive_received", op, payload)
		"ping":
			_send(RemoteProtocol.create_pong())

func _handle_resume_result(ok: bool) -> void:
	if not ok:
		_end_session("La partida ya no está disponible en el otro dispositivo.")
		return
	_resuming = false
	_is_paired = true
	_last_rx_msec = OS.get_ticks_msec()
	emit_signal("connection_state_changed", "Emparejado y conectado", true)
	emit_signal("connection_restored")
