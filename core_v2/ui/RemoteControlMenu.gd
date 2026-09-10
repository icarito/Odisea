extends Control

# RemoteControlMenu.gd - UI for finding and pairing with ODISEA host sessions on local network.

signal closed()

onready var status_label: Label = $VBox/StatusLabel
onready var sessions_item_list: ItemList = $VBox/SessionsItemList
onready var pin_edit: LineEdit = $VBox/HBoxPin/PinEdit
onready var pair_button: Button = $VBox/HBoxPin/PairButton
onready var refresh_button: Button = $VBox/HBoxActions/RefreshButton
onready var back_button: Button = $VBox/HBoxActions/BackButton
onready var log_text: TextEdit = $VBox/LogText

var RemoteControlManager = null
var _discovered_map: Dictionary = {}
var _selected_key: String = ""

func _ready():
	RemoteControlManager = get_node_or_null("/root/RemoteControlManager")

	if refresh_button:
		refresh_button.connect("pressed", self, "_on_refresh_pressed")
	if back_button:
		back_button.connect("pressed", self, "_on_back_pressed")
	if pair_button:
		pair_button.connect("pressed", self, "_on_pair_pressed")
	if sessions_item_list:
		sessions_item_list.connect("item_selected", self, "_on_session_selected")

	if RemoteControlManager and RemoteControlManager.discovery:
		RemoteControlManager.discovery.connect("sessions_updated", self, "_on_sessions_updated")
		RemoteControlManager.client.connect("connection_state_changed", self, "_on_connection_state_changed")
		RemoteControlManager.client.connect("pair_result_received", self, "_on_pair_result_received")
		RemoteControlManager.client.connect("ui_directive_received", self, "_on_ui_directive_received")

func open_menu() -> void:
	show()
	_log("Aquí aparecen las sesiones de ODISEA en curso en tu red local. Selecciona una y pulsa Emparejar.")
	if RemoteControlManager and RemoteControlManager.discovery:
		RemoteControlManager.discovery.start_discovery()

func close_menu() -> void:
	hide()
	if RemoteControlManager and RemoteControlManager.discovery:
		RemoteControlManager.discovery.stop_discovery()
	emit_signal("closed")

func _on_refresh_pressed() -> void:
	if RemoteControlManager and RemoteControlManager.discovery:
		RemoteControlManager.discovery.stop_discovery()
		RemoteControlManager.discovery.start_discovery()
	_log("Buscando sesiones en la red...")

func _on_back_pressed() -> void:
	close_menu()

func _on_session_selected(index: int) -> void:
	var metadata = sessions_item_list.get_item_metadata(index)
	if metadata is String:
		_selected_key = metadata
		_log("Sesión seleccionada: %s" % _selected_key)

func _on_pair_pressed() -> void:
	if _selected_key == "" or not _discovered_map.has(_selected_key):
		_log("Por favor selecciona una sesión válida de la lista.")
		return

	var pin = pin_edit.text.strip_edges() if pin_edit else ""
	if pin.length() != 6 or not pin.is_valid_integer():
		_log("Ingrese un PIN válido de 6 dígitos.")
		return

	var session = _discovered_map[_selected_key]
	var ip = session.get("ip", "")
	var ws_port = session.get("ws_port", 10443)
	var sensor_port = session.get("sensor_port", 10444)

	_log("Conectando a %s:%d..." % [ip, ws_port])
	if RemoteControlManager and RemoteControlManager.client:
		var client = RemoteControlManager.client
		if client.is_connected_to_host():
			client.request_pairing(pin)
		else:
			if not client.is_connected("connection_state_changed", self, "_on_client_connected_for_pairing"):
				client.connect("connection_state_changed", self, "_on_client_connected_for_pairing", [pin], CONNECT_ONESHOT)
			client.connect_to_host(ip, ws_port, sensor_port, OS.get_name() + " Device")

func _on_client_connected_for_pairing(status_text: String, is_connected: bool, pin: String) -> void:
	if is_connected and RemoteControlManager and RemoteControlManager.client:
		RemoteControlManager.client.request_pairing(pin)

func _on_sessions_updated(sessions: Dictionary) -> void:
	_discovered_map = sessions
	if not sessions_item_list:
		return
	sessions_item_list.clear()

	var keys = sessions.keys()
	if keys.size() == 0:
		status_label.text = "Sin sesiones activas en la red local"
		return

	status_label.text = "Sesiones encontradas: %d" % keys.size()
	for key in keys:
		var s = sessions[key]
		var text = "%s (%s) - %s" % [s.get("session_name", "Odisea"), s.get("version", "v0.4.0"), s.get("ip", "")]
		var idx = sessions_item_list.add_item(text)
		sessions_item_list.set_item_metadata(idx, key)

func _on_connection_state_changed(status_text: String, _is_connected: bool) -> void:
	_log("Estado red: " + status_text)

func _on_pair_result_received(ok: bool, reason: String) -> void:
	if ok:
		_log("¡EMPAREJAMIENTO EXITOSO! Dispositivo listo.")
	else:
		_log("Emparejamiento rechazado: " + reason)

func _on_ui_directive_received(op: String, payload: Dictionary) -> void:
	_log("UI DIRECTIVE [%s]: %s" % [op, String(payload)])

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if RemoteControlManager and RemoteControlManager.client:
			RemoteControlManager.client.send_touch_input({"x": event.position.x, "y": event.position.y})

func _log(msg: String) -> void:
	if log_text:
		log_text.text += msg + "\n"
		log_text.cursor_set_line(log_text.get_line_count())
