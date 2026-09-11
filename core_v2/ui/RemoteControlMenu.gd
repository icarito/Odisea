extends Control

# RemoteControlMenu.gd - UI for finding and pairing with ODISEA host sessions on local network.

signal closed()

# Solo se anuncian partidas en curso: el host no publica nada desde el menu principal
# (RemoteControlManager._is_gameplay_scene), por eso la instruccion lo aclara.
const SEARCH_HINT := "Buscando partidas...\n\nNecesita otro dispositivo con Odisea abierto en una partida (no en el menú) y conectado a la misma red wifi que este."

onready var status_label: Label = $VBox/StatusLabel
onready var sessions_scroll: ScrollContainer = $VBox/SessionsScroll
onready var hosts: VBoxContainer = $VBox/SessionsScroll/Hosts
onready var pin_display_label: Label = $VBox/PinDisplayLabel
onready var refresh_button: Button = $VBox/HBoxActions/RefreshButton
onready var back_button: Button = $VBox/HBoxActions/BackButton
onready var log_toggle: Button = $VBox/LogToggle
onready var log_text: TextEdit = $VBox/LogText
onready var connect_confirm: ConfirmationDialog = $ConnectConfirm

var RemoteControlManager = null
var RemoteProtocol = load("res://core_v2/net/RemoteProtocol.gd")
var _discovered_map: Dictionary = {}
var _selected_key: String = ""
# Sesion con la que ya se intento emparejar. Mientras no este vacia, los anuncios de
# discovery (llegan cada segundo) no pisan el estado ni reintentan solos.
var _attempted_key: String = ""
var _awaiting_confirm: bool = false

func _ready():
	RemoteControlManager = get_node_or_null("/root/RemoteControlManager")

	connect_confirm.get_ok().text = "Conectar"
	connect_confirm.get_cancel().text = "Cancelar"
	connect_confirm.connect("confirmed", self, "_on_connect_confirmed")
	connect_confirm.connect("popup_hide", self, "_on_connect_confirm_hidden")
	preload("res://core_v2/ui/DialogButtons.gd").fit_for_touch(connect_confirm)

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
	back_button.grab_focus()
	_restart_search()

func close_menu() -> void:
	hide()
	if RemoteControlManager and RemoteControlManager.discovery:
		RemoteControlManager.discovery.stop_discovery()
		# Sin esto el cliente queda reintentando conectarse para siempre en segundo plano.
		RemoteControlManager.client.disconnect_from_host()
	emit_signal("closed")
	# Menu instancia uno nuevo cada vez; oculto seguiria escuchando discovery y
	# auto-emparejando por su cuenta.
	queue_free()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		# Back/Esc cierra primero el dialogo, despues el menu.
		if connect_confirm.visible:
			connect_confirm.hide()
		else:
			close_menu()
		get_tree().set_input_as_handled()

func _restart_search() -> void:
	_attempted_key = ""
	_awaiting_confirm = false
	connect_confirm.hide()
	pin_display_label.hide()
	sessions_scroll.hide()
	status_label.text = SEARCH_HINT
	if RemoteControlManager and RemoteControlManager.discovery:
		RemoteControlManager.discovery.stop_discovery()
		RemoteControlManager.discovery.start_discovery()

func _on_refresh_pressed() -> void:
	_log("Buscando sesiones en la red...")
	_restart_search()

func _on_back_pressed() -> void:
	close_menu()

# Nada se conecta sin confirmar aca primero, ni siquiera con una sola partida en la red.
func _on_host_pressed(key: String) -> void:
	_selected_key = key
	_attempted_key = key
	_awaiting_confirm = true
	connect_confirm.dialog_text = "¿Controlar esta partida?\n\n%s\n\nEn esa pantalla tendrán que permitirlo con un PIN." % _session_title(_discovered_map.get(key, {}))
	status_label.text = "Confirme la conexión con %s." % _session_name(key)
	connect_confirm.popup_centered()

func _on_connect_confirmed() -> void:
	_awaiting_confirm = false
	status_label.text = "Conectando con %s..." % _session_name(_selected_key)
	_on_pair_pressed()

# popup_hide puede llegar antes que confirmed (AcceptDialog se oculta y despues emite):
# se decide en diferido, igual que RemotePairingDialog.
func _on_connect_confirm_hidden() -> void:
	call_deferred("_cancel_if_unconfirmed")

func _cancel_if_unconfirmed() -> void:
	if _awaiting_confirm:
		_awaiting_confirm = false
		status_label.text = "Conexión cancelada. Elija una partida o pulse Buscar de nuevo."

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
	if ip == "":
		_log("La sesión no trae dirección IP.")
		return

	_log("Conectando a %s:%d..." % [ip, ws_port])
	if RemoteControlManager and RemoteControlManager.client:
		var client = RemoteControlManager.client
		if client.is_connected_to_host():
			client.request_pairing()
		else:
			if not client.is_connected("connection_state_changed", self, "_on_client_connected_for_pairing"):
				client.connect("connection_state_changed", self, "_on_client_connected_for_pairing", [], CONNECT_ONESHOT)
			# Es lo que ve el host en el dialogo de permiso: "icarito-pc (Linux)".
			client.connect_to_host(ip, ws_port, sensor_port, RemoteProtocol.device_label())

func _on_client_connected_for_pairing(status_text: String, is_connected: bool) -> void:
	if is_connected and RemoteControlManager and RemoteControlManager.client:
		RemoteControlManager.client.request_pairing()

func _on_pair_pin_received(pin: String) -> void:
	if pin_display_label:
		pin_display_label.text = "PIN: %s" % pin
		pin_display_label.show()
	status_label.text = "En %s apareció una solicitud. Si muestra este mismo PIN, pulse Permitir." % _session_name(_attempted_key)
	_log("PIN de emparejamiento recibido: %s" % pin)

func _on_sessions_updated(sessions: Dictionary) -> void:
	_discovered_map = sessions
	if not hosts:
		return
	# remove_child ademas de queue_free: si llegan dos actualizaciones en el mismo frame
	# (anuncio + limpieza de vencidas) los botones viejos seguirian en el contenedor.
	for child in hosts.get_children():
		hosts.remove_child(child)
		child.queue_free()

	var keys = sessions.keys()
	# Con una sola partida no hay nada que elegir: se pasa directo a confirmarla.
	sessions_scroll.visible = keys.size() > 1
	if _attempted_key == "":
		match keys.size():
			0:
				status_label.text = SEARCH_HINT
			1:
				_on_host_pressed(keys[0])
			_:
				status_label.text = "Hay %d partidas en su red. Elija cuál quiere controlar:" % keys.size()

	if keys.size() < 2:
		return
	for key in keys:
		var button := Button.new()
		button.text = _session_title(sessions[key])
		button.rect_min_size = Vector2(0, 72)
		button.connect("pressed", self, "_on_host_pressed", [key])
		hosts.add_child(button)

func _session_name(key: String) -> String:
	return String(_discovered_map.get(key, {}).get("session_name", "el otro dispositivo"))

# "hostname\nLinux · Odisea v0.4.1"; hosts viejos no mandan SO.
static func _session_title(s: Dictionary) -> String:
	var os_name: String = String(s.get("os", ""))
	var version: String = String(s.get("version", ""))
	var details: String = "Odisea %s" % version if version != "" else "Odisea"
	if os_name != "":
		details = "%s · %s" % [os_name, details]
	return "%s\n%s" % [s.get("session_name", "Odisea Host"), details]

func _on_connection_state_changed(status_text: String, _is_connected: bool) -> void:
	_log("Estado red: " + status_text)

func _on_pair_result_received(ok: bool, reason: String) -> void:
	if ok:
		RemoteControlManager.discovery.stop_discovery()
		get_tree().change_scene("res://core_v2/ui/RemoteControlHome.tscn")
	else:
		pin_display_label.hide()
		status_label.text = "No se pudo emparejar: %s.\nPulse Buscar de nuevo para reintentar." % reason
		_log("Emparejamiento rechazado: " + reason)

func _on_ui_directive_received(op: String, payload: Dictionary) -> void:
	_log("UI DIRECTIVE [%s]: %s" % [op, String(payload)])

func _log(msg: String) -> void:
	if log_text:
		log_text.text += msg + "\n"
		log_text.cursor_set_line(log_text.get_line_count())
