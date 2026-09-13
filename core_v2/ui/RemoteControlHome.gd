extends Control

var InputProviderV2 = preload("res://core_v2/input/InputProviderV2.gd")
var RemoteProtocol = preload("res://core_v2/net/RemoteProtocol.gd")
var RadialSelectorScene = preload("res://core_v2/ui/radial/RadialSelectorV2.tscn")
var HoloTerminalWidgetScene = preload("res://core_v2/ui/hud/HoloTerminalWidget.tscn")
# El mismo tap/hold de TAB que el modo HUD del juego, para que se maneje igual.
const TabGesture = preload("res://core_v2/ui/hud/HudTabGesture.gd")
const HudWidgetActionScript = preload("res://core_v2/ui/hud/HudWidgetAction.gd")

const SESSION_ENDED_NOTICE_SEC := 2.5
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

# Layout de slots: las mismas filas FIJAS del host (SuitOSWidgetHost): A arriba, B
# debajo, sin subir si A queda vacio, y escaladas por render_scale. El control se ve
# igual aunque el telefono baje la resolucion, y dos widgets nunca se superponen.
const SLOT_ROWS := ["slot_a", "slot_b"]
const SLOT_ROW_HEIGHT := 96.0 # el widget mas alto hoy (SystemStatusWidget) mide 90
const SLOT_GAP := 8.0
const SLOT_PADDING := 16.0
# Hold sobre un widget = dial (mismo umbral que SuitOSWidgetHost usa alla).
const WIDGET_HOLD_MSEC := 400

const UIScaleCompensator = preload("res://core_v2/ui/UIScaleCompensator.gd")

onready var exit_confirm: ConfirmationDialog = $ExitConfirm
# El HUD vive en HUDLayer (capa 5): por encima de la escena, DEBAJO de la UI tactil (capa 10),
# que se dibuja siempre encima de las pantallas. Para que los widgets se puedan tocar igual,
# mientras esta pantalla esta abierta el Container de MobileUI deja pasar el toque de GUI
# (_let_touches_through_touch_ui): con su STOP por defecto se quedaba con todos.
onready var widget_host: Control = $HUDLayer/WidgetHost
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
var _hint_text: String = ""
var _host_paused: bool = false

# F4 HUD Client State
var _screen_list: Array = []
var _snapshots_cache: Dictionary = {}
var _active_remote_screen: Dictionary = {}
var _local_pinned_screen_id: String = ""
var _mounted_widgets: Dictionary = {} # slot -> Node
var _radial_selector: Control = null
var _fullscreen_view_node: Node = null
# Dedo que esta apuntando el dial, y de donde salio: el angulo se mide contra el punto
# inicial del toque, no contra el ultimo delta.
var _radial_touch_index: int = -1
var _radial_touch_start: Vector2 = Vector2.ZERO
var _radial_aim: Vector2 = Vector2.ZERO
var _radial_labels: Array = []
var _tab_gesture = TabGesture.new()
var _widget_press_msec: int = 0
# La pantalla que el slot A eligio por relevancia: es la que abre un tap de TAB si no hay
# ninguna fijada.
var _slot_a_id: String = ""

func _ready() -> void:
	# Sin mouse virtual, a proposito: en un handheld se activaba con cualquier movimiento del
	# stick y convertia A/B en clics locales (comiendoselos: nunca llegaban al host). El dial
	# se apunta con el stick (_aim_radial_with_move_actions), como el modo HUD del host.
	_remote_control_manager = get_node_or_null("/root/RemoteControlManager")
	_input_provider = InputProviderV2.new()
	_let_touches_through_touch_ui(true)
	# Los slots se ubican en el espacio nominal de escala 1.0, como la UI tactil: con el
	# render_scale bajo, un margen en pixeles fijos despegaba el slot del borde. El
	# compensador se reaplica solo cuando cambia el viewport, tambien en runtime.
	var compensator: Control = UIScaleCompensator.new()
	compensator.name = "WidgetHostScale"
	compensator.target_path = NodePath("../WidgetHost") # hermano en HUDLayer
	$HUDLayer.add_child(compensator)

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
	if widget_host and not get_viewport().is_connected("size_changed", self, "_relayout_widgets"):
		get_viewport().connect("size_changed", self, "_relayout_widgets")

	_setup_radial_selector()

	if _raw_passthrough:
		$Hint.text = "Controlando con teclado y mouse. El botón derecho libera el mouse; un clic lo vuelve a capturar. TAB abre las pantallas de este dispositivo."
		var session_mgr = get_node_or_null("/root/SessionManager")
		if session_mgr and session_mgr.has_method("_start_mouse_capture_retry"):
			session_mgr._start_mouse_capture_retry()

	_title_text = $Title.text
	_hint_text = $Hint.text
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
	var status_label: Label = _radial_selector.get_node_or_null("Status") as Label
	if status_label != null:
		status_label.add_font_override("font", _radial_font())
	# Apuntar fuera del dial es la salida en mouse, pero con el dedo no hay puntero que
	# mirar: sin este aviso el dial no se ve como algo que se pueda cerrar.
	_radial_selector.set_status("Esc o botón derecho para cerrar" if _raw_passthrough \
		else "Toque fuera para cerrar")
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

# Donde cayo el ultimo toque o clic, en coordenadas de pantalla (_input las ve antes que la GUI).
var _last_pointer_position: Vector2 = Vector2.ZERO
var _widget_press_on_button: bool = false
# Gatillo derecho del widget en modo pantalla; apretado al mostrarse no lo oprime.
var _widget_view_fire_was_down: bool = true

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		_last_pointer_position = event.position
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
	if String(_active_remote_screen.get("id", "")).empty() or _radial_is_open():
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
	$Title.text = "SIN CONEXIÓN"
	set_process(true)

func _process(_delta: float) -> void:
	var client = _client()
	var left: int = int(ceil(client.get_resume_time_left())) if client else 0
	$Hint.text = "Se perdió la conexión con el otro dispositivo. Reintentando... (%d s)" % left

func _on_connection_restored() -> void:
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
				_screen_list = (payload as Array).duplicate(true)
				# La lista trae el snapshot de cada pantalla: es lo que hace que el widget
				# muestre su nombre y su estado reales y no el id con "EN ESPERA".
				for item in _screen_list:
					if typeof(item) != TYPE_DICTIONARY:
						continue
					var sid: String = String((item as Dictionary).get("id", ""))
					var snap = (item as Dictionary).get("snapshot")
					if not sid.empty() and typeof(snap) == TYPE_DICTIONARY:
						_snapshots_cache[sid] = (snap as Dictionary).duplicate(true)
				_reevaluate_slots()
				_update_radial_options()

		"screen_active":
			if typeof(payload) == TYPE_DICTIONARY:
				_active_remote_screen = (payload as Dictionary).duplicate(true)
				_update_fullscreen_view()

		"screen_data":
			if typeof(payload) == TYPE_DICTIONARY:
				var dict: Dictionary = payload as Dictionary
				var sid: String = String(dict.get("id", ""))
				var snap: Dictionary = dict.get("snapshot", {}) if typeof(dict.get("snapshot")) == TYPE_DICTIONARY else {}
				if not sid.empty():
					_snapshots_cache[sid] = snap.duplicate(true)
					_reevaluate_slots()
					if sid == String(_active_remote_screen.get("id", "")):
						_active_remote_screen["snapshot"] = snap.duplicate(true)
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
	if _host_paused:
		$Title.text = "PARTIDA EN PAUSA"
		$Hint.text = "La partida está en pausa en el otro dispositivo." + (" Esc la reanuda." if _raw_passthrough else "")
	else:
		$Title.text = _title_text
		$Hint.text = _hint_text

# Mismo manejo que el modo HUD del juego (HudModeOverlay): un tap de TAB abre la ultima
# pantalla y vuelve a cerrarla; el hold es el que saca el dial. La muestra sale de Input en
# vivo porque en el control no hay stream grabado que reproducir.
func _step_tab_gesture() -> void:
	var gesture: int = _tab_gesture.feed(Input.is_action_pressed("hud_mode"))
	if gesture == TabGesture.TAP:
		if _hud_mode_active():
			_exit_hud_mode()
		else:
			_open_last_screen()
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
	return _radial_is_open() or not String(_active_remote_screen.get("id", "")).empty()

func _exit_hud_mode() -> void:
	_close_radial()
	if not String(_active_remote_screen.get("id", "")).empty():
		var client = _client()
		if client != null:
			client.send_ui_directive("screen_select", {"id": ""})

# La ultima pantalla: la fijada, y si no la que el slot A eligio por relevancia. Sin
# ninguna, a elegir en el dial (igual que _open_last del modo HUD).
func _open_last_screen() -> void:
	var target: String = _local_pinned_screen_id
	if target.empty() or _screen_list_field(target, "id").empty():
		target = _slot_a_id
	if target.empty():
		_open_radial()
		return
	var client = _client()
	if client != null:
		client.send_ui_directive("screen_select", {"id": target})

func _open_radial() -> void:
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
	# Mientras se elige no se ve lo de atras (el Dim tapa el fondo, y los slots y la vista
	# se esconden): asi funciona el dial del modo HUD del juego.
	if widget_host != null:
		widget_host.visible = false
	if fullscreen_overlay != null:
		fullscreen_overlay.visible = false
	_radial_selector.open()

func _radial_is_open() -> bool:
	return is_instance_valid(_radial_selector) and _radial_selector.is_open()

func _close_radial() -> void:
	_radial_touch_index = -1
	_radial_aim = Vector2.ZERO
	if is_instance_valid(_radial_selector):
		_radial_selector.close()
	if widget_host != null:
		widget_host.visible = true
	# La vista vuelve solo si hay una pantalla abierta.
	if fullscreen_overlay != null:
		fullscreen_overlay.visible = not String(_active_remote_screen.get("id", "")).empty()
		_focus_widget_view()

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
	var ids: Array = []
	for item in _screen_list:
		if typeof(item) == TYPE_DICTIONARY and not String(item.get("id", "")).empty():
			ids.append(String(item["id"]))
	return ids

func _update_radial_options() -> void:
	if not is_instance_valid(_radial_selector):
		return
	var labels: Array = []
	for sid in _radial_screen_ids():
		var title: String = _screen_list_field(sid, "title")
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
	_close_radial()
	var client = _client()
	if client == null:
		return

	var ids: Array = _radial_screen_ids()
	if index < 0 or index >= ids.size():
		return
	var sid: String = ids[index]
	client.send_ui_directive("screen_select", {"id": sid})
	# Confirmar fija la pantalla, como en el modo HUD: es la que reabre un tap.
	pin_local_screen(sid)

func _on_radial_cancelled() -> void:
	_close_radial()

# Un widget montado aca pide ejecutar una accion: la pantalla vive en el host, asi que
# viaja por el canal (el bridge la resuelve contra su SuitOS). Lo llama HudWidgetAction.
func perform_hud_widget_action(screen_id: String, op: String, args: Dictionary = {}) -> void:
	if screen_id.empty():
		return
	send_remote_action(screen_id, op, args)

# --- Slot Evaluation & Widget Host ---

func pin_local_screen(id: String) -> void:
	_local_pinned_screen_id = id
	_reevaluate_slots()
	_update_radial_options()

func _reevaluate_slots() -> void:
	if widget_host == null:
		return

	var best_a_id: String = ""
	var max_rel: float = 0.0

	for item in _screen_list:
		if typeof(item) == TYPE_DICTIONARY:
			var sid: String = String(item.get("id", ""))
			# Misma regla que SuitOS en el host: el slot A nunca repite al B, asi que la
			# pantalla fijada no compite por el A.
			if sid == _local_pinned_screen_id:
				continue
			var rel: float = float(item.get("relevance", 0.0))
			if rel > max_rel:
				max_rel = rel
				best_a_id = sid

	_slot_a_id = best_a_id
	_mount_slot_widget("slot_a", best_a_id)
	_mount_slot_widget("slot_b", _local_pinned_screen_id)

func _mount_slot_widget(slot: String, screen_id: String) -> void:
	if screen_id.empty():
		_remove_slot_widget(slot)
		return

	var snap: Dictionary = _snapshots_cache.get(screen_id, {})
	if snap.empty():
		var title: String = _screen_list_field(screen_id, "title")
		snap = {
			"proto": 1,
			"id": screen_id,
			"title": title if not title.empty() else screen_id,
			"source": "online"
		}

	var existing = _mounted_widgets.get(slot, null)
	if is_instance_valid(existing) and _get_node_screen_id(existing) == screen_id:
		_hydrate_node(existing, snap)
		return

	_remove_slot_widget(slot)

	var widget_scene: PackedScene = _resolve_widget_scene(screen_id)
	var node: Control = null

	if widget_scene != null:
		node = widget_scene.instance() as Control
	else:
		node = PanelContainer.new()
		var label = Label.new()
		label.name = "TitleLabel"
		node.add_child(label)

	if node != null:
		_set_node_screen_id(node, screen_id)
		node.name = "Widget_" + slot
		widget_host.add_child(node)
		_mounted_widgets[slot] = node
		_place_slot_widget(node, slot)
		_hydrate_node(node, snap)

# Misma geometria que el host: fila fija por slot, arriba a la izquierda, nunca invadiendo
# la fila vecina, con la escala compensada por render_scale (UIScaleCompensator).
func _place_slot_widget(node: Control, slot: String) -> void:
	var row: int = SLOT_ROWS.find(slot)
	if row < 0 or not is_instance_valid(node) or not (node is Control):
		return
	var control: Control = node as Control
	var k: float = UIScaleCompensator.scale_for(self)
	var height: float = max(control.get_combined_minimum_size().y, 1.0)
	var fit: float = min(1.0, SLOT_ROW_HEIGHT / height)
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# WidgetHost ya esta compensado (WidgetHostScale): aca todo va en unidades nominales, sin k.
	control.rect_scale = Vector2.ONE * fit
	# Pegado al borde izquierdo, arriba, a cualquier render_scale. Sin las margenes de la UI
	# tactil a proposito: esa se dibuja encima y el joystick esta abajo.
	var inset: Vector2 = _safe_area_inset_nominal()
	control.rect_position = Vector2(SLOT_PADDING + inset.x,
		SLOT_PADDING + inset.y + row * (SLOT_ROW_HEIGHT + SLOT_GAP))
	_make_widget_tappable(control, slot)

# El recorte de la pantalla (camara en el borde), llevado a las unidades nominales del
# WidgetHost: la safe area viene en pixeles de ventana y el HUD vive en el viewport escalado.
func _safe_area_inset_nominal() -> Vector2:
	var window: Vector2 = OS.window_size
	if window.x <= 0.0 or window.y <= 0.0:
		return Vector2.ZERO
	var safe: Rect2 = OS.get_window_safe_area()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var nominal: Vector2 = viewport_size / UIScaleCompensator.scale_for(self)
	return Vector2(safe.position.x * nominal.x / window.x, safe.position.y * nominal.y / window.y)

# Mientras esta pantalla esta abierta, el Container de pantalla completa de la UI tactil
# no se queda con el toque de GUI (sus controles lo leen en _input y siguen andando). Solo
# aca: en gameplay ese STOP evita que los clics que Android emula de cada toque lleguen a
# SessionManager._unhandled_input, que recaptura el mouse.
var _touch_ui_filter_before: int = -1

func _let_touches_through_touch_ui(through: bool) -> void:
	var mobile_ui = get_node_or_null("/root/MobileUIManager")
	var touch_ui = mobile_ui.get("_mobile_ui") if mobile_ui != null else null
	var container: Control = touch_ui.get_node_or_null("Container") as Control if is_instance_valid(touch_ui) else null
	if container == null:
		return
	if through:
		if _touch_ui_filter_before < 0:
			_touch_ui_filter_before = container.mouse_filter
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif _touch_ui_filter_before >= 0:
		container.mouse_filter = _touch_ui_filter_before
		_touch_ui_filter_before = -1

func _exit_tree() -> void:
	_let_touches_through_touch_ui(false)
	# Al volver al menu no queda colgado el hint de la partida del otro dispositivo.
	var hints = get_node_or_null("/root/PlayerHintManager")
	if hints != null and hints.has_method("show_remote_hint"):
		hints.show_remote_hint("")

func _relayout_widgets() -> void:
	for slot in SLOT_ROWS:
		var widget = _mounted_widgets.get(slot, null)
		if is_instance_valid(widget):
			_place_slot_widget(widget, slot)

# El cuerpo del widget es el boton (tap = su pantalla, hold = dial), como en el host.
# Diferencia deliberada: los botones internos (toggle de la linterna) conservan su
# entrada, porque aca son utiles: en el host el widget entero abre el modo HUD y sus
# hijos se apagan; en el control remoto el toggle viaja por el canal y funciona.
func _make_widget_tappable(control: Control, slot: String) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	_silence_display_children(control)
	if not control.is_connected("gui_input", self, "_on_widget_gui_input"):
		control.connect("gui_input", self, "_on_widget_gui_input", [control, slot])

func _silence_display_children(node: Node) -> void:
	for child in node.get_children():
		if child is BaseButton:
			continue
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_silence_display_children(child)

func _on_widget_gui_input(event: InputEvent, control: Control, slot: String) -> void:
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == BUTTON_LEFT:
		pressed = (event as InputEventMouseButton).pressed
	else:
		return
	# Un toque que empieza sobre un boton del widget (el toggle de la linterna) es del boton: no abre
	# la pantalla ni el dial. La GUI de Godot 3 corta la propagacion en un control STOP solo para
	# eventos de MOUSE: un InputEventScreenTouch sobre el boton sigue subiendo hasta el widget.
	if pressed:
		_widget_press_on_button = _pointer_on_widget_button(control)
	if _widget_press_on_button:
		if not pressed:
			_widget_press_on_button = false
		return
	control.accept_event() # que el toque no arrastre tambien la camara
	if pressed:
		_widget_press_msec = OS.get_ticks_msec()
		return
	if OS.get_ticks_msec() - _widget_press_msec >= WIDGET_HOLD_MSEC:
		_open_radial()
		return
	var sid: String = _get_node_screen_id(control)
	if sid.empty():
		return
	var client = _client()
	if client != null:
		client.send_ui_directive("screen_select", {"id": sid})
		# Confirmar en el widget fija la pantalla, como la eleccion en el dial.
		pin_local_screen(sid)

func _pointer_on_widget_button(control: Control) -> bool:
	return HudWidgetActionScript.pointer_on_button(control, _last_pointer_position)

func _remove_slot_widget(slot: String) -> void:
	if _mounted_widgets.has(slot):
		var old = _mounted_widgets[slot]
		if is_instance_valid(old):
			old.queue_free()
		_mounted_widgets.erase(slot)

func _resolve_widget_scene(screen_id: String) -> PackedScene:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null and suit_os.has_screen(screen_id):
		var screen = suit_os.get_screen(screen_id)
		if is_instance_valid(screen) and screen.has_method("widget_scene"):
			var scene = screen.widget_scene()
			if scene != null:
				return scene

	# Lo habitual en el control: la pantalla vive en el host y su widget llega como ruta.
	var widget_path: String = _screen_list_field(screen_id, "widget")
	if not widget_path.empty() and ResourceLoader.exists(widget_path):
		var remote_scene = load(widget_path)
		if remote_scene is PackedScene:
			return remote_scene

	if screen_id.begins_with("holoterminal:"):
		return HoloTerminalWidgetScene

	return null

func _screen_list_field(screen_id: String, key: String) -> String:
	for item in _screen_list:
		if typeof(item) == TYPE_DICTIONARY and String((item as Dictionary).get("id", "")) == screen_id:
			return String((item as Dictionary).get(key, ""))
	return ""

func _resolve_view_scene(screen_id: String) -> PackedScene:
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os != null and suit_os.has_screen(screen_id):
		var screen = suit_os.get_screen(screen_id)
		if is_instance_valid(screen) and screen.has_method("view_scene"):
			var scene = screen.view_scene()
			if scene != null:
				return scene

	# Lo habitual en el control: la pantalla completa vive en el host y llega como ruta
	# (solo la de la pantalla activa). Sin escena, la que presta su Viewport en vivo: eso
	# no se puede replicar aca y queda el widget.
	if String(_active_remote_screen.get("id", "")) == screen_id:
		var view_path: String = String(_active_remote_screen.get("view_scene", ""))
		if not view_path.empty() and ResourceLoader.exists(view_path):
			var remote_view = load(view_path)
			if remote_view is PackedScene:
				return remote_view

	return null

func _active_view_design_size() -> Vector2:
	var size = _active_remote_screen.get("view_size")
	if typeof(size) == TYPE_ARRAY and (size as Array).size() >= 2:
		return Vector2(float(size[0]), float(size[1]))
	return Vector2.ZERO

# La vista se ve igual que en el host solo si se arma igual: el host la renderiza en un
# Viewport a su resolucion de diseño (1280x816 en el HangingDisplay) y muestra esa
# textura. Escalar el Control directo lo remuestrea contra el stretch del proyecto y ni
# las fuentes ni los paneles quedan iguales. Aca se escala la TEXTURA, no el layout.
func _fit_view_node() -> void:
	var container = _view_viewport_container()
	if container == null:
		_fit_widget_placeholder()
		return
	var design: Vector2 = _active_view_design_size()
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

	var sid: String = String(_active_remote_screen.get("id", ""))
	if sid.empty():
		fullscreen_overlay.visible = false
		_free_fullscreen_view()
		return

	# Si el dial esta abierto la vista se monta pero no se muestra: la tapa el dial hasta
	# que se termine de elegir (_close_radial la devuelve).
	fullscreen_overlay.visible = not _radial_is_open()
	var snap: Dictionary = _active_remote_screen.get("snapshot", {})
	if snap.empty():
		snap = _snapshots_cache.get(sid, {})

	if is_instance_valid(_fullscreen_view_node) and _get_node_screen_id(_fullscreen_view_node) == sid:
		_hydrate_node(_fullscreen_view_node, snap)
		return

	_free_fullscreen_view()

	var view_scene: PackedScene = _resolve_view_scene(sid)
	if view_scene == null:
		view_scene = _resolve_widget_scene(sid)

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
		var design: Vector2 = _active_view_design_size()
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
