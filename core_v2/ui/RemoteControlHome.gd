extends Control

var InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")
var RemoteProtocol = preload("res://core_v2/net/RemoteProtocol.gd")
var RadialSelectorScene = preload("res://core_v2/ui/radial/RadialSelectorV2.tscn")
# Los slots del telefono son los mismos nodos que los del juego: el host de widgets con el backend
# remoto (las pantallas llegan por el canal, los slots son de este dispositivo).
const SuitOSWidgetHostScene = preload("res://core_v2/ui/hud/SuitOSWidgetHost.tscn")
const RemoteHudBackendScript = preload("res://core_v2/ui/hud/RemoteHudBackend.gd")
# El mismo tap/hold de TAB que el modo HUD del juego, para que se maneje igual.
const TabGesture = preload("res://core_v2/ui/hud/HudTabGesture.gd")
const HudWidgetActionScript = preload("res://core_v2/ui/hud/HudWidgetAction.gd")

const SESSION_ENDED_NOTICE_SEC := 2.5
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
# Un arrastre por debajo de esto es un toque, no un gesto de apuntado (umbral de
# HudModeOverlay, que resuelve el mismo dial con los mismos dedos).
const RADIAL_TOUCH_MIN_DRAG := 12.0
# RadialSelectorV2.tscn viene medido para el dial 3D del ascensor (opciones de 260x130,
# fuente 104). Aca se usa la MISMA configuracion que el modo HUD del juego
# (HudModeOverlay.tscn): el dial del control se ve igual que el de la partida. Se
# reescala la instancia, no la escena compartida.
const RADIAL_OPTION_SIZE := Vector2(400.0, 48.0)
# Resolucion de diseño de una Pantalla de hudable (screen_resolution de HudViewPresenter.tscn).
# Un widget sin Pantalla ocupa ese mismo lugar: si no, se estiraba a todo el ViewHost.
const DEFAULT_SCREEN_DESIGN := Vector2(1280.0, 816.0)
const RADIAL_FONT_SIZE := 22
const RADIAL_FONT_DATA := "res://assets/fonts/SixtyFour-Regular-FontData.tres"
const RADIAL_DIM_COLOR := Color(0.0, 0.05, 0.08, 0.4)
# Apuntado con mouse: un stick virtual sobre el dial. Solo cuenta el angulo, asi que el
# radio es nada mas el tope del acumulado y la zona muerta el minimo para tener rumbo.
const RADIAL_AIM_RADIUS := 120.0
# Stick o WASD sobre el dial: por debajo de esto el stick en reposo haria titilar el rumbo.
const RADIAL_MOVE_DEADZONE := 0.35
const RADIAL_AIM_DEADZONE := 8.0

onready var exit_confirm: ConfirmationDialog = $ExitConfirm
var hud_backend: Node = null
var widget_host: Control = null
onready var fullscreen_overlay: Control = $HUDLayer/FullScreenOverlay
onready var view_host: Container = $HUDLayer/FullScreenOverlay/ViewHost
onready var radial_overlay: Control = $HUDLayer/RadialOverlay

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

var _radial_selector: Control = null
var _fullscreen_view_node: Node = null
# Dedo que esta apuntando el dial, y de donde salio: el angulo se mide contra el punto
# inicial del toque, no contra el ultimo delta.
var _radial_touch_index: int = -1
var _radial_touch_start: Vector2 = Vector2.ZERO
var _radial_aim: Vector2 = Vector2.ZERO
var _radial_labels: Array = []
var _tab_gesture = TabGesture.new()
# El slot que pidio el dial (tocar un widget cuya pantalla no esta en la partida): elegir lo fija
# ahi. Abierto con TAB (-1) no fija nada: nada se autoasigna.
var _radial_target_slot: int = -1

func _ready() -> void:
	# Sin mouse virtual, a proposito: en un handheld se activaba con cualquier movimiento del
	# stick y convertia A/B en clics locales (comiendoselos: nunca llegaban al host). El dial
	# se apunta con el stick (_aim_radial_with_move_actions), como el modo HUD del host.
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

	if view_host:
		view_host.connect("resized", self, "_fit_view_node")

	_setup_radial_selector()

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

	set_process(false)
	call_deferred("_connect_touch_camera")

func _setup_radial_selector() -> void:
	if RadialSelectorScene == null or radial_overlay == null:
		return
	_radial_selector = RadialSelectorScene.instance()
	_radial_selector.option_size = RADIAL_OPTION_SIZE
	_radial_selector.option_font = _radial_font()
	# La aguja marca estado (el piso donde esta el carro). Aca solo se elige: no hay estado.
	_radial_selector.show_indicator = false
	radial_overlay.add_child(_radial_selector)
	# Tapa lo de atras mientras se elige, igual que el Dim del modo HUD del juego.
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = RADIAL_DIM_COLOR
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radial_selector.add_child(dim)
	_radial_selector.move_child(dim, 0)
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	# El titulo va oculto, como en el modo HUD: la lista ya dice que es.
	var title_label: Label = _radial_selector.get_node_or_null("Title") as Label
	if title_label != null:
		title_label.visible = false
	# Sin texto de ayuda: igual que el dial del modo HUD del host.
	_radial_selector.connect("option_selected", self, "_on_radial_option_selected")
	_radial_selector.connect("cancelled", self, "_on_radial_cancelled")

# La misma fuente que el dial del modo HUD del juego (Heading_Font, con su contorno).
func _radial_font() -> Font:
	var font := DynamicFont.new()
	font.font_data = load(RADIAL_FONT_DATA)
	font.size = RADIAL_FONT_SIZE
	font.outline_size = 2
	font.outline_color = Color(0.0, 0.203922, 0.270588, 0.705882)
	return font

func _connect_touch_camera() -> void:
	var mobile_ui = get_node_or_null("/root/MobileUIManager")
	if mobile_ui and mobile_ui._touch_camera:
		mobile_ui._touch_camera.connect("camera_drag", self, "_on_camera_drag")
		mobile_ui._touch_camera.connect("camera_zoom", self, "_on_camera_zoom")

func _client() -> Node:
	return _remote_control_manager.client if _remote_control_manager else null

func _physics_process(_delta: float) -> void:
	_update_status_art(_delta)
	# Apuntar antes del gesto: el tick en que se suelta TAB todavia mueve la marca.
	_aim_radial_with_move_actions()
	_step_tab_gesture()
	_aim_radial_with_hud_button()
	var client = _client()
	if client == null:
		return
	# Con teclado y mouse, el dial abierto se queda con la entrada: mandar el mouse giraria
	# la camara del host mientras se apunta. En tactil NO: los controles virtuales siguen
	# manejando al host mientras se elige pantalla (el dial solo toma el dedo que apunta, y
	# ese no llega a TouchCameraControls).
	if _radial_is_open() and _raw_passthrough:
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
	# si siguen viajando: aca el host no esta en pausa). El mouse no: su clic va a la GUI.
	if _widget_view_widget() != null and not event is InputEventMouseButton \
			and event.is_action("tool_fire_primary"):
		# En tactil lo oprime _send_touch_actions, que lee el mismo gatillo del Input.
		if _raw_passthrough and event.is_action_pressed("tool_fire_primary"):
			HudWidgetActionScript.press_focused_button(_widget_view_widget())
		get_tree().set_input_as_handled()
		return
	# Antes que nada y antes que nadie: _input corre en orden inverso del arbol, asi que
	# esta escena ve el toque antes que los controles tactiles del autoload (que lo
	# consumirian con set_input_as_handled y dejarian al dial sin entrada).
	if _radial_is_open() and _handle_radial_input(event):
		get_tree().set_input_as_handled()
		return
	_watch_tap_outside_view(event)
	# TAB es el HUD de ESTE dispositivo, y tap o hold lo decide _step_tab_gesture leyendo
	# Input (que no depende de que el evento siga viaje). Aca solo se lo come, para que no
	# abra el modo HUD del host: lo unico que viaja alla es la eleccion (screen_select).
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

# Tocar fuera de la pantalla la cierra, como en el host (HudModeOverlay._is_outside_view): en
# tactil no hay TAB, y sin esto no habia forma de salir de una pantalla. Solo un TOQUE: un
# arrastre es la camara tactil y sigue girando sin cerrar nada. No se consume el evento (la
# camara tactil lleva la cuenta de su dedo y se quedaria trabada sin el release).
var _view_tap_index: int = -1
var _view_tap_start: Vector2 = Vector2.ZERO

func _watch_tap_outside_view(event: InputEvent) -> void:
	if hud_backend.get_active_screen_id().empty() or _radial_is_open():
		_view_tap_index = -1
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _view_tap_index < 0 and _is_outside_view(touch.position):
				_view_tap_index = touch.index
				_view_tap_start = touch.position
		elif touch.index == _view_tap_index:
			_view_tap_index = -1
			if (touch.position - _view_tap_start).length() < RADIAL_TOUCH_MIN_DRAG:
				_exit_hud_mode()
	elif _raw_passthrough and event is InputEventMouseButton:
		# Con el mouse capturado la posicion esta congelada en el centro (dentro de la vista):
		# solo cuenta con el cursor suelto, como un clic fuera en el host.
		var click := event as InputEventMouseButton
		if click.button_index == BUTTON_LEFT and click.pressed \
				and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED \
				and _is_outside_view(click.position):
			_exit_hud_mode()

# Fuera de la pantalla, y tampoco sobre un control virtual (el joystick caminando no cierra nada).
func _is_outside_view(point: Vector2) -> bool:
	return not _view_screen_rect().has_point(point) and not _is_on_virtual_controls(point)

# El area que ocupa la vista en pantalla: la textura escalada del Viewport, o el ViewHost
# entero cuando se monto el widget sin tamaño de diseño.
func _view_screen_rect() -> Rect2:
	var container = _view_viewport_container()
	if container != null:
		return Rect2(container.rect_global_position, container.rect_size * container.rect_scale)
	# El widget de reemplazo cuenta como el lugar de la Pantalla: tocar fuera de el cierra.
	var frame = _widget_placeholder_frame()
	if frame != null:
		var space: Rect2 = _screen_space_in(frame.rect_size)
		return Rect2(frame.rect_global_position + space.position, space.size)
	return view_host.get_global_rect() if view_host != null else Rect2()

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
				_update_radial_options()

		"screen_active":
			if typeof(payload) == TYPE_DICTIONARY:
				hud_backend.apply_screen_active(payload)
				_update_fullscreen_view()

		"screen_data":
			if typeof(payload) == TYPE_DICTIONARY:
				var dict: Dictionary = payload as Dictionary
				var sid: String = String(dict.get("id", ""))
				var snap: Dictionary = dict.get("snapshot", {}) if typeof(dict.get("snapshot")) == TYPE_DICTIONARY else {}
				hud_backend.apply_screen_data(sid, snap)
				if not sid.empty() and sid == hud_backend.get_active_screen_id():
					_update_fullscreen_view()

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

# Mismo manejo que el modo HUD del juego (HudModeOverlay): un tap de TAB abre siempre el dial y
# otro lo cierra; el hold lo abre como cuasimodo. La muestra sale de Input en vivo porque en el
# control no hay stream grabado que reproducir.
func _step_tab_gesture() -> void:
	var gesture: int = _tab_gesture.feed(Input.is_action_pressed("hud_mode"))
	if gesture == TabGesture.TAP:
		if _radial_is_open():
			_close_radial()
		elif _hud_mode_active() and _radial_screen_ids().size() <= 1:
			_exit_hud_mode() # con una sola pantalla no hay dial: el tap la cierra
		else:
			_open_radial()
	elif gesture == TabGesture.HOLD and not _radial_is_open():
		_tab_hold_active = true
		_picked_during_hold = false
		_open_radial()
	elif gesture == TabGesture.HOLD_RELEASE and _tab_hold_active:
		_release_tab_hold()

# El dial abierto por mantener TAB es un cuasimodo, igual que en el host (HudModeOverlay):
var _tab_hold_active: bool = false
var _picked_during_hold: bool = false

# Soltar TAB tras el hold. Si ya se eligio con TAB apretado fue un vistazo: soltar sale. Si el
# dial sigue abierto, lo marcado queda elegido (el dial no se queda abierto); sin nada marcado
# se cierra y vuelve la pantalla que habia, si habia una.
func _release_tab_hold() -> void:
	_tab_hold_active = false
	if _picked_during_hold:
		_picked_during_hold = false
		_close_radial()
		# Sin esperar el screen_active del host: se pudo soltar antes de que llegara, y con
		# _exit_hud_mode (que mira la pantalla activa) la vista se abria despues de soltar.
		var client = _client()
		if client != null:
			client.send_ui_directive("screen_select", {"id": ""})
		return
	if not _radial_is_open():
		return
	if _radial_selector.has_selection():
		_radial_selector.confirm() # -> _on_radial_option_selected, ya sin hold: se queda
	else:
		_close_radial() # devuelve la vista si hay una pantalla abierta

func _hud_mode_active() -> bool:
	return _radial_is_open() or not hud_backend.get_active_screen_id().empty()

func _exit_hud_mode() -> void:
	_close_radial()
	if not hud_backend.get_active_screen_id().empty():
		select_remote_screen("")

func select_remote_screen(id: String) -> void:
	var client = _client()
	if client != null:
		client.send_ui_directive("screen_select", {"id": id})

# Lo que pide el host de widgets (RemoteHudBackend.open_hud_mode): el dial para un slot, o una
# pantalla.
func open_hud_from_backend(radial: bool, screen_id: String, slot: int) -> bool:
	if radial:
		_open_radial(slot)
		return _radial_is_open()
	select_remote_screen(screen_id)
	return true

func _open_radial(slot: int = -1) -> void:
	_radial_target_slot = slot
	if not is_instance_valid(_radial_selector):
		return
	# Como el modo HUD del host (HudModeOverlay._open_radial): con una sola pantalla no hay
	# nada que elegir y se entra directo; sin ninguna, no hay dial.
	var screens: int = _radial_screen_ids().size()
	if screens <= 1:
		if screens == 1:
			_on_radial_option_selected(0)
		return
	_update_radial_options()
	_radial_touch_index = -1
	_radial_aim = Vector2.ZERO
	# Lo que quedo acumulado antes de abrir no se le manda al host al cerrar: seria un
	# tiron de camara con el dial ya cerrado.
	_mouse_delta = Vector2.ZERO
	# En passthrough el host tiene apretado lo que se estaba apretando aca; si el reenvio
	# se corta sin avisar se queda con la tecla pegada.
	var client = _client()
	if client != null and _raw_passthrough:
		client.send_input("release_all", {})
	# Mientras se elige la vista se esconde (el Dim tapa el fondo); los widgets quedan y aparecen los
	# contornos de los slots vacios, como en el modo HUD del juego.
	if fullscreen_overlay != null:
		fullscreen_overlay.visible = false
	_radial_selector.open()
	hud_backend.notify_hud_state()

func _radial_is_open() -> bool:
	return is_instance_valid(_radial_selector) and _radial_selector.is_open()

func _close_radial() -> void:
	_radial_touch_index = -1
	_radial_aim = Vector2.ZERO
	var was_open: bool = _radial_is_open()
	if is_instance_valid(_radial_selector):
		_radial_selector.close()
	# La vista vuelve solo si hay una pantalla abierta.
	if fullscreen_overlay != null:
		fullscreen_overlay.visible = not hud_backend.get_active_screen_id().empty()
		_focus_widget_view()
	if was_open:
		hud_backend.notify_hud_state()

# true = el evento era del dial y no sale de este dispositivo.
func _handle_radial_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		# Back de Android / Esc: cierra el dial, no la sesion.
		_close_radial()
		return true

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			# Los controles virtuales no se apagan nunca: un dedo que empieza sobre el
			# joystick o un boton es de ellos (se sigue caminando con el dial abierto), y
			# tambien cualquier dedo extra mientras otro ya esta apuntando.
			if _radial_touch_index >= 0 or _is_on_virtual_controls(touch.position):
				return false
			_radial_touch_index = touch.index
			_radial_touch_start = touch.position
			return true
		if touch.index != _radial_touch_index:
			return false # dedo de un control virtual (o el que abrio el dial)
		_radial_touch_index = -1
		if (touch.position - _radial_touch_start).length() >= RADIAL_TOUCH_MIN_DRAG:
			# Apunto arrastrando: al soltar se confirma lo que quedo marcado (confirm()
			# no hace nada si el gesto nunca llego a marcar una opcion).
			_radial_selector.confirm()
		elif _radial_selector.option_at(touch.position) >= 0:
			_radial_selector.point_at(touch.position) # toque directo sobre la etiqueta
			_radial_selector.confirm()
		else:
			_close_radial() # toque fuera de toda opcion
		return true

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _radial_touch_index:
			return false # el joystick arrastrando: sigue siendo suyo
		if (drag.position - _radial_touch_start).length() >= RADIAL_TOUCH_MIN_DRAG:
			_point_radial_at(drag.position - _radial_touch_start)
		return true

	if not _raw_passthrough:
		# En tactil el mouse que llega es el emulado de los toques: un arrastre del joystick
		# apuntaria el dial y un toque en un boton lo confirmaria. Y ninguna otra entrada es
		# del dial: los controles virtuales siguen andando mientras se elige.
		return false

	if event is InputEventMouseMotion:
		# El mouse esta CAPTURADO (asi se maneja al host) y ahi la posicion del evento
		# queda congelada en el centro: apuntar por posicion absoluta es imposible. Se
		# acumula el movimiento relativo como un stick virtual sobre el dial.
		_radial_aim = (_radial_aim + (event as InputEventMouseMotion).relative).clamped(RADIAL_AIM_RADIUS)
		if _radial_aim.length() >= RADIAL_AIM_DEADZONE:
			_point_radial_at(_radial_aim)
		return true

	if event.is_action_pressed("ui_accept") \
			or (event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == BUTTON_LEFT \
				and (event as InputEventMouseButton).pressed):
		# Se elige apuntando. Un clic sin nada marcado no cierra: el dial se queda hasta
		# terminar de elegir, y para salir estan Esc, el boton derecho o TAB.
		_radial_selector.confirm()
		return true

	# Con teclado y mouse todo lo demas tambien se queda aca: con el dial abierto la entrada
	# es de este dispositivo, no del host (en tactil ya salio arriba).
	return true

# Sin mouse (un handheld con gamepad, o solo teclado) el dial se apunta con lo mismo que se
# camina: el stick o WASD. Es lo que hace el modo HUD del host con move_vec. En tactil no:
# ahi el joystick virtual sigue caminando y el dial lo apunta el dedo.
func _aim_radial_with_move_actions() -> void:
	if not _radial_is_open() or not _raw_passthrough:
		return
	var move := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward"))
	# Las acciones del InputMap no pasan por la correccion de ejes del handheld (la hace
	# InputProviderV2 al leer el stick): mismo arreglo que tenia el mouse virtual.
	if InputProviderV2.wants_handheld_axis_inversion():
		move = -move
	if move.length() >= RADIAL_MOVE_DEADZONE:
		_point_radial_at(move)

# El boton tactil del HUD es un joystick, como en el host (HudModeOverlay._aim_with_hud_button):
# arrastrar el dedo desde donde se apoyo apunta el dial y soltarlo elige (_release_tab_hold). Si
# arrastra antes del umbral del hold el dial se abre ya: un arrastre nunca es un tap.
func _aim_radial_with_hud_button() -> void:
	var mobile_ui = get_node_or_null("/root/MobileUIManager")
	var drag: Vector2 = mobile_ui.hud_button_drag() if mobile_ui != null and mobile_ui.has_method("hud_button_drag") \
		else Vector2.ZERO
	if drag.length() < RADIAL_TOUCH_MIN_DRAG:
		return
	if Input.is_action_pressed("hud_mode") and not _radial_is_open() and not _tab_hold_active:
		_tab_gesture.promote_to_hold()
		_tab_hold_active = true
		_picked_during_hold = false
		_open_radial()
	if _radial_is_open():
		_point_radial_at(drag)

func _is_on_virtual_controls(point: Vector2) -> bool:
	var mobile_ui = get_node_or_null("/root/MobileUIManager")
	return mobile_ui != null and mobile_ui.has_method("is_point_on_touch_controls") \
		and mobile_ui.is_point_on_touch_controls(point)

# Solo cuenta el angulo: la magnitud fija saca del hub_epsilon aunque el arrastre sea corto.
func _point_radial_at(direction: Vector2) -> void:
	if direction.length_squared() <= 0.0000001:
		return
	_radial_selector.point_at(_radial_selector.rect_size * 0.5 + direction.normalized() * 100.0)

# Las pantallas del dial, en el orden del host. Sin opcion de "cerrar": como en el host, se sale
# tocando fuera, con ESC/back o soltando TAB.
func _radial_screen_ids() -> Array:
	return hud_backend.get_registered_screens()

func _update_radial_options() -> void:
	if not is_instance_valid(_radial_selector):
		return
	var labels: Array = []
	for sid in _radial_screen_ids():
		var title: String = hud_backend.screen_field(sid, "title")
		labels.append(title if not title.empty() else sid)
	# El host reenvia screen_list en CADA cambio de widget (bateria, estado del terminal),
	# o sea varias veces por segundo. set_options() libera las Labels y resetea el marcado,
	# asi que reconstruir con las mismas etiquetas le sacaba el foco al dial abierto cada
	# pocos frames: no se podia elegir nada.
	if labels == _radial_labels:
		return
	_radial_labels = labels
	_radial_selector.set_options(labels)

func _on_radial_option_selected(index: int) -> void:
	if _tab_hold_active:
		_picked_during_hold = true
	var slot: int = _radial_target_slot
	_radial_target_slot = -1
	_close_radial()
	var ids: Array = _radial_screen_ids()
	if index < 0 or index >= ids.size():
		return
	var sid: String = ids[index]
	# Solo el dial que pidio un slot lo fija; el de TAB nada mas abre la pantalla.
	if slot >= 0:
		hud_backend.pin_to_slot(slot, sid)
	select_remote_screen(sid)

func _on_radial_cancelled() -> void:
	_close_radial()

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

# La vista se ve igual que en el host solo si se arma igual: el host la renderiza en un
# Viewport a su resolucion de diseño (1280x816 en el HangingDisplay) y muestra esa
# textura. Escalar el Control directo lo remuestrea contra el stretch del proyecto y ni
# las fuentes ni los paneles quedan iguales. Aca se escala la TEXTURA, no el layout.
func _fit_view_node() -> void:
	var container = _view_viewport_container()
	if container == null:
		_fit_widget_placeholder()
		return
	var design: Vector2 = hud_backend.active_view_size()
	var frame = container.get_parent()
	if design.x <= 0.0 or design.y <= 0.0 or not (frame is Control):
		return
	var host: Vector2 = (frame as Control).rect_size
	if host.x <= 0.0 or host.y <= 0.0:
		return
	var factor: float = min(host.x / design.x, host.y / design.y)
	container.rect_size = design
	container.rect_scale = Vector2(factor, factor)
	container.rect_position = (host - design * factor) * 0.5

# Sin Pantalla: el widget ampliado de forma uniforme y centrado dentro del lugar que ocuparia una
# Pantalla de DEFAULT_SCREEN_DESIGN, igual de grande que Criogenia y no a pantalla completa.
func _fit_widget_placeholder() -> void:
	var frame = _widget_placeholder_frame()
	if frame == null or not is_instance_valid(_fullscreen_view_node):
		return
	var space: Rect2 = _screen_space_in(frame.rect_size)
	var natural: Vector2 = _fullscreen_view_node.get_combined_minimum_size()
	if space.size.x <= 0.0 or natural.x <= 0.0 or natural.y <= 0.0:
		return
	var factor: float = min(space.size.x / natural.x, space.size.y / natural.y)
	_fullscreen_view_node.rect_size = natural
	_fullscreen_view_node.rect_scale = Vector2(factor, factor)
	_fullscreen_view_node.rect_position = space.position + (space.size - natural * factor) * 0.5

# El rect que ocupa una Pantalla de DEFAULT_SCREEN_DESIGN calzada en host_size (como _fit_view_node).
static func _screen_space_in(host_size: Vector2) -> Rect2:
	if host_size.x <= 0.0 or host_size.y <= 0.0:
		return Rect2()
	var factor: float = min(host_size.x / DEFAULT_SCREEN_DESIGN.x, host_size.y / DEFAULT_SCREEN_DESIGN.y)
	return Rect2((host_size - DEFAULT_SCREEN_DESIGN * factor) * 0.5, DEFAULT_SCREEN_DESIGN * factor)

# El widget ampliado de un hudable sin Pantalla, si es lo que se esta viendo.
func _widget_view_widget() -> Control:
	if fullscreen_overlay == null or not fullscreen_overlay.visible or _widget_placeholder_frame() == null:
		return null
	return _fullscreen_view_node as Control if is_instance_valid(_fullscreen_view_node) else null

# Sin mouse: foco en su primer boton, para navegarlo con la cruceta y oprimirlo con el gatillo.
func _focus_widget_view() -> void:
	var widget: Control = _widget_view_widget()
	if widget == null:
		return
	_widget_view_fire_was_down = true
	HudWidgetActionScript.focus_first_button(widget)

func _widget_placeholder_frame() -> Control:
	return view_host.get_node_or_null("WidgetFrame") as Control if view_host != null else null

func _view_viewport_container() -> ViewportContainer:
	var frame = view_host.get_node_or_null("ViewFrame") if view_host != null else null
	if frame == null:
		return null
	return frame.get_node_or_null("ViewViewport") as ViewportContainer

func _free_fullscreen_view() -> void:
	_fullscreen_view_node = null
	if view_host == null:
		return
	# Una sola pantalla a la vez: todo lo que cuelga del ViewHost es la vista anterior, venga en
	# su marco con Viewport (con tamaño de diseño, como Criogenia) o montada directo (un widget
	# ampliado, como la linterna). Liberando solo el marco, la linterna quedaba dibujada detras.
	for child in view_host.get_children():
		view_host.remove_child(child)
		child.queue_free()

func _update_fullscreen_view() -> void:
	if fullscreen_overlay == null or view_host == null:
		return

	var sid: String = hud_backend.get_active_screen_id()
	if sid.empty():
		fullscreen_overlay.visible = false
		_free_fullscreen_view()
		return

	# Si el dial esta abierto la vista se monta pero no se muestra: la tapa el dial hasta
	# que se termine de elegir (_close_radial la devuelve).
	fullscreen_overlay.visible = not _radial_is_open()
	var snap: Dictionary = hud_backend.active_screen.get("snapshot", {})
	if snap.empty():
		snap = hud_backend.snapshots.get(sid, {})

	if is_instance_valid(_fullscreen_view_node) and _get_node_screen_id(_fullscreen_view_node) == sid:
		_hydrate_node(_fullscreen_view_node, snap)
		return

	_free_fullscreen_view()

	var view_scene: PackedScene = hud_backend.resolve_view_scene(sid)
	if view_scene == null:
		view_scene = hud_backend.resolve_widget_scene(sid)

	var node: Control = null
	if view_scene != null:
		node = view_scene.instance() as Control
	else:
		node = PanelContainer.new()
		var label = Label.new()
		label.name = "TitleLabel"
		node.add_child(label)

	if node != null:
		_set_node_screen_id(node, sid)
		var design: Vector2 = hud_backend.active_view_size()
		if design.x > 0.0 and design.y > 0.0:
			# view_host es un MarginContainer y a un hijo directo le impone tamaño y
			# posicion: el marco es el que el estira, y adentro va el Viewport a su
			# resolucion de diseño, como lo arma el host.
			var frame := Control.new()
			frame.name = "ViewFrame"
			frame.mouse_filter = Control.MOUSE_FILTER_PASS
			view_host.add_child(frame)
			frame.set_anchors_and_margins_preset(Control.PRESET_WIDE)
			var container := ViewportContainer.new()
			container.name = "ViewViewport"
			# stretch=false: el Viewport se queda en su tamaño de diseño y lo que se
			# escala es como se dibuja, no como se reparte adentro.
			container.stretch = false
			container.rect_size = design
			container.mouse_filter = Control.MOUSE_FILTER_PASS
			var viewport := Viewport.new()
			viewport.size = design
			viewport.usage = Viewport.USAGE_2D
			viewport.transparent_bg = true
			viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
			frame.add_child(container)
			container.add_child(viewport)
			viewport.add_child(node)
			node.set_anchors_and_margins_preset(Control.PRESET_WIDE)
			_fullscreen_view_node = node
			# El contenedor reparte tamaños en diferido: el calzado va despues.
			call_deferred("_fit_view_node")
		else:
			# Sin Pantalla: el widget ampliado va en su propio marco (a un hijo directo el
			# MarginContainer le impone su tamaño) y se calza en _fit_widget_placeholder.
			var widget_frame := Control.new()
			widget_frame.name = "WidgetFrame"
			widget_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			view_host.add_child(widget_frame)
			widget_frame.set_anchors_and_margins_preset(Control.PRESET_WIDE)
			widget_frame.add_child(node)
			node.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_fullscreen_view_node = node
			call_deferred("_fit_view_node")
			call_deferred("_focus_widget_view")
		_hydrate_node(node, snap)

func _set_node_screen_id(node: Node, sid: String) -> void:
	if "screen_id" in node:
		node.set("screen_id", sid)
	node.set_meta("screen_id", sid)

func _get_node_screen_id(node: Node) -> String:
	if not is_instance_valid(node):
		return ""
	if node.has_meta("screen_id"):
		return String(node.get_meta("screen_id"))
	if "screen_id" in node:
		return String(node.get("screen_id"))
	return ""

func _hydrate_node(node: Node, snap: Dictionary) -> void:
	if node.has_method("update_snapshot"):
		node.update_snapshot(snap)
	elif node.has_method("set_snapshot"):
		node.set_snapshot(snap)
	else:
		var label = node.get_node_or_null("TitleLabel")
		if label is Label:
			var title: String = String(snap.get("title", snap.get("id", "Screen")))
			label.text = "[REMOTE] " + title

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
