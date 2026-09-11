extends Control

# RemoteControlMenu.gd - UI for finding and pairing with ODISEA host sessions on local network.

signal closed()

onready var status_label: Label = $VBox/StatusLabel
onready var hosts: VBoxContainer = $VBox/SessionsScroll/Hosts
onready var pin_display_label: Label = $VBox/PinDisplayLabel
onready var refresh_button: Button = $VBox/HBoxActions/RefreshButton
onready var back_button: Button = $VBox/HBoxActions/BackButton
onready var log_toggle: Button = $VBox/LogToggle
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
	if log_toggle:
		log_toggle.connect("pressed", self, "_on_log_toggle")

	if RemoteControlManager and RemoteControlManager.discovery:
		RemoteControlManager.discovery.connect("sessions_updated", self, "_on_sessions_updated")
		RemoteControlManager.client.connect("connection_state_changed", self, "_on_connection_state_changed")
		RemoteControlManager.client.connect("pair_pin_received", self, "_on_pair_pin_received")
		RemoteControlManager.client.connect("pair_result_received", self, "_on_pair_result_received")
		RemoteControlManager.client.connect("ui_directive_received", self, "_on_ui_directive_received")

func open_menu() -> void:
	show()
	log_text.hide()
	log_toggle.text = "Ver registro"
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

func _on_host_pressed(key: String) -> void:
	_selected_key = key
	_on_pair_pressed()

func _on_log_toggle() -> void:
	log_text.visible = not log_text.visible
	log_toggle.text = "Ocultar registro" if log_text.visible else "Ver registro"

func _on_pair_pressed() -> void:
	if _selected_key == "" or not _discovered_map.has(_selected_key):
		_log("Por favor selecciona una sesión válida de la lista.")
		return

	var session = _discovered_map[_selected_key]
	var ip = session.get("ip", "")
	var ws_port = session.get("ws_port", 10443)
	var sensor_port = session.get("sensor_port", 10444)

	_log("Conectando a %s:%d..." % [ip, ws_port])
	if RemoteControlManager and RemoteControlManager.client:
		var client = RemoteControlManager.client
		if client.is_connected_to_host():
			client.request_pairing()
		else:
			if not client.is_connected("connection_state_changed", self, "_on_client_connected_for_pairing"):
				client.connect("connection_state_changed", self, "_on_client_connected_for_pairing", [], CONNECT_ONESHOT)
			client.connect_to_host(ip, ws_port, sensor_port, OS.get_name() + " Device")

func _on_client_connected_for_pairing(status_text: String, is_connected: bool) -> void:
	if is_connected and RemoteControlManager and RemoteControlManager.client:
		RemoteControlManager.client.request_pairing()

func _on_pair_pin_received(pin: String) -> void:
	if pin_display_label:
		pin_display_label.text = "PIN: %s" % pin
	_log("PIN de emparejamiento recibido: %s" % pin)

func _on_sessions_updated(sessions: Dictionary) -> void:
	_discovered_map = sessions
	if not hosts:
		return
	for child in hosts.get_children():
		child.queue_free()

	var keys = sessions.keys()
	if keys.size() == 0:
		status_label.text = "Sin sesiones activas en la red local"
		return

	status_label.text = "Sesiones encontradas: %d" % keys.size()
	for key in keys:
		var s = sessions[key]
		var button := Button.new()
		button.text = "%s\n%s" % [s.get("session_name", "Odisea Host"), s.get("version", "v0.4.0")]
		button.rect_min_size = Vector2(0, 72)
		button.connect("pressed", self, "_on_host_pressed", [key])
		hosts.add_child(button)

func _on_connection_state_changed(status_text: String, _is_connected: bool) -> void:
	_log("Estado red: " + status_text)

func _on_pair_result_received(ok: bool, reason: String) -> void:
	if ok:
		RemoteControlManager.discovery.stop_discovery()
		get_tree().change_scene("res://core_v2/ui/RemoteControlHome.tscn")
	else:
		_log("Emparejamiento rechazado: " + reason)

func _on_ui_directive_received(op: String, payload: Dictionary) -> void:
	_log("UI DIRECTIVE [%s]: %s" % [op, String(payload)])

func _log(msg: String) -> void:
	if log_text:
		log_text.text += msg + "\n"
		log_text.cursor_set_line(log_text.get_line_count())
