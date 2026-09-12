extends Control

# HudModeOverlay.gd - Modo HUD local de OdiseaOS (FD-296 F3, spec 4).
# Lo monta SuitOS.open_hud_mode() en OverlayUIManager (SLOT_MODAL) con el mundo pausado por
# PauseManager.pause_hud_mode(), asi que corre en PAUSE_MODE_PROCESS.
#
# TAB: tap (< 0.4 s) abre la ULTIMA pantalla (pin de Slot B, si no la automatica de Slot A);
# hold abre el radial. Con una pantalla abierta, tap cierra y hold cambia sin cerrar. Confirmar
# fija el pin. Con una sola pantalla no hay radial. Tap/hold, gesto y click salen de InputDataV2
# (patron ElevatorFloorSelector): con el mundo pausado el proveedor del jugador no avanza, asi
# que el overlay avanza uno propio, una muestra por tick y con la normalizacion del replay.

const Gesture = preload("res://core_v2/ui/hud/HudTabGesture.gd")
const ViewMount = preload("res://core_v2/ui/hud/HudViewMount.gd")
const VirtualMouse = preload("res://core_v2/ui/VirtualMouse.gd")
# Mismos umbrales que ElevatorFloorSelector: se filtra ruido de angulo, no movimiento.
const MOVE_GESTURE_DEADZONE_SQ := 0.02
const MOUSE_GESTURE_DEADZONE := 3.0
const TOUCH_MIN_DRAG := 12.0

var input_provider = null # InputProviderV2; LIVE salvo que un test inyecte uno en REPLAY

var _selector: Control = null
var _view_host: Control = null
var _placeholder: Label = null
var _slots_label: Label = null
var _hint: Label = null
var _screen_ids: Array = []
var _gesture = Gesture.new()
var _mount = ViewMount.new()
# Ya se decidio la pulsacion que abrio el modo HUD: desde ahi, un tap cierra.
var _opened: bool = false
var _mouse_aim_active: bool = false
var _confirm_was_down: bool = true # sostenido al abrir: ese boton no confirma
var _touch_index: int = -1
var _touch_start: Vector2 = Vector2.ZERO
var _active_focused_screen: Object = null

func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	add_child(VirtualMouse.new())
	_selector = get_node("RadialSelector")
	_view_host = get_node("ViewHost")
	_placeholder = get_node("Placeholder")
	_slots_label = get_node("SlotsLabel")
	_hint = get_node("Hint")
	if input_provider == null:
		input_provider = InputProviderV2.new()
	_selector.connect("option_selected", self, "_select")
	_selector.connect("cancelled", self, "_exit")
	var suit_os: Node = _suit_os()
	_screen_ids = suit_os.get_registered_screens()
	_placeholder.visible = _screen_ids.empty()
	suit_os.connect("widget_changed", self, "_refresh_slots")
	var mobile: Node = get_node_or_null("/root/MobileUIManager")
	if mobile != null and mobile.is_touch_active():
		_hint.text = "Mantén el widget para elegir pantalla"
	# El TAB que abrio el modo HUD sigue apretado: tap o hold se decide con las muestras.
	_gesture.begin_held()
	_refresh_slots()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_cleanup_focus()

func _exit_tree() -> void:
	_cleanup_focus()
	_mount.close()

# Entrada directa al radial (hold sobre el widget del slot, que no pasa por el stream).
func show_radial() -> void:
	_gesture.consume()
	_opened = true
	_open_radial()

# Entrada directa a una pantalla (tap sobre el widget de su slot).
func show_screen_id(id: String) -> void:
	_gesture.consume()
	_opened = true
	_show_screen(id)

func _physics_process(_delta: float) -> void:
	var input = _frame_input()
	if input == null:
		return
	var gesture: int = _gesture.feed(bool(input.hud_mode))
	if gesture == Gesture.TAP:
		if _opened:
			_exit()
			return
		_opened = true
		_open_last()
	elif gesture == Gesture.HOLD and not _selector.is_open():
		_opened = true
		_open_radial()
	_drive_from_stream(input)

# La muestra del tick: get_input() una vez por tick (el proveedor del jugador esta pausado).
func _frame_input():
	return input_provider.get_input()

func _drive_from_stream(input) -> void:
	if not _selector.is_open():
		return
	# mouse_delta viene con Y invertida (arriba es +Y); en pantalla arriba es -Y.
	var gesture: Vector2 = Vector2(input.mouse_delta.x, -input.mouse_delta.y)
	var move: Vector2 = Vector2(input.move_vec.x, input.move_vec.y)
	if _touch_index < 0 and gesture.length() >= MOUSE_GESTURE_DEADZONE:
		_mouse_aim_active = true
		_point_at(gesture)
	elif move.length_squared() > MOVE_GESTURE_DEADZONE_SQ \
			and (input.analog_move_active or not _mouse_aim_active):
		_point_at(move) # WASD solo mientras no se movio el mouse (ElevatorFloorSelector)
	var down: bool = bool(input.tool_fire_primary)
	if down and not _confirm_was_down:
		_selector.confirm()
	_confirm_was_down = down

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Lo que hace PlayerControllerV2._input, que ahora esta pausado.
		if InputProviderV2.is_emulated_from_touch(event):
			return # el dedo ya apunta el radial por InputEventScreenDrag, mas abajo
		if input_provider != null and "mouse_delta_accum" in input_provider:
			input_provider.mouse_delta_accum += event.relative
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index < 0:
			_touch_index = event.index
			_touch_start = event.position
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
		return
	if event is InputEventScreenDrag:
		# Todo el arrastre, no el ultimo delta (criterio de ElevatorFloorSelector).
		if event.index == _touch_index and (event.position - _touch_start).length() >= TOUCH_MIN_DRAG:
			_point_at(event.position - _touch_start)
		return
	# TAB NO se lee aca: tap/hold sale del stream (_physics_process).
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed and _selector.is_open():
		_selector.confirm()
	elif event.is_action_pressed("ui_cancel"):
		_exit()
	elif event.is_action_pressed("ui_accept") and _selector.is_open():
		_selector.confirm()
	else:
		return
	get_tree().set_input_as_handled()

# Solo cuenta el angulo; la magnitud fija saca del hub_epsilon aunque el dial no tenga tamaño.
func _point_at(direction: Vector2) -> void:
	if direction.length_squared() <= 0.0000001:
		return
	_selector.point_at(_selector.rect_size * 0.5 + direction.normalized() * 100.0)

func _open_last() -> void:
	var suit_os: Node = _suit_os()
	if _screen_ids.empty():
		return
	var last: String = suit_os.get_pinned_screen_id()
	if not suit_os.has_screen(last):
		last = String(suit_os.get_slot_snapshot("slot_a").get("id", ""))
	if suit_os.has_screen(last):
		_show_screen(last)
	else:
		_open_radial() # Sin ultima pantalla: a elegir (con una sola, directo).

func _open_radial() -> void:
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
	_view_host.visible = false
	_hint.visible = false
	Gesture.mark_hold_discovered()

func _select(index: int) -> void:
	var suit_os: Node = _suit_os()
	if index < 0 or index >= _screen_ids.size():
		return
	suit_os.pin_screen(_screen_ids[index])
	_show_screen(_screen_ids[index])

func _show_screen(id: String) -> void:
	var suit_os: Node = _suit_os()
	var screen: Object = suit_os.get_screen(id)
	suit_os.open_screen(id)
	_selector.close()
	_view_host.visible = true

	var origin: Dictionary = {}
	if screen != null and screen.has_method("view_transition_origin"):
		origin = screen.view_transition_origin()

	if origin.get("kind", "") == "focus_rig":
		print("[DEBUG] HudModeOverlay: focus_rig origin detectado, llamando enter_focus_mode")
		_cleanup_focus()
		_active_focused_screen = screen
		if screen.has_method("enter_focus_mode"):
			screen.enter_focus_mode()
	else:
		_cleanup_focus()

	var snapshot: Dictionary = screen.widget_snapshot() if screen.has_method("widget_snapshot") else {"id": id}
	_mount.show(screen, snapshot, _view_host)
	# El hold es invisible: se avisa una vez, hasta el primer uso, y solo si hay a donde cambiar.
	_hint.visible = _screen_ids.size() > 1 and not Gesture.hold_discovered()

# Narrativa ambiental, poco texto: solo que hay en cada slot (A automatico, B fijado).
func _refresh_slots(_slot: String = "", _snapshot: Dictionary = {}) -> void:
	var suit_os: Node = _suit_os()
	_slots_label.text = "A · %s      B · %s" % [
		_slot_title(suit_os.get_slot_snapshot("slot_a")),
		_slot_title(suit_os.get_slot_snapshot("slot_b"))]

func _slot_title(snapshot: Dictionary) -> String:
	var title: String = String(snapshot.get("title", snapshot.get("id", "---")))
	return title + (" [OFFLINE]" if String(snapshot.get("source", "")) == "offline" else "")

func _cleanup_focus() -> void:
	if is_instance_valid(_active_focused_screen):
		if _active_focused_screen.has_method("exit_focus_mode"):
			_active_focused_screen.exit_focus_mode()
	_active_focused_screen = null

func _exit() -> void: # SuitOS saca el overlay y le devuelve la pausa a PauseManager
	_cleanup_focus()
	_suit_os().close_hud_mode()

func _suit_os() -> Node:
	return get_node_or_null("/root/SuitOS")
