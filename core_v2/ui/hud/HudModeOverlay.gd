extends Control

# HudModeOverlay.gd - Modo HUD local de OdiseaOS (FD-296 F3, spec 4).
# Lo monta SuitOS.open_hud_mode() en OverlayUIManager (SLOT_MODAL) con el mundo pausado por
# PauseManager.pause_hud_mode(), asi que corre en PAUSE_MODE_PROCESS.
#
# TAB (o el boton tactil del HUD): desde el juego, tap abre el radial; con una pantalla abierta, tap
# vuelve al jugador; con el radial ya abierto, un tap confirma lo marcado o lo cierra si no hay nada.
# Hold abre el radial tambien sobre una pantalla (para cambiarla), como cuasimodo: soltar elige lo
# marcado. Elegir abre la pantalla sin fijarla: nada se autoasigna a un slot.
# Teclas 1-4 (hud_slot): tap abre la pantalla de ese slot (o la cierra; vacio = radial) y hold
# abre el radial que fija lo elegido EN ese slot. Con una sola pantalla no hay radial.
# El radial se apunta con un vector acumulado con zona muerta: soltar en el centro no elige nada. Tap/hold, gesto y click salen de InputDataV2
# (patron ElevatorFloorSelector): con el mundo pausado el proveedor del jugador no avanza, asi
# que el overlay avanza uno propio, una muestra por tick y con la normalizacion del replay.

const Gesture = preload("res://core_v2/ui/hud/HudTabGesture.gd")
const ViewMount = preload("res://core_v2/ui/hud/HudViewMount.gd")
const VirtualMouse = preload("res://core_v2/ui/VirtualMouse.gd")
const HudWidgetActionScript = preload("res://core_v2/ui/hud/HudWidgetAction.gd")
const HudSlots = preload("res://core_v2/ui/hud/HudSlots.gd")
const UIScaleCompensator = preload("res://core_v2/ui/UIScaleCompensator.gd")
const Haptics = preload("res://core_v2/ui/Haptics.gd")
const EyeOpen = preload("res://core_v2/ui/remote_control/eye_open.svg")
const EyeClosed = preload("res://core_v2/ui/remote_control/eye_closed.svg")
# Mismos umbrales que ElevatorFloorSelector: se filtra ruido de angulo, no movimiento.
const MOVE_GESTURE_DEADZONE_SQ := 0.02
const MOUSE_GESTURE_DEADZONE := 3.0
const TOUCH_MIN_DRAG := 12.0
# Punteria del dial, en pixeles del dial: el mouse suma hasta este radio, el stick lo recorre en
# vivo y el dedo lo arrastra. Dentro de AIM_DEAD_ZONE no se marca nada.
const AIM_RADIUS := 120.0
const AIM_DEAD_ZONE := 40.0
# Mantener un item del radial y mover el dedo lo levanta para soltarlo sobre un slot (lo fija ahi).
# Mismo umbral que el hold de TAB y del widget.
const DRAG_HOLD_MSEC := 400
# Godot marca asi el mouse que emula a partir del touch (InputEvent.DEVICE_ID_TOUCH_MOUSE).
const TOUCH_MOUSE_DEVICE := -1
# Asa de la pantalla abierta: arrastrarla hasta un slot la ancla ahi. Pixeles nominales.
const HANDLE_SIZE := Vector2(64, 22)
const HANDLE_GAP := 8.0
const CAMERA_FOCUS_SIZE := Vector2(56, 38)
const DrawerScript = preload("res://core_v2/ui/hud/SuitOSDrawer.gd")
# Botones de cara, tal como ya viajan en el stream (FD-304 §4): A = crouch, B = jump, X = interact,
# Y = hud_mode. No se agrega ninguna accion nueva al mapa de entrada: la pantalla declara sus
# operaciones con hud_gamepad_actions() y el overlay las despacha por HudWidgetAction.
const FACE_FIELDS := {"a": "crouch", "b": "jump", "x": "interact"}
# Paso de la cruceta por el arco: mismo umbral que el hold, para no inventar un tercer tempo.
const NAV_REPEAT_MSEC := 400
const NAV_RATE_MSEC := 110
# Leyenda de los botones de cara: se va sola y vuelve con el primer input (patron de las leyendas
# de interaccion). Solo con mando: no ensucia el HUD de quien juega con teclado.
const LEGEND_VISIBLE_MSEC := 3000
const LEGEND_PILL := Vector2(132, 26)
# Cuanto recorre el cursor del arrastre por tick con el stick a fondo, en pixeles del viewport.
const STICK_DRAG_SPEED := 14.0

var input_provider = null # InputProviderV2; LIVE salvo que un test inyecte uno en REPLAY
# De donde salen las pantallas y los slots: SuitOS en el juego; RemoteHudBackend en el control
# remoto, que lo monta sin pausa (el mundo sigue en el host). Se asigna antes de add_child.
var backend: Node = null
# En el juego el mouse virtual usa la pantalla abierta. En el control remoto no: en un handheld se
# activaba con el stick y convertia A/B en clics locales que nunca llegaban al host.
var use_virtual_mouse: bool = true
# Con el mundo pausado el stick, el mouse y el gatillo quedan libres para el dial y el widget
# ampliado. En un telefono no: el joystick y los botones virtuales siguen manejando al host.
var drives_dial_with_gameplay_input: bool = true

var _selector: Control = null
var _view_host: Control = null
var _placeholder: Label = null
var _virtual_mouse: Control = null
var _screen_ids: Array = []
var _gesture = Gesture.new()
var _mount = ViewMount.new()
# Ya se decidio la pulsacion que abrio el modo HUD: desde ahi, un tap cierra.
var _opened: bool = false
var _mouse_aim_active: bool = false
var _confirm_was_down: bool = true # sostenido al abrir: ese boton no confirma
var _touch_index: int = -1
var _touch_start: Vector2 = Vector2.ZERO
var _touch_press_msec: int = 0
var _drag_option: int = -1 # el item del radial bajo el dedo al apoyarlo
var _drag_ghost: Label = null # el item levantado, siguiendo al dedo
var _mouse_drag_pending: bool = false
var _mouse_drag_position: Vector2 = Vector2.ZERO
var _mouse_drag_moved: bool = false
var _restore_mouse_capture_after_drag: bool = false
# Arrastre del widget ampliado (pantalla que es solo widget) hasta un slot.
var _view_drag_candidate: bool = false
var _view_handle: Control = null
var _camera_focus_button: Button = null
var _drag_from_handle: bool = false
# El toque cayo sobre un widget de slot con el dial a la vista: es del widget (tocarlo o arrastrarlo,
# SuitOSWidgetHost), no del dial.
var _touch_on_widget: bool = false
var _dragging_view: bool = false
var _active_focused_screen: Object = null
# El dial abierto por mantener TAB: mientras siga apretado es un cuasimodo (ver _release_tab_hold).
var _tab_hold_active: bool = false
# Clic del widget en modo pantalla: ya estaba apretado al mostrarse (el confirm del dial o el
# tap que lo abrio no lo oprime).
var _widget_click_was_down: bool = true
var _picked_during_hold: bool = false
var _pending_focus_screen: Object = null
var _pending_focus_camera: Camera = null
var _pending_swap_screen: Object = null
# Slot que abrio el radial (tecla o widget): lo elegido se fija ahi. -1 = lo abrio TAB.
var _target_slot: int = -1
var _aim: Vector2 = Vector2.ZERO
var _stick_aiming: bool = false
# Tap/hold de las teclas de slot, del stream igual que TAB. Una sola pulsacion a la vez.
var _slot_gesture = Gesture.new()
var _key_slot: int = -1
var _key_slot_down: bool = false
# La pulsacion de tecla en curso ya abrio su pantalla al oprimir (solo widget, sin vista diegetica):
# su tap no la cierra, y un hold soltado sin elegir sale en vez de volver a ella.
var _opened_on_press: bool = false
# Lo que muestra el arco: los favoritos ordenados por relevancia (FD-305 §2, FD-306 §2). El
# registry completo (_screen_ids) es lo que muestra el drawer.
var _dial_ids: Array = []
# Lo que se esta arrastrando, por id y no por indice: el asa de una pantalla abierta puede
# arrastrar algo que no esta en el arco.
var _drag_id: String = ""
var _drawer: Control = null
# Flancos de los botones de cara. Arrancan en true: el boton que abrio el modo HUD no acciona.
var _face_was_down := {"a": true, "b": true, "x": true}
var _nav_dir: int = 0
var _nav_msec: int = 0
# Relleno del marco del slot mientras se mantiene su hombro (FD-304 §3.1): el hold no puede ser
# invisible. Es solo dibujo, no lee input, y por eso no entra al replay.
var _hold_gauge: Control = null
var _hold_slot: int = -1
var _hold_progress: float = 0.0
var _legend: Control = null
var _legend_actions: Array = []
var _legend_msec: int = -100000
# Cursor virtual del arrastre con stick: arranca en el centro del slot y el stick lo desplaza.
var _stick_cursor: Vector2 = Vector2.ZERO
# Arrastre de una fila del drawer hacia un slot (FD-305 §3.5). Con mouse/dedo la fila se levanta
# al superar el umbral; con un hombro sostenido se levanta la fila enfocada y la lleva el stick.
var _drawer_press_row: int = -1
var _drawer_press_star: bool = false
var _drawer_drag_row: int = -1
var _drawer_drag_active: bool = false

func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	if use_virtual_mouse:
		_virtual_mouse = VirtualMouse.attach_to(self)
	_selector = get_node("RadialSelector")
	# FD-306 §1: el centro ya no es un agujero sino el hub ("..." -> el drawer), con su propio radio.
	# Por eso no se le pone dead_zone: apuntar al medio marca el hub, y SOLTAR ahi cierra sin elegir,
	# que es la misma red de seguridad que daba la zona muerta.
	_selector.hub_enabled = true
	_selector.animate_transitions = true
	# Sin su sector del anillo el texto de cada opcion flota sobre la escena y no se lee como opcion.
	_selector.draw_option_slices = true
	_view_host = get_node("ViewHost")
	_placeholder = get_node("Placeholder")
	_view_handle = Control.new()
	_view_handle.name = "ViewHandle"
	_view_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE # el toque se resuelve en _input
	_view_handle.visible = false
	add_child(_view_handle)
	_view_handle.connect("draw", self, "_draw_view_handle")
	_camera_focus_button = Button.new()
	_camera_focus_button.name = "CameraFocus"
	_camera_focus_button.hint_tooltip = "Enfocar cámara del piloto"
	_camera_focus_button.toggle_mode = true
	_camera_focus_button.expand_icon = true
	_camera_focus_button.icon = EyeOpen
	_camera_focus_button.rect_min_size = CAMERA_FOCUS_SIZE
	_camera_focus_button.visible = false
	_camera_focus_button.connect("pressed", self, "_on_camera_focus_pressed")
	add_child(_camera_focus_button)
	add_to_group("touch_camera_blocker")
	if input_provider == null:
		input_provider = InputProviderV2.new()
	# En el modo HUD el D-pad es de la UI (ui_*): que no apunte el dial como si fuera la camara.
	input_provider.digital_camera_enabled = false
	_selector.connect("option_selected", self, "_select")
	_selector.connect("cancelled", self, "_exit")
	_hold_gauge = Control.new()
	_hold_gauge.name = "HoldGauge"
	_hold_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hold_gauge.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(_hold_gauge)
	_hold_gauge.connect("draw", self, "_draw_hold_gauge")
	_legend = Control.new()
	_legend.name = "GamepadLegend"
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	add_child(_legend)
	_legend.connect("draw", self, "_draw_legend")
	var suit_os: Node = _suit_os()
	_mount.view_2d = suit_os.get("presents_views_in_2d") == true
	# FD-306 §5: el overlay leia el registry una sola vez. Con el drawer eso pasa a ser un bug real,
	# asi que se escucha el alta y la baja de pantallas y la lista se rehace conservando el foco.
	for sig in ["screen_registered", "screen_unregistered"]:
		if suit_os.has_signal(sig) and not suit_os.is_connected(sig, self, "_refresh_screens"):
			suit_os.connect(sig, self, "_refresh_screens")
	_refresh_screens()
	# El TAB que abrio el modo HUD sigue apretado: tap o hold se decide con las muestras.
	_gesture.begin_held()
	# Con el mundo pausado detras, el widget en modo pantalla se dibuja a resolucion completa
	# (a render_scale < 1 su texto salia pixelado). Ver SettingsManager.hold_full_resolution_ui.
	var settings = get_node_or_null("/root/SettingsManager")
	if settings and settings.has_method("hold_full_resolution_ui"):
		settings.hold_full_resolution_ui(self, true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cleanup_focus()

func _exit_tree() -> void:
	_end_option_drag()
	_cleanup_focus()
	_mount.close()
	var suit_os: Node = _suit_os()
	if is_instance_valid(suit_os):
		for sig in ["screen_registered", "screen_unregistered"]:
			if suit_os.has_signal(sig) and suit_os.is_connected(sig, self, "_refresh_screens"):
				suit_os.disconnect(sig, self, "_refresh_screens")
	var settings = get_node_or_null("/root/SettingsManager")
	if settings and settings.has_method("hold_full_resolution_ui"):
		settings.hold_full_resolution_ui(self, false)

# Entrada directa al radial (hold sobre el widget del slot, que no pasa por el stream).
func show_radial(slot: int = -1) -> void:
	_gesture.consume()
	_opened = true
	_open_radial(slot)

# Lo abrio la tecla de un slot: esa tecla sigue apretada y tap/hold se decide con sus muestras.
func show_for_slot(slot: int) -> void:
	_gesture.consume()
	_key_slot = slot
	_key_slot_down = true
	_slot_gesture.begin_held()
	_open_on_press(slot)

# Entrada directa a una pantalla (tap sobre el widget de su slot).
func show_screen_id(id: String) -> void:
	_gesture.consume()
	_opened = true
	_show_screen(id)

func _physics_process(_delta: float) -> void:
	_mount_focused_screen_if_ready()
	_update_view_handle()
	_update_camera_focus_button()
	var input = _frame_input()
	if input == null:
		return
	var gesture: int = _gesture.feed(bool(input.hud_mode))
	if _drawer_open():
		# El drawer es una vista: Y sale del modo HUD (no vuelve al dial), como dice FD-305 §3.5.
		if gesture == Gesture.TAP:
			_exit()
			return
		_drive_drawer(input, _delta)
		_update_hold_feedback()
		return
	if gesture == Gesture.TAP:
		if _screen_ids.empty():
			# Sin pantallas no hay dial: el tap que abrio muestra "SIN PANTALLAS", el siguiente sale.
			if _opened:
				_exit()
				return
			_opened = true
		elif _selector.is_open():
			_opened = true
			_dismiss_radial()
			if not is_inside_tree() or is_queued_for_deletion():
				return
		elif _mount.is_showing() or is_instance_valid(_active_focused_screen):
			# Desde una pantalla, el boton del HUD vuelve al jugador. Para cambiar de pantalla, hold.
			_exit()
			return
		else:
			_opened = true
			_open_radial()
	elif gesture == Gesture.HOLD and not _selector.is_open():
		_begin_hold_radial(-1)
	var slot_was_down: bool = _key_slot_down
	var slot_gesture: int = _feed_slot_gesture(int(input.hud_slot) - 1)
	if _key_slot_down and not slot_was_down:
		_open_on_press(_key_slot)
	if slot_gesture == Gesture.TAP:
		if _opened_on_press:
			_opened_on_press = false # el release de la pulsacion que la abrio
		elif _tap_slot(_key_slot):
			return
	elif slot_gesture == Gesture.HOLD and not _selector.is_open():
		_begin_hold_radial(_key_slot)
	_aim_with_hud_button(bool(input.hud_mode))
	# Apuntar antes de resolver el release: la ultima muestra con TAB suelto todavia cuenta.
	if drives_dial_with_gameplay_input:
		_drive_from_stream(input)
		_drive_nav(input)
	if (gesture == Gesture.HOLD_RELEASE or slot_gesture == Gesture.HOLD_RELEASE) and _tab_hold_active:
		_release_tab_hold()
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if drives_dial_with_gameplay_input:
		# Si la pantalla abierta declara sus botones de cara, son suyos: la navegacion por foco de
		# la GUI no puede oprimir el mismo boton otra vez en el mismo toque.
		if not _drive_hud_buttons(input):
			_drive_widget_screen(input)
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_update_hold_feedback()

# Una tecla de slot nueva toma el gesto solo si no hay otra sostenida.
func _feed_slot_gesture(pressed_slot: int) -> int:
	if pressed_slot >= 0 and not _key_slot_down:
		_key_slot = pressed_slot
	var down: bool = pressed_slot >= 0 and pressed_slot == _key_slot
	_key_slot_down = down
	return _slot_gesture.feed(down)

# Tap de la tecla de un slot. Devuelve true si salio del modo HUD.
func _tap_slot(slot: int) -> bool:
	var suit_os: Node = _suit_os()
	var id: String = suit_os.slot_screen_id(slot)
	_opened = true
	if not suit_os.has_screen(id):
		# FD-304 §3: un tap no abre un menu. El slot vacio responde con un deny y el radial queda
		# para el hold, que es la accion deliberada.
		_deny_slot(slot)
		return false
	if id == suit_os.get_active_screen_id() and not _selector.is_open():
		_exit()
		return true
	_show_screen(id)
	return false

# Una pantalla que es solo widget se abre al oprimir la tecla, sin esperar a saber si es tap o
# hold: no hay transicion de camara que disimule esa espera. Con vista diegetica sigue al soltar.
func _open_on_press(slot: int) -> void:
	var suit_os: Node = _suit_os()
	var id: String = suit_os.slot_screen_id(slot)
	var screen: Object = suit_os.get_screen(id)
	if screen == null or _selector.is_open() or id == suit_os.get_active_screen_id():
		return
	if screen.has_method("view_scene") and screen.view_scene() != null:
		return
	_opened = true
	_opened_on_press = true
	_show_screen(id)

func _begin_hold_radial(slot: int) -> void:
	_opened = true
	if _opened_on_press:
		# La pulsacion ya habia abierto la pantalla del slot por adelantado (es widget puro y no
		# hay transicion de camara que disimule la espera). Que la pulsacion termine siendo un
		# hold dice que no era eso lo que se queria: se deshace antes de abrir el dial, o el
		# acorde de FD-304 §5 abriria justo la pantalla que promete no abrir.
		_opened_on_press = false
		_cleanup_focus()
		_mount.close()
		_suit_os().close_screen()
	_tab_hold_active = true
	_picked_during_hold = false
	_open_radial(slot)

# La muestra del tick: get_input() una vez por tick (el proveedor del jugador esta pausado).
func _frame_input():
	return input_provider.get_input()

# El boton tactil del HUD es un joystick: arrastrar el dedo desde donde se apoyo apunta el dial,
# y soltarlo suelta TAB (elige lo marcado, _release_tab_hold). Si arrastra antes del umbral del
# hold el dial se abre ya: un arrastre nunca es un tap. Sin boton o sin dedo, drag es cero.
func _aim_with_hud_button(tab_down: bool) -> void:
	var mobile: Node = get_node_or_null("/root/MobileUIManager")
	var drag: Vector2 = mobile.hud_button_drag() if mobile != null and mobile.has_method("hud_button_drag") \
		else Vector2.ZERO
	if drag.length() < TOUCH_MIN_DRAG:
		return
	if tab_down and not _selector.is_open() and not _tab_hold_active:
		_gesture.promote_to_hold()
		_begin_hold_radial(-1)
	if _selector.is_open():
		_point_at(drag)

func _drive_from_stream(input) -> void:
	if not _selector.is_open():
		return
	# mouse_delta viene con Y invertida (arriba es +Y); en pantalla arriba es -Y.
	var gesture: Vector2 = Vector2(input.mouse_delta.x, -input.mouse_delta.y)
	var move: Vector2 = Vector2(input.move_vec.x, input.move_vec.y)
	if _touch_index < 0 and gesture != Vector2.ZERO:
		# El mouse suma: volver hacia el centro es volver a la zona muerta.
		_point_at(_aim + gesture)
		if gesture.length() >= MOUSE_GESTURE_DEADZONE:
			_mouse_aim_active = true
	# Hold de un hombro sobre un slot QUE YA TIENE pantalla: el stick no apunta el dial, levanta el
	# widget y lo arrastra (FD-304 §6). Para cambiarle la pantalla a ese slot esta la cruceta, que
	# recorre el arco (§7.2); el stick solo apunta el dial cuando el slot esta vacio y no hay nada
	# que arrastrar. Asi el mismo hold hace las dos cosas sin que se pisen.
	if _stick_drag_armed():
		_drive_stick_drag(move, input)
		_confirm_was_down = bool(input.tool_fire_primary)
		return
	if move.length_squared() > MOVE_GESTURE_DEADZONE_SQ \
			and (input.analog_move_active or not _mouse_aim_active):
		# WASD solo mientras no se movio el mouse (ElevatorFloorSelector). El stick es en vivo.
		_stick_aiming = bool(input.analog_move_active)
		_point_at(move.limit_length(1.0) * AIM_RADIUS)
	elif _stick_aiming:
		_stick_aiming = false
		_point_at(Vector2.ZERO) # stick soltado: al centro, nada marcado
	var down: bool = bool(input.tool_fire_primary)
	# El clic del mouse tambien aparece en el stream como tool_fire_primary. Mientras su release
	# decide click corto o drag, no puede confirmar el dial por adelantado.
	if not _mouse_drag_pending and down and not _confirm_was_down:
		_confirm_or_dismiss()
	_confirm_was_down = down

func _input(event: InputEvent) -> void:
	if _drawer_open() and (event is InputEventMouseMotion or event is InputEventMouseButton \
			or event is InputEventScreenTouch or event is InputEventScreenDrag):
		# El drawer se usa con el dedo, el mouse y el mando. No marca el evento como atendido: el
		# cursor virtual compartido necesita ver el mismo mouse para seguir al puntero.
		_drawer_pointer_input(event)
		return
	if use_virtual_mouse and event is InputEventMouseButton and event.button_index == BUTTON_RIGHT:
		if event.pressed and is_instance_valid(_virtual_mouse):
			_set_virtual_mouse_enabled(true)
			_virtual_mouse.set_desktop_mouse_mode(true, event.position)
		get_tree().set_input_as_handled()
		return
	if is_instance_valid(_active_focused_screen) and _active_focused_screen.has_method("forward_view_input"):
		if event is InputEventKey and not event.is_action_pressed("ui_cancel"):
			_active_focused_screen.forward_view_input(event)
			get_tree().set_input_as_handled()
			return
		if event is InputEventMouseMotion or event is InputEventMouseButton:
			_active_focused_screen.forward_view_input(event)
			get_tree().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		if _mouse_drag_pending and _drag_option >= 0:
			var drag_position: Vector2 = _update_mouse_drag_position(event)
			if _drive_option_drag(drag_position, false):
				_mouse_drag_moved = _mouse_drag_moved \
					or (drag_position - _touch_start).length() >= TOUCH_MIN_DRAG
			get_tree().set_input_as_handled()
			return
		# Lo que hace PlayerControllerV2._input, que ahora esta pausado.
		if _touch_index >= 0 or not drives_dial_with_gameplay_input:
			return # es un dedo: ya apunta el radial por InputEventScreenDrag, mas abajo
		if input_provider != null and "mouse_delta_accum" in input_provider:
			input_provider.mouse_delta_accum += event.relative
		return
	if event is InputEventScreenTouch:
		# Un dedo sobre el joystick o un boton virtual es de ellos: se sigue caminando con el dial
		# abierto (en el control remoto; en el juego estan ocultos o no sirven en pausa).
		if event.pressed and _touch_index < 0 and not _on_touch_controls(event.position):
			_touch_index = event.index
			_touch_start = event.position
			_touch_press_msec = OS.get_ticks_msec()
			var host = _widget_host()
			_touch_on_widget = _selector.is_open() and host != null and host.forward_touch(event)
			if _touch_on_widget:
				get_tree().set_input_as_handled()
				return
			_drag_option = _selector.slice_at(event.position)
			_drag_id = _dial_id_at(_drag_option)
			_drag_from_handle = is_on_view_handle(event.position)
			if _drag_from_handle:
				_drag_id = _suit_os().get_active_screen_id()
				_drag_option = _dial_ids.find(_drag_id)
			_view_drag_candidate = _widget_screen_showing() and not _drag_from_handle \
				and _view_screen_rect().has_point(event.position) \
				and not HudWidgetActionScript.pointer_on_button(_mount.get_widget(), event.position)
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			var tapped: bool = (event.position - _touch_start).length() < TOUCH_MIN_DRAG
			if _touch_on_widget:
				_touch_on_widget = false # lo resuelve el widget (su pantalla, su boton, o el arrastre)
				var host = _widget_host()
				if host != null:
					host.forward_touch(event)
				get_tree().set_input_as_handled()
			elif is_instance_valid(_drag_ghost):
				_drop_option(event.position)
				get_tree().set_input_as_handled()
			elif _dragging_view:
				_drop_view(event.position)
				get_tree().set_input_as_handled()
			elif _drag_from_handle:
				_drag_from_handle = false # un toque al asa sin arrastrar no hace nada (ni cierra)
				get_tree().set_input_as_handled()
			elif _selector.is_open() \
					and _selector.slice_at(_touch_start) == RadialSelectorV2.HUB_INDEX \
					and _selector.slice_at(event.position) == RadialSelectorV2.HUB_INDEX:
				# Dedo que empezo y solto en el "..." pero se corrio mas que el umbral del tap:
				# sigue siendo el hub, que no es una opcion. Sin esto el drift lo dejaba en nada.
				Haptics.confirm()
				_select(RadialSelectorV2.HUB_INDEX)
				get_tree().set_input_as_handled()
			elif tapped and _selector.is_open():
				# Como en el ascensor: tocar un sector elige ese sector; tocar en cualquier otro lado
				# con una opcion marcada (apuntada con el boton del HUD o arrastrando) la oprime, y
				# sin nada marcado cierra el dial.
				var picked: int = _selector.slice_at(event.position)
				if picked != RadialSelectorV2.NONE:
					Haptics.confirm() # el toque directo no pasa por confirm(), que es el que vibra
					_select(picked)
				elif _selector.has_selection():
					_selector.confirm()
				else:
					_dismiss_radial()
				get_tree().set_input_as_handled()
			elif tapped and _is_outside_view(event.position):
				_exit()
				get_tree().set_input_as_handled()
		return
	if event is InputEventScreenDrag:
		# Todo el arrastre, no el ultimo delta (criterio de ElevatorFloorSelector).
		if event.index == _touch_index:
			if _touch_on_widget or _drive_option_drag(event.position) or _drive_view_drag(event.position):
				return
			_point_at(event.position - _touch_start)
		return
	# TAB NO se lee aca: tap/hold sale del stream (_physics_process).
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and _selector.is_open():
		# El clic emulado de un toque no decide: el toque se resuelve al soltar (sector o fuera).
		# Por el device y no solo por InputProviderV2.pointer_is_from_touch(): con el arbol pausado
		# MobileUIManager no renueva esa ventana, y el clic del dedo cerraba el dial al apoyarlo.
		if event.device == TOUCH_MOUSE_DEVICE \
				or (Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED and InputProviderV2.pointer_is_from_touch()):
			# Y sigue de largo a la GUI: si el dedo cayo sobre un widget de slot, ese clic es el
			# que lo oprime. Marcarlo como atendido dejaba al widget sin su toque.
			return
		if event.pressed:
			# Igual que touch: el click corto confirma; si se mueve antes de soltar, lleva el
			# item del dial hasta un slot.
			_mouse_drag_pending = true
			# El dial se apunta, no se señala: manda el aim. Con el mouse capturado el click
			# llega warpeado al centro (el hub), y tomar el puntero como verdad pisaba lo
			# apuntado y hacia que soltar descartara en vez de elegir (FD-306 §1). El puntero
			# solo decide cuando no hay nada apuntado (mouse libre sobre el item, o recien abierto).
			_drag_option = _selector.get_hovered_index()
			if _drag_option == RadialSelectorV2.NONE:
				_drag_option = _selector.slice_at(event.position)
			_drag_id = _dial_id_at(_drag_option)
			_mouse_drag_moved = false
			_mouse_drag_position = _selector.option_center(_drag_option)
			_touch_start = _mouse_drag_position
			_touch_press_msec = OS.get_ticks_msec()
			if _drag_option != RadialSelectorV2.NONE:
				_selector.point_at(_mouse_drag_position)
				_start_mouse_option_drag(_mouse_drag_position)
		elif is_instance_valid(_drag_ghost):
			var dragged: bool = _mouse_drag_moved
			_drop_option(event.position)
			if not dragged:
				_confirm_or_dismiss()
		elif _mouse_drag_pending:
			_mouse_drag_pending = false
			# El hub se confirma con un click explicito (FD-306 §1.1): _confirm_or_dismiss lo
			# descartaria, porque soltar con el centro marcado no elige. Solo si el click cayo
			# sobre el hub; un click en cualquier otro lado conserva la ruta de siempre.
			var pressed_hub: bool = _drag_option == RadialSelectorV2.HUB_INDEX
			_drag_option = -1
			if pressed_hub:
				_selector.confirm()
			else:
				_confirm_or_dismiss()
	elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed \
			and _is_outside_view(event.position):
		_exit()
	elif event.is_action_pressed("ui_cancel"):
		_exit()
	elif event.is_action_pressed("ui_accept") and _selector.is_open():
		_selector.confirm()
	elif event.is_action("ui_accept") and _widget_screen_showing():
		pass # el boton lo oprime _drive_widget_screen: la GUI lo oprimiria otra vez
	else:
		return
	get_tree().set_input_as_handled()

# Levanta el item apretado cuando, pasado el hold, el dedo se mueve; desde ahi lo sigue y resalta el
# slot de abajo. El mouse lo levanta al oprimir para que se lea como un drag desde su propia opcion.
func _drive_option_drag(position: Vector2, require_hold: bool = true, allow_stationary: bool = false) -> bool:
	if not is_instance_valid(_drag_ghost):
		if _drag_id.empty() \
				or (not allow_stationary and (position - _touch_start).length() < TOUCH_MIN_DRAG):
			return false
		# Del dial hace falta el hold; el asa ya es para arrastrar; el drawer levanta la fila con
		# el gesto que ya paso su propio umbral (mouse/dedo) o con el hombro sostenido (stick).
		if not _drag_from_handle and not _drawer_open() and (not _selector.is_open() \
				or (require_hold and OS.get_ticks_msec() - _touch_press_msec < DRAG_HOLD_MSEC)):
			return false
		Haptics.pulse(Haptics.LIFT_MSEC)
		_drag_ghost = Label.new()
		_drag_ghost.name = "DragGhost"
		_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drag_ghost.text = _screen_title(_drag_id)
		if _selector.option_font is Font:
			_drag_ghost.add_font_override("font", _selector.option_font)
		_drag_ghost.add_color_override("font_color", _selector.color_fg)
		add_child(_drag_ghost)
	_drag_ghost.rect_position = position - _drag_ghost.get_combined_minimum_size() * 0.5
	var host = _widget_host()
	if host != null:
		host.show_drop_targets(true, host.slot_at(position))
	return true

func _start_mouse_option_drag(position: Vector2) -> void:
	if not _drive_option_drag(position, false, true):
		return
	_restore_mouse_capture_after_drag = Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if _restore_mouse_capture_after_drag:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		get_viewport().warp_mouse(position)

func _update_mouse_drag_position(event: InputEventMouseMotion) -> Vector2:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		_mouse_drag_position = event.position
		return _mouse_drag_position
	_mouse_drag_position += event.relative
	var size: Vector2 = get_viewport_rect().size
	_mouse_drag_position.x = clamp(_mouse_drag_position.x, 0.0, size.x)
	_mouse_drag_position.y = clamp(_mouse_drag_position.y, 0.0, size.y)
	return _mouse_drag_position

# Soltar el item levantado: sobre un slot lo fija ahi; en cualquier otro lado no pasa nada. Desde el
# dial, el dial queda abierto para seguir asignando; desde el asa de una pantalla, anclarla cierra
# el modo HUD para que se vea el widget en su slot.
func _drop_option(position: Vector2) -> void:
	var host = _widget_host()
	var slot: int = host.slot_at(position) if host != null else -1
	var from_handle: bool = _drag_from_handle
	var recycled: bool = host != null and host.recycle_rect().has_point(position)
	if slot >= 0:
		Haptics.pulse(Haptics.DROP_MSEC)
		_suit_os().pin_to_slot(slot, _drag_id)
	elif recycled:
		# Soltar sobre la zona de reciclaje vacia el slot, igual que con el mouse (FD-304 §6).
		Haptics.pulse(Haptics.DROP_MSEC)
		_suit_os().clear_slot(_suit_os().get_pinned_slots().find(_drag_id))
	_end_option_drag()
	if slot >= 0 and from_handle:
		_exit()

func _end_option_drag() -> void:
	if is_instance_valid(_drag_ghost):
		_drag_ghost.queue_free()
	_drag_ghost = null
	_drag_option = -1
	_drag_id = ""
	_mouse_drag_pending = false
	_mouse_drag_position = Vector2.ZERO
	_mouse_drag_moved = false
	_drag_from_handle = false
	if _restore_mouse_capture_after_drag:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_restore_mouse_capture_after_drag = false
	var host = _widget_host()
	if host != null:
		host.show_drop_targets(false)

# El widget ampliado de una pantalla que es solo widget: pasado el hold y con el dedo en movimiento
# se levanta, vuelve al tamaño de slot y sigue al dedo.
func _drive_view_drag(position: Vector2) -> bool:
	var widget: Control = _mount.get_widget()
	if not is_instance_valid(widget):
		return false
	if not _dragging_view:
		if not _view_drag_candidate or OS.get_ticks_msec() - _touch_press_msec < DRAG_HOLD_MSEC \
				or (position - _touch_start).length() < TOUCH_MIN_DRAG:
			return false
		_dragging_view = true
		Haptics.pulse(Haptics.LIFT_MSEC)
		widget.rect_pivot_offset = Vector2.ZERO
		widget.rect_scale = Vector2.ONE * UIScaleCompensator.scale_for(self)
	widget.rect_global_position = position - widget.rect_size * widget.rect_scale * 0.5
	var host = _widget_host()
	if host != null:
		host.show_drop_targets(true, host.slot_at(position))
	return true

# Soltarlo sobre un slot lo fija ahi y cierra el modo HUD: el widget queda en su slot. En cualquier
# otro lado vuelve a la vista ampliada.
func _drop_view(position: Vector2) -> void:
	_dragging_view = false
	_view_drag_candidate = false
	var host = _widget_host()
	var slot: int = host.slot_at(position) if host != null else -1
	if host != null:
		host.show_drop_targets(false)
	var suit_os: Node = _suit_os()
	var id: String = suit_os.get_active_screen_id()
	if slot >= 0 and suit_os.has_screen(id):
		Haptics.pulse(Haptics.DROP_MSEC)
		suit_os.pin_to_slot(slot, id)
		_exit()
	elif suit_os.has_screen(id):
		_show_screen(id)

func _screen_title(id: String) -> String:
	var suit_os: Node = _suit_os()
	var screen: Object = suit_os.get_screen(id)
	if screen != null and screen.has_method("screen_title"):
		return screen.screen_title()
	# Un favorito de otro nivel sigue teniendo nombre: sale del ultimo snapshot conocido.
	if suit_os.has_method("screen_title_of"):
		return String(suit_os.screen_title_of(id))
	return id


func _dial_id_at(index: int) -> String:
	return String(_dial_ids[index]) if index >= 0 and index < _dial_ids.size() else ""


# --- Frescura del registry (FD-306 §5) ---

func _refresh_screens(_id: String = "") -> void:
	var suit_os: Node = _suit_os()
	if not is_instance_valid(suit_os):
		return
	_screen_ids = suit_os.get_registered_screens()
	_placeholder.visible = _screen_ids.empty() and not _selector.is_open() and not _drawer_open()
	if is_instance_valid(_drawer):
		_drawer.set_rows(_drawer_rows())


# --- Drawer (FD-305 §3) ---

func _drawer_open() -> bool:
	return is_instance_valid(_drawer) and _drawer.visible


func _drawer_rows() -> Array:
	var suit_os: Node = _suit_os()
	var rows: Array = []
	var seen := {}
	# Todo el registry, mas los favoritos de otros niveles: un favorito offline se sigue viendo
	# (marcado) para poder quitarlo, en vez de desaparecer al cambiar de escena.
	var ids: Array = _screen_ids.duplicate()
	if suit_os.has_method("get_favorites"):
		for id in suit_os.get_favorites():
			if not ids.has(id):
				ids.append(id)
	for id in ids:
		if seen.has(id):
			continue
		seen[id] = true
		var screen: Object = suit_os.get_screen(id)
		var snapshot: Dictionary = {}
		if screen != null and screen.has_method("widget_snapshot"):
			snapshot = screen.widget_snapshot()
		rows.append({
			"id": id,
			"title": _screen_title(id),
			"source": "online" if screen != null else "offline",
			"favorite": suit_os.has_method("is_favorite") and suit_os.is_favorite(id),
			"alarm": bool(snapshot.get("alarm", false))
		})
	return rows


func _open_drawer() -> void:
	# El unico cierre del dial que no tiene nada que lo tape en el mismo frame: el drawer entra
	# encima mientras el anillo se retrae hacia el centro (FD-304 §8). Cerrar hacia una pantalla
	# tiene que ser sincronico, y salir del modo HUD se lleva el overlay entero.
	_selector.close_animated()
	_placeholder.visible = false
	_view_host.visible = false
	if not is_instance_valid(_drawer):
		_drawer = DrawerScript.new()
		_drawer.name = "SuitOSDrawer"
		add_child(_drawer)
		_drawer.connect("screen_chosen", self, "_on_drawer_chose")
		_drawer.connect("favorite_toggled", self, "_on_drawer_favorited")
	_drawer.visible = true
	_drawer.set_rows(_drawer_rows())
	_end_drawer_row_drag()
	_set_virtual_mouse_enabled(false)
	if is_instance_valid(_virtual_mouse) and _virtual_mouse.has_method("set_gamepad_cursor_enabled"):
		_virtual_mouse.set_gamepad_cursor_enabled(false)


func _close_drawer() -> void:
	if is_instance_valid(_drawer):
		_drawer.visible = false
	_placeholder.visible = _screen_ids.empty()
	_end_drawer_row_drag()
	if is_instance_valid(_drag_ghost):
		_end_option_drag()
	if is_instance_valid(_virtual_mouse) and _virtual_mouse.has_method("set_gamepad_cursor_enabled"):
		_virtual_mouse.set_gamepad_cursor_enabled(true)


func _on_drawer_chose(id: String) -> void:
	_close_drawer()
	if _target_slot >= 0:
		_suit_os().pin_to_slot(_target_slot, id)
	_show_screen(id)


func _on_drawer_favorited(_id: String, _is_favorite: bool) -> void:
	# El arco se rehace la proxima vez que se abra: reordenarlo mientras el drawer esta encima
	# solo serviria para que cambie a espaldas del jugador.
	pass

# --- Asa de la pantalla abierta ---

# Arriba al centro de la vista (dentro si la vista toca el borde de arriba). Solo con una pantalla a
# la vista y sin dial ni arrastre en curso.
func _update_view_handle() -> void:
	if not is_instance_valid(_view_handle):
		return
	var rect: Rect2 = _view_screen_rect() if _mount.is_showing() else Rect2()
	var show: bool = rect.size.x > 0.0 and rect.size.y > 0.0 and not _selector.is_open() \
		and not _dragging_view and not is_instance_valid(_drag_ghost)
	_view_handle.visible = show
	if not show:
		return
	var k: float = UIScaleCompensator.scale_for(self)
	var size: Vector2 = HANDLE_SIZE * k
	var y: float = rect.position.y - size.y - HANDLE_GAP * k
	if y < HANDLE_GAP * k:
		y = rect.position.y + HANDLE_GAP * k
	var x: float = clamp(rect.position.x + (rect.size.x - size.x) * 0.5, 0.0, get_viewport_rect().size.x - size.x)
	_view_handle.rect_position = Vector2(x, y)
	if _view_handle.rect_size != size:
		_view_handle.rect_size = size
		_view_handle.update()

func _update_camera_focus_button() -> void:
	if not is_instance_valid(_camera_focus_button):
		return
	var screen: Object = _suit_os().get_screen(_suit_os().get_active_screen_id())
	var snapshot: Dictionary = screen.widget_snapshot() if screen != null and screen.has_method("widget_snapshot") else {}
	var remote_view: bool = _suit_os().get("presents_views_in_2d") == true
	var show: bool = remote_view and not _selector.is_open() and _mount.is_showing() \
		and String(snapshot.get("id", "")).begins_with("holoterminal:") and bool(snapshot.get("can_focus", false))
	_camera_focus_button.visible = show
	if not show:
		return
	var focused: bool = bool(snapshot.get("focused", false))
	_camera_focus_button.set_pressed_no_signal(focused)
	_camera_focus_button.icon = EyeClosed if focused else EyeOpen
	_camera_focus_button.hint_tooltip = "Dejar de enfocar cámara del piloto" if focused else "Enfocar cámara del piloto"
	var rect: Rect2 = _view_screen_rect()
	var size: Vector2 = CAMERA_FOCUS_SIZE * UIScaleCompensator.scale_for(self)
	_camera_focus_button.rect_size = size
	_camera_focus_button.rect_position = Vector2(
		clamp(rect.position.x + (rect.size.x - size.x) * 0.5, 0.0, get_viewport_rect().size.x - size.x),
		rect.end.y + HANDLE_GAP * UIScaleCompensator.scale_for(self))

func _on_camera_focus_pressed() -> void:
	var id: String = _suit_os().get_active_screen_id()
	if not id.empty():
		_suit_os().perform_action(id, "toggle_focus")

func is_on_view_handle(point: Vector2) -> bool:
	return is_instance_valid(_view_handle) and _view_handle.visible \
		and _view_handle.get_global_rect().grow(HANDLE_GAP * UIScaleCompensator.scale_for(self)).has_point(point)

func _is_on_camera_focus_button(point: Vector2) -> bool:
	return is_instance_valid(_camera_focus_button) and _camera_focus_button.visible \
		and _camera_focus_button.get_global_rect().has_point(point)

# Una pastilla con tres rayas de agarre.
func _draw_view_handle() -> void:
	var size: Vector2 = _view_handle.rect_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.1, 0.13, 0.85)
	style.border_color = Color(0.0, 0.83, 1.0, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(size.y * 0.5))
	_view_handle.draw_style_box(style, Rect2(Vector2.ZERO, size))
	var line := Color(0.0, 0.83, 1.0, 0.9)
	for i in range(3):
		var y: float = size.y * (0.3 + 0.2 * i)
		_view_handle.draw_line(Vector2(size.x * 0.3, y), Vector2(size.x * 0.7, y), line, 1.5, true)

# El host de widgets de este mismo backend (el del juego cuelga de SuitOS; el del control, del home).
func _widget_host() -> Node:
	var suit_os: Node = _suit_os()
	for host in get_tree().get_nodes_in_group("hud_widget_host"):
		if host._backend() == suit_os:
			return host
	return null

# TouchCameraControls: un dedo del modo HUD no gira la camara. Con el dial a la vista es del dial (o
# de un widget); con una pantalla abierta, lo que cae en ella o en su asa (usarla, arrastrar su
# widget). Fuera de la pantalla si es camara, y el joystick y los botones siguen siendo suyos.
func blocks_touch_camera(point: Vector2) -> bool:
	if is_queued_for_deletion() or _on_touch_controls(point):
		return false
	if _selector.is_open():
		return true
	if not _mount.is_showing():
		return false
	return is_on_view_handle(point) or _is_on_camera_focus_button(point) or _view_screen_rect().has_point(point)

func _on_touch_controls(point: Vector2) -> bool:
	var mobile: Node = get_node_or_null("/root/MobileUIManager")
	return mobile != null and mobile.has_method("is_point_on_touch_controls") \
		and mobile.is_point_on_touch_controls(point)

# Tocar fuera de la pantalla la cierra, simetrico con tocar el widget del slot para abrirla.
func _is_outside_view(pos: Vector2) -> bool:
	if not _opened or _selector.is_open() or not _mount.is_showing() or is_on_view_handle(pos) \
			or _is_on_camera_focus_button(pos):
		return false
	var rect: Rect2 = _view_screen_rect()
	return rect.size.x > 0.0 and rect.size.y > 0.0 and not rect.has_point(pos)


# El area que ocupa la vista en pantalla: el widget ampliado (2D) o, lo habitual, el cuadro del
# presentador 3D proyectado con la camara.
func _view_screen_rect() -> Rect2:
	if _mount.get_view_rect().size != Vector2.ZERO:
		return _mount.get_view_rect()
	var widget: Control = _mount.get_widget()
	if is_instance_valid(widget):
		# La transformacion dibujada: rect_global_position ya trae el corrimiento del pivote y la
		# escala, y sumarselos otra vez corria el rect media pantalla. Tocar el boton del widget
		# ampliado caia "fuera de la pantalla" y cerraba el modo HUD en vez de oprimirlo.
		var xf: Transform2D = widget.get_global_transform_with_canvas()
		return Rect2(xf.origin, widget.rect_size * xf.get_scale())
	var presenter: Spatial = _mount.get_presenter()
	var camera: Camera = get_viewport().get_camera()
	if presenter == null or camera == null:
		return Rect2()
	# El mesh puede estar reparentado a la camara (hud_attach_as_child), como en reveal_presenter.
	var mesh = presenter._get_hud_attach_target() if presenter.has_method("_get_hud_attach_target") \
		else presenter.get_node_or_null("ScreenContainer/ScreenMesh")
	if not is_instance_valid(mesh) or not ("width" in mesh) or not ("height" in mesh):
		return Rect2()
	var half_w: float = float(mesh.width) * 0.5
	var half_h: float = float(mesh.height) * 0.5
	var xf: Transform = mesh.global_transform
	var rect := Rect2(camera.unproject_position(xf.xform(Vector3(-half_w, -half_h, 0.0))), Vector2.ZERO)
	for corner in [Vector3(half_w, -half_h, 0.0), Vector3(-half_w, half_h, 0.0), Vector3(half_w, half_h, 0.0)]:
		rect = rect.expand(camera.unproject_position(xf.xform(corner)))
	return rect


# Cuentan angulo y magnitud: dentro de AIM_DEAD_ZONE del centro el dial no marca nada.
func _point_at(aim: Vector2) -> void:
	_aim = aim.limit_length(AIM_RADIUS)
	_selector.point_at(_selector.rect_size * 0.5 + _aim)

# El arco lo llenan los FAVORITOS, no el registry (FD-305 §2): el jugador decide que esta a mano.
# Su orden es la relevancia del momento, resuelta UNA vez al abrir y no por frame, o las opciones
# se reordenarian bajo el dedo (FD-306 §2). Lo demas vive en el drawer, detras del hub.
func _open_radial(slot: int = -1) -> void:
	_target_slot = slot
	_aim = Vector2.ZERO
	_stick_aiming = false
	_dial_ids = _dial_screen_ids()
	if _dial_ids.size() == 1 and _screen_ids.size() <= 1:
		# Una sola pantalla y nada mas que elegir: se abre directo, como siempre.
		_select(0)
		return
	var suit_os: Node = _suit_os()
	var items: Array = []
	for id in _dial_ids:
		var screen: Object = suit_os.get_screen(id)
		var title: String = String(screen.screen_title()) if screen != null and screen.has_method("screen_title") \
			else _screen_title(id)
		items.append({
			"id": id, "label": title,
			"icon": screen.screen_icon() if screen != null and screen.has_method("screen_icon") else null,
			"enabled": true
		})
	_selector.set_options(items)
	_selector.open()
	_placeholder.visible = _dial_ids.empty() and _screen_ids.empty()
	_set_virtual_mouse_enabled(false)
	_view_host.visible = false


# Favoritos ordenados, filtrados por el backend. El control remoto no tiene favoritos propios:
# ahi el arco sigue siendo el registry, como hasta ahora.
func _dial_screen_ids() -> Array:
	var suit_os: Node = _suit_os()
	if suit_os != null and suit_os.has_method("get_favorites_ordered"):
		return suit_os.get_favorites_ordered()
	return _screen_ids.duplicate()

# Soltar TAB tras el hold conserva una pantalla ya elegida. Si el dial sigue abierto, lo marcado
# queda elegido (el dial no se queda abierto); sin nada marcado se vuelve a la pantalla que habia,
# o se sale si no habia ninguna.
func _release_tab_hold() -> void:
	_tab_hold_active = false
	# El hold del boton tactil no tiene stick que volver al centro: si solto sobre el hub, lo
	# confirma. Solo ese origen: el reflejo del stick y el mouse que vuelve al medio descartan
	# (FD-306 §1.1, test_letting_go_on_the_hub... / test_release_in_the_dead_zone...).
	var touch_hold: bool = _consume_touch_hud_hold()
	if is_instance_valid(_drag_ghost):
		# Se estaba arrastrando un widget con el stick: soltar el hombro lo suelta donde este.
		_drop_option(_stick_cursor)
		_picked_during_hold = false
		return
	if _picked_during_hold:
		_picked_during_hold = false
		return
	if not _selector.is_open():
		return
	if _selector.hub_hovered() and touch_hold:
		_selector.confirm()
		return
	_confirm_or_dismiss() # con algo marcado -> _select, ya sin hold activo: la pantalla se queda

# El boton tactil del HUD avisa cuando lo apretaron (MobileUIManager.note_hud_touch). Se consume
# aca una sola vez, en el release del hold.
func _consume_touch_hud_hold() -> bool:
	var mobile: Node = get_node_or_null("/root/MobileUIManager")
	return mobile != null and mobile.has_method("consume_hud_touch") and bool(mobile.consume_hud_touch())

# Oprimir con algo marcado lo elige; sin nada marcado (zona muerta, o fuera del dial) lo cierra.
func _confirm_or_dismiss() -> void:
	if _selector.has_selection():
		_selector.confirm()
	else:
		_dismiss_radial()

# Cerrar el dial sin elegir siempre sale del modo HUD.
func _dismiss_radial() -> void:
	_opened_on_press = false
	_exit()

func _select(index: int) -> void:
	var suit_os: Node = _suit_os()
	if index == RadialSelectorV2.HUB_INDEX:
		# El hub no es una app: es la puerta al resto. Elegirlo abre el drawer y deja el dial
		# cerrado (el drawer es una vista, no un submenu del dial).
		_picked_during_hold = _tab_hold_active
		_open_drawer()
		return
	if index < 0 or index >= _dial_ids.size():
		return
	if _tab_hold_active:
		_picked_during_hold = true
	_opened_on_press = false
	var id: String = _dial_ids[index]
	if _target_slot >= 0:
		suit_os.pin_to_slot(_target_slot, id)
	_show_screen(id)

# El mouse virtual es para usar una pantalla (clic en su UI), no para el dial, que se apunta con
# el stick o el mouse. Se activa solo con cualquier boton o eje de gamepad: apretar el boton del
# HUD o mover el stick para apuntar lo prendia encima del dial, y con TAB (teclado) no. Apagado
# mientras el dial esta abierto, los dos entran igual.
func _set_virtual_mouse_enabled(enabled: bool) -> void:
	if not is_instance_valid(_virtual_mouse):
		return
	_virtual_mouse.set_process(enabled)
	_virtual_mouse.set_process_input(enabled)
	if enabled:
		_virtual_mouse.visible = true
		if _virtual_mouse.has_method("set_gamepad_cursor_enabled"):
			# Con el drawer abierto el mando navega la lista directo: su cursor inyectaria clicks.
			_virtual_mouse.set_gamepad_cursor_enabled(not _drawer_open())
	if not enabled:
		if _virtual_mouse.has_method("set_desktop_mouse_mode"):
			_virtual_mouse.set_desktop_mouse_mode(false)
		_virtual_mouse.visible = false

func _show_screen(id: String) -> void:
	_set_virtual_mouse_enabled(true)
	var suit_os: Node = _suit_os()
	var screen: Object = suit_os.get_screen(id)
	suit_os.open_screen(id)
	_selector.close()
	_view_host.visible = true

	var origin: Dictionary = {}
	if screen != null and screen.has_method("view_transition_origin"):
		origin = screen.view_transition_origin()

	if origin.get("kind", "") == "focus_rig":
		_cleanup_focus()
		_active_focused_screen = screen
		_pending_focus_screen = screen
		var rig = get_node_or_null(origin.get("path", NodePath("")))
		_pending_focus_camera = rig.get_node_or_null("Camera") as Camera if is_instance_valid(rig) else null
		_view_host.visible = false
		if screen.has_method("enter_focus_mode"):
			screen.enter_focus_mode()
		_mount_focused_screen_if_ready()
	else:
		_cleanup_focus()
		if screen.has_method("view_requires_input") and screen.view_requires_input():
			_active_focused_screen = screen
			# El cursor compartido sigue recibiendo joystick, pero se dibuja dentro del
			# Viewport de la pantalla enfocada.
			if is_instance_valid(_virtual_mouse):
				_virtual_mouse.visible = false
				_virtual_mouse.relative_target_scale = _focus_cursor_scale(screen)
			if screen.has_method("enter_focus_mode"):
				screen.enter_focus_mode()
		var snapshot: Dictionary = screen.widget_snapshot() if screen.has_method("widget_snapshot") else {"id": id}
		_mount.show(screen, snapshot, _view_host)
	_sync_widget_focus()

# Un hudable sin Pantalla muestra su widget ampliado. No usa mouse: se navega entre sus botones
# (cruceta o flechas, la navegacion de foco de la GUI) y se oprime el enfocado con el gatillo
# derecho, jump, crouch o ui_accept. En el host el modo HUD pausa el mundo, asi que esas acciones
# no hacen nada mas y quedan libres para eso.
func _sync_widget_focus() -> void:
	var widget = _mount.get_widget()
	if not is_instance_valid(widget) or _selector.is_open():
		return
	_set_virtual_mouse_enabled(false)
	_widget_click_was_down = true
	HudWidgetActionScript.focus_first_button(widget)

func _widget_screen_showing() -> bool:
	return is_instance_valid(_mount.get_widget()) and not _selector.is_open()

func _drive_widget_screen(input) -> void:
	if not _widget_screen_showing():
		return
	# Un solo flanco para todo: A es crouch y ui_accept a la vez, y oprimir dos veces el toggle de
	# la linterna en el mismo toque la dejaba como estaba.
	var down: bool = bool(input.tool_fire_primary) or bool(input.jump) or bool(input.crouch) \
		or Input.is_action_pressed("ui_accept")
	if down and not _widget_click_was_down:
		HudWidgetActionScript.press_focused_button(_mount.get_widget())
	_widget_click_was_down = down

func _cleanup_focus() -> void:
	_pending_focus_screen = null
	_pending_focus_camera = null
	_pending_swap_screen = null
	if is_instance_valid(_virtual_mouse):
		_virtual_mouse.visible = true
		_virtual_mouse.relative_target_scale = Vector2.ZERO
	if VisualServer.is_connected("frame_post_draw", self, "_complete_focus_swap"):
		VisualServer.disconnect("frame_post_draw", self, "_complete_focus_swap")
	if is_instance_valid(_active_focused_screen):
		if _active_focused_screen.has_method("set_source_view_visible"):
			_active_focused_screen.set_source_view_visible(true)
		if _active_focused_screen.has_method("exit_focus_mode"):
			_active_focused_screen.exit_focus_mode()
	_active_focused_screen = null

# El cursor virtual cruza el terminal en el mismo tiempo que cruza la pantalla: la resolucion
# del Viewport del terminal sobre la del viewport de render.
func _focus_cursor_scale(screen: Object) -> Vector2:
	var design: Vector2 = screen.view_size() if screen != null and screen.has_method("view_size") else Vector2.ZERO
	var root: Vector2 = get_viewport_rect().size
	if design.x <= 0.0 or design.y <= 0.0 or root.x <= 0.0 or root.y <= 0.0:
		return Vector2.ONE
	return design / root

func _mount_focused_screen_if_ready() -> void:
	if not is_instance_valid(_pending_focus_screen):
		return
	if is_instance_valid(_pending_focus_camera) and not _pending_focus_camera.current:
		return
	var screen: Object = _pending_focus_screen
	_pending_focus_screen = null
	_pending_focus_camera = null
	var snapshot: Dictionary = screen.widget_snapshot() if screen.has_method("widget_snapshot") else {}
	_mount.show(screen, snapshot, _view_host, true)
	if is_instance_valid(_mount.get_presenter()):
		_pending_swap_screen = screen
		VisualServer.connect("frame_post_draw", self, "_complete_focus_swap", [], CONNECT_ONESHOT)
		return
	_complete_focus_swap(screen)

func _complete_focus_swap(screen: Object = null) -> void:
	if screen == null:
		screen = _pending_swap_screen
	_pending_swap_screen = null
	if not is_instance_valid(screen):
		return
	_mount.reveal_presenter()
	if screen.has_method("forward_view_input") and is_instance_valid(_virtual_mouse):
		_virtual_mouse.visible = false # sigue generando eventos; el cursor se dibuja dentro del Viewport
		# Y los genera en las unidades del terminal, sin warp (VirtualMouse.relative_target_scale).
		_virtual_mouse.relative_target_scale = _focus_cursor_scale(screen)
	if screen.has_method("set_source_view_visible"):
		screen.set_source_view_visible(false)
	_view_host.visible = true

func _exit() -> void: # SuitOS saca el overlay y le devuelve la pausa a PauseManager
	_end_option_drag()
	_end_drawer_row_drag()
	_cleanup_focus()
	_set_virtual_mouse_enabled(false)
	_suit_os().close_hud_mode()

# --- Gamepad: botones de cara, cruceta y acordes (FD-304 §4/§5/§7) ---

# Los tres flancos de una vez: leerlos por separado en distintas ramas dejaba alguno sin consumir
# y el siguiente tick lo veia como pulsacion nueva.
func _face_edges(input) -> Dictionary:
	var edges := {}
	for button in FACE_FIELDS:
		var down: bool = bool(input.get(FACE_FIELDS[button]))
		edges[button] = down and not _face_was_down[button]
		_face_was_down[button] = down
	return edges


func _drive_hud_buttons(input) -> bool:
	"""Devuelve true si los botones de cara son de la pantalla abierta: en ese caso la ruta GUI
	por foco (_drive_widget_screen) no debe volver a oprimir nada."""
	var edges: Dictionary = _face_edges(input)
	if _selector.is_open():
		if edges["x"] or edges["b"]:
			_dismiss_radial()
			return false
		if edges["a"]:
			# Acorde (§5): con el hombro sostenido sobre un slot, A ejecuta la operacion primaria
			# de su pantalla sin abrirla. El dial NO se cierra: el slot sigue en foco.
			if _tab_hold_active and _target_slot >= 0 and _perform_chord(_target_slot):
				return false
			_selector.confirm()
		return false
	return _dispatch_screen_action(edges)


func _perform_chord(slot: int) -> bool:
	var suit_os: Node = _suit_os()
	var id: String = suit_os.slot_screen_id(slot)
	var screen: Object = suit_os.get_screen(id)
	if screen == null or not screen.has_method("hud_gamepad_actions"):
		return false
	for action in screen.hud_gamepad_actions():
		if not bool(action.get("confirm", false)):
			continue
		HudWidgetActionScript.perform(self, id, String(action.get("op", "")), {})
		Haptics.confirm()
		_selector.flash_option(_dial_ids.find(id))
		return true
	return false


# FD-304 §4: la pantalla declara que hace cada boton de cara y el overlay lo despacha por la misma
# ruta que su boton tactil, asi que funciona igual en local y en el control remoto. Si no declara
# nada, se cae a la navegacion por foco de la GUI que ya existia.
func _dispatch_screen_action(edges: Dictionary) -> bool:
	if not (_mount.is_showing() or is_instance_valid(_active_focused_screen)):
		_legend_actions = []
		return false
	var suit_os: Node = _suit_os()
	var id: String = suit_os.get_active_screen_id()
	var screen: Object = suit_os.get_screen(id)
	if screen == null or not screen.has_method("hud_gamepad_actions"):
		_legend_actions = []
		return false
	var actions: Array = screen.hud_gamepad_actions()
	if actions.empty():
		_legend_actions = []
		return false
	if _legend_actions.hash() != actions.hash():
		_legend_actions = actions
		_legend_msec = OS.get_ticks_msec()
	for action in actions:
		if not bool(edges.get(String(action.get("button", "")).to_lower(), false)):
			continue
		if not bool(action.get("enabled", true)):
			continue
		HudWidgetActionScript.perform(self, id, String(action.get("op", "")), {})
		_legend_msec = OS.get_ticks_msec()
		break
	# Los botones de cara son de esta pantalla aunque este tick no haya coincidido ninguno: si la
	# GUI tambien los oprimiera, el toggle de la linterna se accionaria dos veces en un toque.
	return true


# La cruceta recorre el arco en pasos, con auto-repeat al mismo umbral que el hold.
func _drive_nav(input) -> void:
	var dir: int = int(input.hud_nav)
	var now: int = OS.get_ticks_msec()
	var step: int = 0
	if dir == 0:
		_nav_dir = 0
	elif dir != _nav_dir:
		_nav_dir = dir
		_nav_msec = now
		step = dir
	elif now - _nav_msec >= NAV_REPEAT_MSEC and (now - _nav_msec - NAV_REPEAT_MSEC) % NAV_RATE_MSEC < 20:
		step = dir
	if step == 0:
		return
	if not _selector.is_open():
		# Con una pantalla abierta la cruceta recorre SU lista, si es que tiene una (el roster de
		# las criocapsulas). Sin contrato nuevo: se le pide "select" y las que no lo permiten ni
		# se enteran.
		_step_screen_selection(step)
		return
	if _dial_ids.empty():
		return
	# Arriba en pantalla es avanzar por el arco (el primer sector esta a las 6, el ultimo a las 12).
	# Sin nada marcado, el primer paso entra SIEMPRE por el primer sector, vaya para donde vaya:
	# entrar por el otro extremo segun la direccion se siente como un salto, no como un paso.
	var current: int = _selector.get_hovered_index()
	var next: int = 0
	if current >= 0:
		next = int(clamp(current - step, 0, _dial_ids.size() - 1))
	var angle: float = _selector.option_angle(next)
	_point_at(Vector2(cos(angle), sin(angle)) * AIM_RADIUS)


# --- Arrastre de un widget con el stick (FD-304 §6) ---

func _step_screen_selection(step: int) -> void:
	if not (_mount.is_showing() or is_instance_valid(_active_focused_screen)):
		return
	var suit_os: Node = _suit_os()
	var id: String = suit_os.get_active_screen_id()
	var screen: Object = suit_os.get_screen(id)
	if screen == null or not screen.has_method("allowed_actions") or not ("select" in screen.allowed_actions()):
		return
	HudWidgetActionScript.perform(self, id, "select", {"delta": step})


func _stick_drag_armed() -> bool:
	if not _tab_hold_active or _target_slot < 0 or not _selector.is_open():
		return false
	return _suit_os().has_screen(_suit_os().slot_screen_id(_target_slot))


func _drive_stick_drag(move: Vector2, input) -> void:
	var host = _widget_host()
	if host == null:
		return
	if _drag_id.empty():
		_drag_id = _suit_os().slot_screen_id(_target_slot)
		_drag_option = _dial_ids.find(_drag_id)
		_stick_cursor = host.slot_rect(_target_slot).get_center()
		_touch_start = _stick_cursor
		_touch_press_msec = OS.get_ticks_msec() - DRAG_HOLD_MSEC # el hold ya se cumplio al abrir
	if bool(input.analog_move_active) or move.length_squared() > MOVE_GESTURE_DEADZONE_SQ:
		_stick_cursor += move.limit_length(1.0) * STICK_DRAG_SPEED
		var size: Vector2 = get_viewport_rect().size
		_stick_cursor.x = clamp(_stick_cursor.x, 0.0, size.x)
		_stick_cursor.y = clamp(_stick_cursor.y, 0.0, size.y)
	_drive_option_drag(_stick_cursor, false)


# --- Deny del tap sobre un slot vacio (FD-304 §3) ---

func _deny_slot(slot: int) -> void:
	Haptics.pulse(Haptics.LIFT_MSEC)
	var host = _widget_host()
	if host != null and host.has_method("deny_slot"):
		host.deny_slot(slot)


# --- Relleno del hold y leyenda (FD-304 §3.1 / §9) ---

func _update_hold_feedback() -> void:
	var slot: int = _key_slot if _key_slot_down and not _selector.is_open() else -1
	var progress: float = _slot_gesture.progress() if slot >= 0 else 0.0
	if slot != _hold_slot or abs(progress - _hold_progress) > 0.001:
		_hold_slot = slot
		_hold_progress = progress
		if is_instance_valid(_hold_gauge):
			_hold_gauge.update()
	if is_instance_valid(_legend):
		_legend.update()


func _draw_hold_gauge() -> void:
	if _hold_slot < 0 or _hold_progress <= 0.0:
		return
	var host = _widget_host()
	if host == null:
		return
	var rect: Rect2 = host.slot_rect(_hold_slot)
	var color := Color(0.0, 0.835, 1.0, 0.9)
	_hold_gauge.draw_rect(rect, Color(color.r, color.g, color.b, 0.15))
	# El marco se llena como una barra proporcional al tiempo; soltar antes lo vacia solo.
	_hold_gauge.draw_rect(Rect2(rect.position, Vector2(rect.size.x * _hold_progress, 3.0)), color)
	_hold_gauge.draw_rect(rect, color, false, 2.0)


func _draw_legend() -> void:
	if _legend_actions.empty() or _selector.is_open() or _drawer_open():
		return
	if OS.get_ticks_msec() - _legend_msec > LEGEND_VISIBLE_MSEC:
		return
	if Input.get_connected_joypads().empty():
		return # con teclado y mouse la leyenda es ruido
	var font: Font = get_font("font")
	if font == null:
		return
	var k: float = UIScaleCompensator.scale_for(self)
	var pill: Vector2 = LEGEND_PILL * k
	var rect: Rect2 = _view_screen_rect()
	var total: float = pill.x * _legend_actions.size() + 8.0 * k * max(0, _legend_actions.size() - 1)
	var origin := Vector2(rect_size.x * 0.5 - total * 0.5,
		(rect.end.y + 12.0 * k) if rect.size.y > 0.0 else rect_size.y - pill.y - 24.0 * k)
	for i in range(_legend_actions.size()):
		var action: Dictionary = _legend_actions[i]
		var at := Vector2(origin.x + i * (pill.x + 8.0 * k), origin.y)
		_legend.draw_rect(Rect2(at, pill), Color(0.02, 0.1, 0.13, 0.85))
		_legend.draw_rect(Rect2(at, pill), Color(0.0, 0.835, 1.0, 0.8), false, 1.0)
		_legend.draw_string(font, at + Vector2(8.0 * k, pill.y * 0.7),
			"%s  %s" % [String(action.get("button", "")).to_upper(), String(action.get("label", ""))],
			Color(0.0, 0.835, 1.0, 1.0))


# --- Drawer (FD-305 §3.5) ---

# Puntero del drawer (mouse/dedo): la estrella favoritea, el resto de la fila abre, y una fila
# levantada se suelta en un slot. La estrella no arrastra: solo se toca.
func _drawer_pointer_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# El click y el movimiento que el motor emula de cada toque no son mouse real: el dedo se
		# resuelve por ScreenTouch/ScreenDrag y no debe prender el cursor virtual.
		if event.device == TOUCH_MOUSE_DEVICE:
			return
		# El cursor nativo no se muestra nunca: al primer movimiento real se prende el cursor
		# virtual (que sigue al puntero) y el nativo queda oculto.
		if event.relative.length_squared() > 0.0:
			_enable_drawer_cursor(event.position)
		if is_instance_valid(_drag_ghost):
			_drive_option_drag(event.position, false, true)
		elif _drawer_drag_row >= 0 and (event.position - _touch_start).length() >= TOUCH_MIN_DRAG:
			_start_drawer_row_drag(event.position)
		return
	if event is InputEventScreenDrag:
		if is_instance_valid(_drag_ghost):
			_drive_option_drag(event.position, false, true)
		elif _drawer_drag_row >= 0 and (event.position - _touch_start).length() >= TOUCH_MIN_DRAG:
			_start_drawer_row_drag(event.position)
		return
	if event is InputEventMouseButton:
		if event.device == TOUCH_MOUSE_DEVICE or event.button_index != BUTTON_LEFT:
			return
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_drawer_press_row = _drawer.row_at(event.position)
			_drawer_press_star = _drawer_press_row >= 0 and _drawer.star_at(event.position) == _drawer_press_row
			_drawer_drag_row = -1 if _drawer_press_star else _drawer_press_row
			_touch_start = event.position
			return
		if is_instance_valid(_drag_ghost):
			_drop_option(event.position)
			_end_drawer_row_drag()
			return
		var row: int = _drawer_press_row
		var star: bool = _drawer_press_star
		_end_drawer_row_drag()
		if row < 0:
			return
		_drawer.focus_row(row)
		if star:
			_drawer.toggle_favorite(_suit_os())
		else:
			_drawer.activate()
		return


func _start_drawer_row_drag(position: Vector2) -> void:
	_drag_id = _drawer.row_id(_drawer_drag_row)
	if _drag_id.empty():
		return
	_touch_press_msec = OS.get_ticks_msec() - DRAG_HOLD_MSEC # el gesto ya empezo en el press
	_drive_option_drag(position, false, true)


func _end_drawer_row_drag() -> void:
	_drawer_press_row = -1
	_drawer_press_star = false
	_drawer_drag_row = -1
	_drawer_drag_active = false


func _enable_drawer_cursor(position: Vector2) -> void:
	_set_virtual_mouse_enabled(true)
	if is_instance_valid(_virtual_mouse) and _virtual_mouse.has_method("set_desktop_mouse_mode"):
		_virtual_mouse.set_desktop_mouse_mode(true, position)


# El mando no usa el cursor: navega la lista directo (A/X/B + stick) y su hombro arrastra la fila
# enfocada. Cualquier actividad de mando apaga el cursor que el mouse hubiera prendido.
func _drawer_gamepad_active(input) -> bool:
	return bool(input.analog_move_active) or input.move_vec.length_squared() > MOVE_GESTURE_DEADZONE_SQ \
		or int(input.hud_nav) != 0 or int(input.hud_slot) > 0 \
		or bool(input.crouch) or bool(input.jump) or bool(input.interact)


func _drive_drawer_shoulder_drag(input) -> void:
	if not _drawer_drag_active:
		_drag_id = _drawer.focused_screen_id()
		if _drag_id.empty():
			return
		_drawer_drag_active = true
		_stick_cursor = _drawer.focused_row_center()
		_touch_start = _stick_cursor
		_touch_press_msec = OS.get_ticks_msec() - DRAG_HOLD_MSEC
	var move := Vector2(input.move_vec.x, input.move_vec.y)
	if move.length_squared() > 0.0:
		_stick_cursor += move.limit_length(1.0) * STICK_DRAG_SPEED
		var size: Vector2 = get_viewport_rect().size
		_stick_cursor.x = clamp(_stick_cursor.x, 0.0, size.x)
		_stick_cursor.y = clamp(_stick_cursor.y, 0.0, size.y)
	_drive_option_drag(_stick_cursor, false, true)


func _drive_drawer(input, delta: float) -> void:
	var edges: Dictionary = _face_edges(input)
	if not is_instance_valid(_drawer):
		return
	if _drawer_gamepad_active(input):
		_set_virtual_mouse_enabled(false)
	var shoulder: int = int(input.hud_slot) - 1
	if shoulder >= 0:
		_drive_drawer_shoulder_drag(input)
	elif _drawer_drag_active:
		_drop_option(_stick_cursor)
		_drawer_drag_active = false
	else:
		_drawer.drive(-float(input.move_vec.y), int(input.hud_nav), delta)
	if _drawer_drag_active:
		return # arrastrando: A/X/B no accionan la fila
	if edges["a"]:
		_drawer.activate()
	elif edges["x"]:
		_drawer.toggle_favorite(_suit_os())
	elif edges["b"]:
		# B vuelve: al dial si habia uno, o al juego si se entro directo.
		_close_drawer()
		if _dial_ids.empty():
			_exit()
		else:
			_open_radial(_target_slot)


func _suit_os() -> Node:
	return backend if is_instance_valid(backend) else get_node_or_null("/root/SuitOS")
