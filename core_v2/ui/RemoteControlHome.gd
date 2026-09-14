extends Control

var InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")
var RemoteProtocol = preload("res://core_v2/net/RemoteProtocol.gd")
# Los slots del telefono son los mismos nodos que los del juego: el host de widgets con el backend
# remoto (las pantallas llegan por el canal, los slots son de este dispositivo).
const SuitOSWidgetHostScene = preload("res://core_v2/ui/hud/SuitOSWidgetHost.tscn")
const RemoteHudBackendScript = preload("res://core_v2/ui/hud/RemoteHudBackend.gd")
const HudWidgetActionScript = preload("res://core_v2/ui/hud/HudWidgetAction.gd")

const SESSION_ENDED_NOTICE_SEC := 2.5
const TITLE_PREFIX := "ODISEAOS"
# Fondo (StatusArt en el .tscn): el gamepad inalambrico apagado, y sus ondas dicen como esta la
# conexion. Las texturas viven en core_v2/ui/remote_control/ a proposito: esta escena no esta en
# export_files del preset, asi que Godot no arrastra sus dependencias, y en include_filter
# assets/**/*.png no casa con un .png suelto en assets/. Ahi no se empaquetaban y la pantalla del
# control no cargaba en el telefono (test_export_includes_preloaded_assets lo vigila).
const STATUS_WAVES_OK := Color(0.25, 0.44, 0.48, 1.0)
const STATUS_WAVES_LAG := Color(0.58, 0.44, 0.14, 1.0)
const STATUS_WAVES_LOST := Color(0.58, 0.18, 0.18, 1.0)
# Latido cada 1 s: sin respuesta en 1.6 s el pong viene tarde (lag); a los 3 s el cliente corta.
const STATUS_LAG_MS := 1600
# Lo que manda un control tactil: las acciones que empujan el joystick virtual y los
# botones, como eventos (el mismo protocolo que el teclado del escritorio). El host deriva
# de ahi lo demas igual que con controles locales: curva del stick, sprint automatico,
# flancos. hud_mode no esta a proposito: el HUD es de este dispositivo.
const FORWARDED_ANALOG_ACTIONS := ["move_left", "move_right", "move_forward", "move_backward"]
const FORWARDED_BUTTON_ACTIONS := ["jump", "run", "crouch", "interact", "focus",
	"rotate_left", "rotate_right", "zero_g_roll_left", "zero_g_roll_right",
	"tool_fire_primary", "tool_fire_secondary", "tool_next_mode", "tool_prev_mode",
	"cargol_ability"]
# Sin cuantizar, el pulgar apoyado quieto igual cambia la fuerza en el ultimo decimal y
# manda un evento por tick.
const ANALOG_STRENGTH_STEP := 0.02

onready var exit_confirm: ConfirmationDialog = $ExitConfirm
var hud_backend: Node = null
var widget_host: Control = null

var _input_provider: InputProviderV2 = null
var _remote_control_manager: Node = null
var _raw_passthrough: bool = not OS.get_name() in ["Android", "iOS"]
var _mouse_delta: Vector2 = Vector2.ZERO
# Ultima fuerza enviada por accion: solo viaja lo que cambio.
var _sent_action_strength: Dictionary = {}
var _touch_look: Vector2 = Vector2.ZERO
var _touch_zoom: float = 0.0
var _was_captured: bool = false
var _title_text: String = ""
var _status_waves: TextureRect = null
var _connection_lost: bool = false
var _status_blink: float = 0.0
var _host_paused: bool = false

func _ready() -> void:
	# El HUD es el del juego con otro backend: el host de widgets aca, y el modo HUD (dial y vista)
	# lo monta RemoteHudBackend en HUDLayer cuando se aprieta el boton del HUD o TAB.
	_remote_control_manager = get_node_or_null("/root/RemoteControlManager")
	_input_provider = InputProviderV2.new()
	# El backend antes que el host: el host lee sus slots en su _ready.
	hud_backend = RemoteHudBackendScript.new()
	hud_backend.name = "HudBackend"
	hud_backend.home = self
	add_child(hud_backend)
	widget_host = SuitOSWidgetHostScene.instance()
	widget_host.backend = hud_backend
	# Sus widgets van en la capa 5 (WIDGET_LAYER); la vista y el dial (HUDLayer, capa 6) encima, y la
	# UI tactil (capa 10) encima de todo.
	add_child(widget_host)

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

	if _raw_passthrough:
		var session_mgr = get_node_or_null("/root/SessionManager")
		if session_mgr and session_mgr.has_method("_start_mouse_capture_retry"):
			session_mgr._start_mouse_capture_retry()

	_title_text = $Title.text
	_status_waves = $StatusArt/Waves
	var client = _client()
	if client:
		_host_paused = client.host_paused
		_refresh_status()
		# Lo que el host mando mientras el control seguia en el menu (ver last_screen_list):
		# al final del _ready, con el dial y el WidgetHost ya armados.
		if client.get("last_screen_list") != null:
			_on_ui_directive("screen_list", client.last_screen_list)
		if client.get("last_screen_active") != null:
			_on_ui_directive("screen_active", client.last_screen_active)
		if client.get("last_hint") != null:
			_on_ui_directive("hint", client.last_hint)
		if client.get("last_slots") != null:
			_on_ui_directive("slots", client.last_slots)
		if client.get("last_location") != null:
			_on_ui_directive("location", client.last_location)

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
	_update_status_art(_delta)
	_poll_hud_button()
	var client = _client()
	if client == null:
		return
	# Con teclado y mouse, el dial abierto se queda con la entrada: mandar el mouse giraria
	# la camara del host mientras se apunta. En tactil NO: los controles virtuales siguen
	# manejando al host mientras se elige pantalla (el dial solo toma el dedo que apunta, y
	# ese no llega a TouchCameraControls).
	if _radial_is_open() and _raw_passthrough:
		_mouse_delta = Vector2.ZERO # lo que apunto el dial no gira la camara del host al cerrarlo
		return
	if not _raw_passthrough:
		_send_touch_actions(client)
		_send_touch_camera(client)
	elif _mouse_delta != Vector2.ZERO:
		client.send_input("mouse_delta", {"x": _mouse_delta.x, "y": _mouse_delta.y})
		_mouse_delta = Vector2.ZERO

func _send_touch_actions(client) -> void:
	for action in FORWARDED_ANALOG_ACTIONS:
		_send_action_if_changed(client, action, stepify(Input.get_action_strength(action), ANALOG_STRENGTH_STEP))
	# El boton izquierdo (tool_fire_primary) tambien lo aprieta el puntero que el sistema
	# emula de cada toque: arrastrar el joystick disparaba.
	var mobile_ui = get_node_or_null("/root/MobileUIManager")
	var from_touch: bool = mobile_ui != null and mobile_ui.has_method("is_pointer_from_touch") \
		and mobile_ui.is_pointer_from_touch()
	for action in FORWARDED_BUTTON_ACTIONS:
		var down: bool = Input.is_action_pressed(action) if InputMap.has_action(action) else false
		if action == "tool_fire_primary" and from_touch:
			down = false
		if action == "tool_fire_primary" and _widget_view_widget() != null:
			if down and not _widget_view_fire_was_down:
				HudWidgetActionScript.press_focused_button(_widget_view_widget())
			_widget_view_fire_was_down = down
			down = false
		_send_action_if_changed(client, action, 1.0 if down else 0.0)

func _send_action_if_changed(client, action: String, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	if is_equal_approx(float(_sent_action_strength.get(action, 0.0)), strength):
		return
	_sent_action_strength[action] = strength
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = strength > 0.0
	ev.strength = strength
	var payload: Dictionary = RemoteProtocol.encode_event(ev, Vector2.ZERO)
	if not payload.empty():
		client.send_input("event", payload)

func _send_touch_camera(client) -> void:
	if _touch_look == Vector2.ZERO and _touch_zoom == 0.0:
		return
	client.send_input("touch_camera", {"x": _touch_look.x, "y": _touch_look.y, "zoom": _touch_zoom})
	_touch_look = Vector2.ZERO
	_touch_zoom = 0.0

# Lo que el host tiene apretado ya no es cierto (se solto todo, o se cayo y retomo la
# sesion): lo que siga apretado aca se vuelve a mandar en el proximo tick.
func _forget_sent_actions() -> void:
	_sent_action_strength.clear()

# Gatillo derecho del widget en modo pantalla; apretado al mostrarse no lo oprime.
var _widget_view_fire_was_down: bool = true

func _input(event: InputEvent) -> void:
	# Widget en modo pantalla: el gatillo derecho es su clic y no dispara en el host (jump y crouch
	# si siguen viajando: aca el host no esta en pausa). El mouse no: su clic va a la GUI. Lo oprime
	# el modo HUD (con teclado y gamepad) o _send_touch_actions (en tactil); aca solo no viaja.
	if _widget_view_widget() != null and not event is InputEventMouseButton \
			and event.is_action("tool_fire_primary"):
		get_tree().set_input_as_handled()
		return
	# TAB es el HUD de ESTE dispositivo (_poll_hud_button lo abre leyendo Input, y el modo HUD decide
	# tap o hold). Aca solo se lo come, para que no abra el modo HUD del SuitOS local ni viaje al host:
	# lo unico que viaja alla es la eleccion (screen_select).
	if event.is_action("hud_mode"):
		get_tree().set_input_as_handled()
		return
	# Sin boton Salir: ESC en escritorio y back en Android (PauseManager lo traduce a una accion
	# ui_cancel). Solo teclado y esa accion: en un gamepad B tambien es ui_cancel pero es saltar,
	# y tiene que seguir viajando al host. Se come el press y el release (ESC ya no pausa el host).
	if (event is InputEventKey or event is InputEventAction) and event.is_action("ui_cancel"):
		if event.is_action_pressed("ui_cancel"):
			_on_cancel_requested()
		get_tree().set_input_as_handled()
		return
	# Boton secundario: suelta el mouse de esta ventana. Esta mapeado a ui_cancel, asi que
	# reenviarlo pausaba la partida del host; y aca no soltaba nada, porque SessionManager
	# lo suelta y lo recaptura con el mismo evento (es tambien un boton de mouse apretado).
	# Un clic izquierdo lo vuelve a capturar, como antes.
	if _raw_passthrough and event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == BUTTON_RIGHT:
		if (event as InputEventMouseButton).pressed:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_tree().set_input_as_handled()
		return
	if not _raw_passthrough or not event is InputEventMouseMotion:
		return
	var captured: bool = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if captured and _was_captured:
		_mouse_delta += (event as InputEventMouseMotion).relative
	_was_captured = captured

func _unhandled_input(event: InputEvent) -> void:
	if _radial_is_open() and _raw_passthrough:
		return
	if not _raw_passthrough:
		# Un gamepad fisico en un control tactil (handheld) no empuja acciones que
		# _send_touch_actions vea como fuerza de move_*: su stick es un eje. Viaja como
		# evento, el mismo camino que en escritorio.
		if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
			return
	var client = _client()
	if client == null:
		return
	var payload: Dictionary = RemoteProtocol.encode_event(_event_for_host(event), get_viewport().get_visible_rect().size)
	if not payload.empty():
		client.send_input("event", payload)

func _event_for_host(event: InputEvent) -> InputEvent:
	if event is InputEventJoypadMotion and InputProviderV2.wants_handheld_axis_inversion() \
			and (event as InputEventJoypadMotion).axis in [JOY_AXIS_0, JOY_AXIS_1, JOY_AXIS_2, JOY_AXIS_3]:
		var corrected := event.duplicate() as InputEventJoypadMotion
		corrected.axis_value = -corrected.axis_value
		return corrected
	return event

func _notification(what: int) -> void:
	# Se va el foco o la app al fondo: nada queda apretado alla. Vale para los dos modos,
	# ahora que el tactil tambien deja estado sostenido en el host.
	if (what == MainLoop.NOTIFICATION_WM_FOCUS_OUT or what == MainLoop.NOTIFICATION_APP_PAUSED) \
			and _client():
		_client().send_input("release_all", {})
		_forget_sent_actions()

func _on_camera_drag(delta: Vector2) -> void:
	_touch_look += delta

func _on_camera_zoom(delta: float) -> void:
	_touch_zoom += delta
	hud_backend.add_zoom(delta) # la regla del zoom (ZoomRuler) sin jugador local

# Primero cierra la pantalla del HUD si hay una (como ESC en el modo HUD del host); si no,
# pide confirmar la salida del control remoto.
func _on_cancel_requested() -> void:
	if _hud_mode_active():
		_exit_hud_mode()
	else:
		_on_exit_pressed()

func _on_exit_pressed() -> void:
	if exit_confirm.visible:
		exit_confirm.hide()
	else:
		exit_confirm.popup_centered()

func _on_exit_confirmed() -> void:
	if _remote_control_manager and _remote_control_manager.client:
		_remote_control_manager.client.disconnect_from_host()
	_go_to_menu()

func _on_connection_lost() -> void:
	_connection_lost = true
	set_process(true)

func _process(_delta: float) -> void:
	var client = _client()
	var left: int = int(ceil(client.get_resume_time_left())) if client else 0
	$Title.text = "SIN CONEXIÓN · %d s" % left

func _on_connection_restored() -> void:
	_connection_lost = false
	set_process(false)
	# Durante el corte el host solto lo que tenia apretado (client_stalled): lo que siga
	# sostenido aca tiene que volver a viajar.
	_forget_sent_actions()
	_refresh_status()

# --- F4 HUD Directives ---

func _on_ui_directive(op: String, payload) -> void:
	match op:
		"host_paused":
			if typeof(payload) == TYPE_DICTIONARY:
				_host_paused = bool((payload as Dictionary).get("paused", false))
				if not is_processing():
					_refresh_status()

		"screen_list":
			if typeof(payload) == TYPE_ARRAY:
				hud_backend.apply_screen_list(payload)

		"screen_active":
			if typeof(payload) == TYPE_DICTIONARY:
				hud_backend.apply_screen_active(payload)

		"screen_data":
			if typeof(payload) == TYPE_DICTIONARY:
				var dict: Dictionary = payload as Dictionary
				var sid: String = String(dict.get("id", ""))
				var snap: Dictionary = dict.get("snapshot", {}) if typeof(dict.get("snapshot")) == TYPE_DICTIONARY else {}
				hud_backend.apply_screen_data(sid, snap)

		"slots":
			if typeof(payload) == TYPE_DICTIONARY and typeof((payload as Dictionary).get("pinned")) == TYPE_ARRAY:
				hud_backend.adopt_host_pins((payload as Dictionary)["pinned"])

		"location":
			# Arriba, el sistema del traje y el mapa donde anda el jugador en el host.
			if typeof(payload) == TYPE_DICTIONARY:
				var place: String = String((payload as Dictionary).get("name", ""))
				_title_text = TITLE_PREFIX + (" · " + place.to_upper() if not place.empty() else "")
				if not is_processing():
					_refresh_status()

		"hint":
			# El hint del interactuable que tiene delante el jugador en el host, con el mismo
			# overlay y estilo que alla (PlayerHintManager local, que aca no tiene jugador).
			if typeof(payload) == TYPE_DICTIONARY:
				var hints = get_node_or_null("/root/PlayerHintManager")
				if hints != null and hints.has_method("show_remote_hint"):
					hints.show_remote_hint(String((payload as Dictionary).get("text", "")),
						String((payload as Dictionary).get("mode", "hint")))

		"haptic":
			if typeof(payload) == TYPE_DICTIONARY:
				var intensity: float = float((payload as Dictionary).get("intensity", 1.0))
				if OS.get_name() in ["Android", "iOS"]:
					Input.vibrate_handheld(int(intensity * 100.0))

func _refresh_status() -> void:
	$Title.text = "PARTIDA EN PAUSA" if _host_paused else _title_text

# ok / lag / lost. Lag: el pong del latido viene tarde. Lost: el cliente ya corto y reintenta.
func _connection_state() -> String:
	if _connection_lost:
		return "lost"
	var client = _client()
	var since: int = client.ms_since_last_rx() if client != null and client.has_method("ms_since_last_rx") else -1
	return "lag" if since >= STATUS_LAG_MS else "ok"

func _update_status_art(delta: float) -> void:
	if not is_instance_valid(_status_waves):
		return
	match _connection_state():
		"lost":
			# Titila: se esta reintentando.
			_status_blink = fmod(_status_blink + delta, 1.0)
			var color := STATUS_WAVES_LOST
			color.a = 0.35 + 0.65 * abs(sin(_status_blink * PI))
			_status_waves.modulate = color
		"lag":
			_status_waves.modulate = STATUS_WAVES_LAG
		_:
			_status_waves.modulate = STATUS_WAVES_OK

func _hud_mode_active() -> bool:
	return hud_backend.is_hud_mode_active()

func _exit_hud_mode() -> void:
	hud_backend.close_hud_mode()

# Apretar el boton del HUD (o TAB) con el modo HUD cerrado lo abre; desde ahi el overlay decide tap
# (dial) u hold con sus muestras, igual que en el juego.
var _hud_button_was_down: bool = false

func _poll_hud_button() -> void:
	var down: bool = Input.is_action_pressed("hud_mode")
	if down and not _hud_button_was_down and not _hud_mode_active():
		hud_backend.open_hud_mode()
	_hud_button_was_down = down

# RemoteHudBackend: el modo HUD va encima de los widgets y debajo de la UI tactil. En passthrough el
# dial se queda con teclado y mouse: lo que el host tenia apretado se suelta.
func mount_hud_overlay(overlay: Control) -> void:
	$HUDLayer.add_child(overlay)
	_mouse_delta = Vector2.ZERO
	var client = _client()
	if client != null and _raw_passthrough:
		client.send_input("release_all", {})

func select_remote_screen(id: String) -> void:
	var client = _client()
	if client != null:
		client.send_ui_directive("screen_select", {"id": id})

func _radial_is_open() -> bool:
	return hud_backend.is_dial_open()

# Un widget montado aca pide ejecutar una accion: la pantalla vive en el host, asi que
# viaja por el canal (el bridge la resuelve contra su SuitOS). Lo llama HudWidgetAction.
func perform_hud_widget_action(screen_id: String, op: String, args: Dictionary = {}) -> void:
	if screen_id.empty():
		return
	send_remote_action(screen_id, op, args)

func _exit_tree() -> void:
	# Al volver al menu no queda colgado el hint de la partida del otro dispositivo.
	var hints = get_node_or_null("/root/PlayerHintManager")
	if hints != null and hints.has_method("show_remote_hint"):
		hints.show_remote_hint("")

# El widget ampliado de un hudable sin Pantalla, si es lo que se esta viendo.
func _widget_view_widget() -> Control:
	var overlay = hud_backend.get_overlay()
	if overlay == null or not overlay._widget_screen_showing():
		return null
	return overlay._mount.get_widget()

func send_remote_action(screen_id: String, op: String, args: Dictionary = {}) -> void:
	# Con el host en pausa los widgets no mandan comandos (el host tambien los rechaza).
	if _host_paused:
		return
	var client = _client()
	if client != null:
		client.send_ui_directive("remote_action", {
			"screen_id": screen_id,
			"op": op,
			"args": args
		})

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
