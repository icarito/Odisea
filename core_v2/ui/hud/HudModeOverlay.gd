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

func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	if use_virtual_mouse:
		_virtual_mouse = VirtualMouse.attach_to(self)
	_selector = get_node("RadialSelector")
	_selector.dead_zone = AIM_DEAD_ZONE
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
	_selector.connect("option_selected", self, "_select")
	_selector.connect("cancelled", self, "_exit")
	var suit_os: Node = _suit_os()
	_mount.view_2d = suit_os.get("presents_views_in_2d") == true
	_screen_ids = suit_os.get_registered_screens()
	_placeholder.visible = _screen_ids.empty()
	# El TAB que abrio el modo HUD sigue apretado: tap o hold se decide con las muestras.
	_gesture.begin_held()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cleanup_focus()

func _exit_tree() -> void:
	_end_option_drag()
	_cleanup_focus()
	_mount.close()

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
	if (gesture == Gesture.HOLD_RELEASE or slot_gesture == Gesture.HOLD_RELEASE) and _tab_hold_active:
		_release_tab_hold()
	if drives_dial_with_gameplay_input:
		_drive_widget_screen(input)

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
		_open_radial(slot) # vacio, o fijado a una pantalla de otra escena: a elegir para ese slot
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
	if move.length_squared() > MOVE_GESTURE_DEADZONE_SQ \
			and (input.analog_move_active or not _mouse_aim_active):
		# WASD solo mientras no se movio el mouse (ElevatorFloorSelector). El stick es en vivo.
		_stick_aiming = bool(input.analog_move_active)
		_point_at(move.limit_length(1.0) * AIM_RADIUS)
	elif _stick_aiming:
		_stick_aiming = false
		_point_at(Vector2.ZERO) # stick soltado: al centro, nada marcado
	var down: bool = bool(input.tool_fire_primary)
	if down and not _confirm_was_down:
		_confirm_or_dismiss()
	_confirm_was_down = down

func _input(event: InputEvent) -> void:
	if (event is InputEventMouseMotion or event is InputEventMouseButton) \
			and is_instance_valid(_active_focused_screen) \
			and _active_focused_screen.has_method("forward_view_input"):
		_active_focused_screen.forward_view_input(event)
	if event is InputEventMouseMotion:
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
			_drag_from_handle = is_on_view_handle(event.position)
			if _drag_from_handle:
				_drag_option = _screen_ids.find(_suit_os().get_active_screen_id())
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
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed and _selector.is_open():
		# El clic emulado de un toque no decide: el toque se resuelve al soltar (sector o fuera).
		# Por el device y no solo por InputProviderV2.pointer_is_from_touch(): con el arbol pausado
		# MobileUIManager no renueva esa ventana, y el clic del dedo cerraba el dial al apoyarlo.
		if event.device == TOUCH_MOUSE_DEVICE or InputProviderV2.pointer_is_from_touch():
			# Y sigue de largo a la GUI: si el dedo cayo sobre un widget de slot, ese clic es el
			# que lo oprime. Marcarlo como atendido dejaba al widget sin su toque.
			return
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
# slot de abajo. true mientras el dedo arrastra un item (no apunta el dial).
func _drive_option_drag(position: Vector2) -> bool:
	if not is_instance_valid(_drag_ghost):
		if _drag_option < 0 or _drag_option >= _screen_ids.size() \
				or (position - _touch_start).length() < TOUCH_MIN_DRAG:
			return false
		# Del dial hace falta el hold; el asa ya es para arrastrar.
		if not _drag_from_handle and (not _selector.is_open() \
				or OS.get_ticks_msec() - _touch_press_msec < DRAG_HOLD_MSEC):
			return false
		Haptics.pulse(Haptics.LIFT_MSEC)
		_drag_ghost = Label.new()
		_drag_ghost.name = "DragGhost"
		_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drag_ghost.text = _screen_title(_screen_ids[_drag_option])
		if _selector.option_font is Font:
			_drag_ghost.add_font_override("font", _selector.option_font)
		_drag_ghost.add_color_override("font_color", _selector.color_fg)
		add_child(_drag_ghost)
	_drag_ghost.rect_position = position - _drag_ghost.get_combined_minimum_size() * 0.5
	var host = _widget_host()
	if host != null:
		host.show_drop_targets(true, host.slot_at(position))
	return true

# Soltar el item levantado: sobre un slot lo fija ahi; en cualquier otro lado no pasa nada. Desde el
# dial, el dial queda abierto para seguir asignando; desde el asa de una pantalla, anclarla cierra
# el modo HUD para que se vea el widget en su slot.
func _drop_option(position: Vector2) -> void:
	var host = _widget_host()
	var slot: int = host.slot_at(position) if host != null else -1
	var from_handle: bool = _drag_from_handle
	if slot >= 0:
		Haptics.pulse(Haptics.DROP_MSEC)
		_suit_os().pin_to_slot(slot, _screen_ids[_drag_option])
	_end_option_drag()
	if slot >= 0 and from_handle:
		_exit()

func _end_option_drag() -> void:
	if is_instance_valid(_drag_ghost):
		_drag_ghost.queue_free()
	_drag_ghost = null
	_drag_option = -1
	_drag_from_handle = false
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
	var screen: Object = _suit_os().get_screen(id)
	return screen.screen_title() if screen != null and screen.has_method("screen_title") else id

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

func _open_radial(slot: int = -1) -> void:
	_target_slot = slot
	_aim = Vector2.ZERO
	_stick_aiming = false
	if _screen_ids.size() <= 1:
		if _screen_ids.size() == 1:
			_select(0)
		return
	var suit_os: Node = _suit_os()
	var labels: Array = []
	for id in _screen_ids:
		var screen: Object = suit_os.get_screen(id)
		labels.append(screen.screen_title() if screen.has_method("screen_title") else id)
	_selector.set_options(labels)
	_selector.open()
	_set_virtual_mouse_enabled(false)
	_view_host.visible = false

# Soltar TAB tras el hold. Si ya se eligio con TAB apretado fue un vistazo: se entro, se uso
# con el mouse virtual y el clic, y soltar sale del modo HUD. Si el dial sigue abierto, lo
# marcado queda elegido (el dial no se queda abierto); sin nada marcado se vuelve a la
# pantalla que habia, o se sale si no habia ninguna.
func _release_tab_hold() -> void:
	_tab_hold_active = false
	if _picked_during_hold:
		_picked_during_hold = false
		_exit()
		return
	if not _selector.is_open():
		return
	_confirm_or_dismiss() # con algo marcado -> _select, ya sin hold activo: la pantalla se queda

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
	if index < 0 or index >= _screen_ids.size():
		return
	if _tab_hold_active:
		_picked_during_hold = true
	_opened_on_press = false
	var id: String = _screen_ids[index]
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
	if not enabled:
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
	_cleanup_focus()
	if is_instance_valid(_virtual_mouse):
		_virtual_mouse.visible = false
	_suit_os().close_hud_mode()

func _suit_os() -> Node:
	return backend if is_instance_valid(backend) else get_node_or_null("/root/SuitOS")
