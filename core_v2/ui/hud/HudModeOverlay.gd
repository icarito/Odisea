extends Control

# HudModeOverlay.gd - Modo HUD local de OdiseaOS (FD-296 F3).
# Lo monta SuitOS.open_hud_mode() en OverlayUIManager (SLOT_MODAL) con el mundo pausado por
# PauseManager.pause_hud_mode(), asi que corre en PAUSE_MODE_PROCESS. Radial de pantallas
# registradas; confirmar fija el pin (Slot B) y abre view_scene() del HUDable. Con una sola
# pantalla no hay radial: se fija y se abre directo. ESC/TAB sale por SuitOS.close_hud_mode().
#
# El radial sigue el patron de ElevatorFloorSelector: EL GESTO ES LA ELECCION (angulo de
# mouse_delta, stick derecho, stick de movimiento, arrastre touch) y el apuntado y el click
# salen de InputDataV2, no de eventos crudos. Una diferencia obligada: con el mundo pausado el
# proveedor del jugador no avanza y su peek_input() queda congelado en el frame del TAB. El
# overlay avanza uno propio, una muestra por tick de fisica y con la misma normalizacion que
# graba el replay (Y invertida, cuantizado, stick derecho sumado a mouse_delta). Inyectarle un
# proveedor en REPLAY reproduce la misma seleccion (ver test_hud_mode.gd).

const WIDGET_ZOOM := 3.0
# Mismos umbrales que ElevatorFloorSelector: se filtra ruido de angulo, no movimiento.
const MOVE_GESTURE_DEADZONE_SQ := 0.02
const MOUSE_GESTURE_DEADZONE := 3.0
const TOUCH_MIN_DRAG := 12.0

var input_provider = null # InputProviderV2; LIVE salvo que un test inyecte uno en REPLAY

var _selector: Control = null
var _view_host: Control = null
var _placeholder: Label = null
var _slots_label: Label = null
var _screen_ids: Array = []
var _mouse_aim_active: bool = false
# Arranca "sostenido": un boton que ya estaba apretado al abrir no confirma.
var _confirm_was_down: bool = true
var _touch_index: int = -1
var _touch_start: Vector2 = Vector2.ZERO

func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	_selector = get_node("RadialSelector")
	_view_host = get_node("ViewHost")
	_placeholder = get_node("Placeholder")
	_slots_label = get_node("SlotsLabel")
	if input_provider == null:
		input_provider = InputProviderV2.new()
	_selector.connect("option_selected", self, "_on_option_selected")
	_selector.connect("cancelled", self, "_exit")
	var suit_os: Node = _suit_os()
	if suit_os != null:
		suit_os.connect("widget_changed", self, "_refresh_slots")
	_open_radial()
	_refresh_slots()

func _open_radial() -> void:
	var suit_os: Node = _suit_os()
	_screen_ids = suit_os.get_registered_screens() if suit_os != null else []
	_placeholder.visible = _screen_ids.empty()
	if _screen_ids.empty():
		return
	if _screen_ids.size() == 1:
		_on_option_selected(0) # Nada que elegir: directo a la vista, sin radial.
		return
	var labels: Array = []
	for id in _screen_ids:
		var screen: Object = suit_os.get_screen(id)
		labels.append(screen.screen_title() if screen.has_method("screen_title") else id)
	_selector.set_status("")
	_selector.set_options(labels)
	_selector.open()
	# La aguja marca estado, no eleccion: la pantalla fijada hoy en Slot B.
	var pinned: int = _screen_ids.find(suit_os.get_pinned_screen_id())
	_selector.get_node("Indicator").visible = pinned >= 0
	_selector.set_level(max(pinned, 0))

func _physics_process(_delta: float) -> void:
	_drive_from_stream(_frame_input())

# La muestra del tick. get_input() una sola vez por tick de fisica: es este overlay el que
# avanza su proveedor (el del jugador esta pausado).
func _frame_input():
	if input_provider == null:
		return null
	return input_provider.get_input()

func _drive_from_stream(input) -> void:
	if input == null or not _selector.is_open():
		return
	# mouse_delta viene con Y invertida (arriba es +Y); en pantalla arriba es -Y.
	var gesture: Vector2 = Vector2(input.mouse_delta.x, -input.mouse_delta.y)
	var move: Vector2 = Vector2(input.move_vec.x, input.move_vec.y)
	if _touch_index < 0 and gesture.length() >= MOUSE_GESTURE_DEADZONE:
		_mouse_aim_active = true
		_point_at(gesture)
	elif move.length_squared() > MOVE_GESTURE_DEADZONE_SQ \
			and (input.analog_move_active or not _mouse_aim_active):
		# WASD solo apunta mientras no se haya movido el mouse (ver ElevatorFloorSelector).
		_point_at(move)
	var down: bool = bool(input.tool_fire_primary)
	if down and not _confirm_was_down:
		_selector.confirm()
	_confirm_was_down = down

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Lo que hace PlayerControllerV2._input, que ahora esta pausado.
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
		# Todo el arrastre, no el ultimo delta (mismo criterio que ElevatorFloorSelector).
		if event.index == _touch_index and (event.position - _touch_start).length() >= TOUCH_MIN_DRAG:
			_point_at(event.position - _touch_start)
		return
	if event.is_action_pressed("hud_mode") or event.is_action_pressed("ui_cancel"):
		_exit()
	elif event.is_action_pressed("ui_accept"):
		_selector.confirm()
	else:
		return
	get_tree().set_input_as_handled()

# Solo cuenta el angulo; la magnitud fija es para salir del hub_epsilon del dial aunque
# todavia no tenga tamaño.
func _point_at(direction: Vector2) -> void:
	if direction.length_squared() <= 0.0000001:
		return
	_selector.point_at(_selector.rect_size * 0.5 + direction.normalized() * 100.0)

func _on_option_selected(index: int) -> void:
	var suit_os: Node = _suit_os()
	if suit_os == null or index < 0 or index >= _screen_ids.size():
		return
	var id: String = _screen_ids[index]
	suit_os.pin_screen(id)
	suit_os.open_screen(id)
	_selector.close()
	_show_view(suit_os.get_screen(id), suit_os.get_slot_snapshot("slot_b"))

func _show_view(screen: Object, snapshot: Dictionary) -> void:
	var scene: PackedScene = screen.view_scene() if screen.has_method("view_scene") else null
	if scene != null:
		var view: Control = scene.instance()
		_view_host.add_child(view)
		var design: Vector2 = screen.view_size() if screen.has_method("view_size") else Vector2.ZERO
		if design.x <= 0.0 or design.y <= 0.0:
			view.set_anchors_and_margins_preset(Control.PRESET_WIDE)
			return
		# ponytail: tamaño de diseño escalado y centrado; no se reajusta si la ventana cambia.
		var host: Vector2 = _view_host.rect_size
		var k: float = min(host.x / design.x, host.y / design.y)
		view.set_anchors_preset(Control.PRESET_TOP_LEFT)
		view.rect_size = design
		view.rect_scale = Vector2(k, k)
		view.rect_position = (host - design * k) * 0.5
		return
	# Sin vista propia: el widget del slot, ampliado. Y si tampoco hay widget, el titulo.
	scene = screen.widget_scene() if screen.has_method("widget_scene") else null
	var widget: Control = scene.instance() if scene != null else Label.new()
	if scene == null:
		(widget as Label).text = String(snapshot.get("title", snapshot.get("id", "")))
	widget.name = "WidgetFallback"
	_view_host.add_child(widget)
	if widget.has_method("update_snapshot"):
		widget.update_snapshot(snapshot)
	widget.set_anchors_and_margins_preset(Control.PRESET_CENTER)
	widget.rect_pivot_offset = widget.rect_size * 0.5
	widget.rect_scale = Vector2(WIDGET_ZOOM, WIDGET_ZOOM)

func _refresh_slots(_slot: String = "", _snapshot: Dictionary = {}) -> void:
	var suit_os: Node = _suit_os()
	if suit_os == null:
		return
	# Narrativa ambiental, poco texto: solo que hay en cada slot (A automatico, B fijado).
	_slots_label.text = "A · %s      B · %s" % [
		_slot_title(suit_os.get_slot_snapshot("slot_a")),
		_slot_title(suit_os.get_slot_snapshot("slot_b"))]

func _slot_title(snapshot: Dictionary) -> String:
	if snapshot.empty():
		return "---"
	var title: String = String(snapshot.get("title", snapshot.get("id", "")))
	if String(snapshot.get("source", "")) == "offline":
		title += " [OFFLINE]"
	return title

func _exit() -> void:
	# SuitOS saca el overlay de SLOT_MODAL y le devuelve la pausa a PauseManager.
	_suit_os().close_hud_mode()

func _suit_os() -> Node:
	return get_node_or_null("/root/SuitOS")
