extends Control

const VirtualMouse = preload("res://core_v2/ui/VirtualMouse.gd")
var InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")
var RemoteProtocol = preload("res://core_v2/net/RemoteProtocol.gd")

const SESSION_ENDED_NOTICE_SEC := 2.5

onready var exit_confirm: ConfirmationDialog = $ExitConfirm
var _input_provider: InputProviderV2 = null
var _remote_control_manager: Node = null
# Con teclado/mouse los eventos viajan crudos y el host los procesa como hardware propio
# (todo el InputMap, modificadores incluidos). Un control tactil no tiene eventos que
# reenviar: el joystick virtual usa Input.action_press, asi que manda InputDataV2.
# No mezclar las dos vias: las acciones de flanco (interact, focus) llegarian dos veces.
var _raw_passthrough: bool = not OS.get_name() in ["Android", "iOS"]
var _mouse_delta: Vector2 = Vector2.ZERO
var _was_captured: bool = false
var _title_text: String = ""
var _hint_text: String = ""
var _host_paused: bool = false

func _ready() -> void:
	add_child(VirtualMouse.new())
	_remote_control_manager = get_node_or_null("/root/RemoteControlManager")
	_input_provider = InputProviderV2.new()
	# La musica del Menu seguia sonando: aca el juego suena en la otra pantalla. Al
	# volver, Menu.gd la arranca de nuevo en su _ready.
	var audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr:
		audio_mgr.fade_out_current_bgm(1.0)
	if _remote_control_manager and _remote_control_manager.client:
		var client = _remote_control_manager.client
		client.connect("session_ended", self, "_on_session_ended")
		client.connect("connection_lost", self, "_on_connection_lost")
		client.connect("connection_restored", self, "_on_connection_restored")
		client.connect("ui_directive_received", self, "_on_ui_directive")
	exit_confirm.connect("confirmed", self, "_on_exit_confirmed")
	exit_confirm.get_ok().text = "Salir"
	exit_confirm.get_cancel().text = "Cancelar"
	preload("res://core_v2/ui/DialogButtons.gd").fit_for_touch(exit_confirm)
	$ExitLayer/ExitButton.connect("pressed", self, "_on_exit_pressed")
	if _raw_passthrough:
		$Hint.text = "Controlando con teclado y mouse. Esc libera el mouse; un clic lo vuelve a capturar."
		# Se entra aca con change_scene, no por SceneManager, asi que no llega el
		# scene_ready que dispara la captura del juego. Se usa la misma captura con
		# reintentos (Wayland/XWayland puede rechazar el primer grab en silencio).
		var session_mgr = get_node_or_null("/root/SessionManager")
		if session_mgr and session_mgr.has_method("_start_mouse_capture_retry"):
			session_mgr._start_mouse_capture_retry()
	_title_text = $Title.text
	_hint_text = $Hint.text
	var client = _client()
	if client:
		_host_paused = client.host_paused
		_refresh_status()
	# _process solo corre mientras falta conexion, para la cuenta regresiva.
	set_process(false)
	call_deferred("_connect_touch_camera")

func _connect_touch_camera() -> void:
	var mobile_ui = get_node_or_null("/root/MobileUIManager")
	if mobile_ui and mobile_ui._touch_camera:
		mobile_ui._touch_camera.connect("camera_drag", self, "_on_camera_drag")
		mobile_ui._touch_camera.connect("camera_zoom", self, "_on_camera_zoom")

func _client() -> Node:
	return _remote_control_manager.client if _remote_control_manager else null

func _physics_process(_delta: float) -> void:
	var client = _client()
	if client == null:
		return
	if not _raw_passthrough:
		client.send_input_data(_input_provider.get_input().to_dict())
	elif _mouse_delta != Vector2.ZERO:
		# Acumulado por tick: un mouse de 1000 Hz no debe volverse 1000 mensajes por segundo.
		client.send_input("mouse_delta", {"x": _mouse_delta.x, "y": _mouse_delta.y})
		_mouse_delta = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if not _raw_passthrough or not event is InputEventMouseMotion:
		return
	var captured: bool = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	# El primer motion tras capturar es el warp del cursor al centro, no un gesto.
	if captured and _was_captured:
		_mouse_delta += (event as InputEventMouseMotion).relative
	_was_captured = captured

# La captura del mouse (clic) y su liberacion (Esc) las hace SessionManager en su propio
# _unhandled_input; aca solo se reenvia. Lo que consume la UI local (el boton Salir) no
# llega hasta aca y no viaja al host.
func _unhandled_input(event: InputEvent) -> void:
	if not _raw_passthrough:
		if event.is_action_pressed("ui_cancel"):
			_on_exit_pressed()
			get_tree().set_input_as_handled()
		return
	var client = _client()
	if client == null:
		return
	var payload: Dictionary = RemoteProtocol.encode_event(event, get_viewport().get_visible_rect().size)
	if not payload.empty():
		client.send_input("event", payload)

func _notification(what: int) -> void:
	# Al perder el foco el otro lado nunca recibiria los key-up de lo que quedo apretado.
	if what == MainLoop.NOTIFICATION_WM_FOCUS_OUT and _raw_passthrough and _client():
		_client().send_input("release_all", {})

func _on_camera_drag(delta: Vector2) -> void:
	_input_provider.add_touch_camera_drag(delta)

func _on_camera_zoom(delta: float) -> void:
	_input_provider.add_touch_camera_zoom(delta)

func _on_exit_pressed() -> void:
	if exit_confirm.visible:
		exit_confirm.hide()
	else:
		exit_confirm.popup_centered()

func _on_exit_confirmed() -> void:
	if _remote_control_manager and _remote_control_manager.client:
		_remote_control_manager.client.disconnect_from_host()
	_go_to_menu()

# Corte sin aviso del host: el cliente reintenta solo; aca solo se muestra que falta
# conexion y cuanto queda de espera.
func _on_connection_lost() -> void:
	$Title.text = "SIN CONEXIÓN"
	set_process(true)

func _process(_delta: float) -> void:
	var client = _client()
	var left: int = int(ceil(client.get_resume_time_left())) if client else 0
	$Hint.text = "Se perdió la conexión con el otro dispositivo. Reintentando... (%d s)" % left

func _on_connection_restored() -> void:
	set_process(false)
	_refresh_status()

func _on_ui_directive(op: String, payload: Dictionary) -> void:
	if op == "host_paused":
		_host_paused = bool(payload.get("paused", false))
		# Sin conexion manda el aviso de reintento; la pausa se muestra al volver.
		if not is_processing():
			_refresh_status()

func _refresh_status() -> void:
	if _host_paused:
		$Title.text = "PARTIDA EN PAUSA"
		# El teclado llega tal cual al host, asi que Esc cierra su menu de pausa.
		$Hint.text = "La partida está en pausa en el otro dispositivo." + (" Esc la reanuda." if _raw_passthrough else "")
	else:
		$Title.text = _title_text
		$Hint.text = _hint_text

# El host cerro la partida, rechazo el token o vencio la espera: se avisa el motivo un
# momento y se vuelve solo al menu.
func _on_session_ended(reason: String) -> void:
	set_process(false)
	set_physics_process(false)
	exit_confirm.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$Title.text = "LA PARTIDA TERMINÓ"
	$Hint.text = "%s Volviendo al menú..." % reason
	get_tree().create_timer(SESSION_ENDED_NOTICE_SEC).connect("timeout", self, "_go_to_menu")

func _go_to_menu() -> void:
	get_tree().change_scene("res://scenes/Menu.tscn")
