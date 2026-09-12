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
var _active_focused_screen: Object = null
# El dial abierto por mantener TAB: mientras siga apretado es un cuasimodo (ver _release_tab_hold).
var _tab_hold_active: bool = false
# Modo del mouse antes de liberarlo para un widget de reemplazo; -1 = no esta liberado.
var _mouse_mode_before_widget: int = -1
var _picked_during_hold: bool = false
var _pending_focus_screen: Object = null
var _pending_focus_camera: Camera = null
var _pending_swap_screen: Object = null

func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	_virtual_mouse = VirtualMouse.attach_to(self)
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
	_restore_widget_pointer()

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
	_mount_focused_screen_if_ready()
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
		_tab_hold_active = true
		_picked_during_hold = false
		_open_radial()
	_aim_with_hud_button(bool(input.hud_mode))
	# Apuntar antes de resolver el release: la ultima muestra con TAB suelto todavia cuenta.
	_drive_from_stream(input)
	if gesture == Gesture.HOLD_RELEASE and _tab_hold_active:
		_release_tab_hold()

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
		_opened = true
		_tab_hold_active = true
		_picked_during_hold = false
		_open_radial()
	if _selector.is_open():
		_point_at(drag)

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
	if (event is InputEventMouseMotion or event is InputEventMouseButton) \
			and is_instance_valid(_active_focused_screen) \
			and _active_focused_screen.has_method("forward_view_input"):
		_active_focused_screen.forward_view_input(event)
	if event is InputEventMouseMotion:
		# Lo que hace PlayerControllerV2._input, que ahora esta pausado.
		if _touch_index >= 0:
			return # es un dedo: ya apunta el radial por InputEventScreenDrag, mas abajo
		if input_provider != null and "mouse_delta_accum" in input_provider:
			input_provider.mouse_delta_accum += event.relative
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index < 0:
			_touch_index = event.index
			_touch_start = event.position
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			if (event.position - _touch_start).length() < TOUCH_MIN_DRAG \
					and _is_outside_view(event.position):
				_exit()
				get_tree().set_input_as_handled()
		return
	if event is InputEventScreenDrag:
		# Todo el arrastre, no el ultimo delta (criterio de ElevatorFloorSelector).
		if event.index == _touch_index and (event.position - _touch_start).length() >= TOUCH_MIN_DRAG:
			_point_at(event.position - _touch_start)
		return
	# TAB NO se lee aca: tap/hold sale del stream (_physics_process).
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed and _selector.is_open():
		_selector.confirm()
	elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed \
			and _is_outside_view(event.position):
		_exit()
	elif event.is_action_pressed("ui_cancel"):
		_exit()
	elif event.is_action_pressed("ui_accept") and _selector.is_open():
		_selector.confirm()
	else:
		return
	get_tree().set_input_as_handled()

# Tocar fuera de la pantalla la cierra, simetrico con tocar el widget del slot para abrirla.
func _is_outside_view(pos: Vector2) -> bool:
	if not _opened or _selector.is_open() or not _mount.is_showing():
		return false
	var rect: Rect2 = _view_screen_rect()
	return rect.size.x > 0.0 and rect.size.y > 0.0 and not rect.has_point(pos)


# El area que ocupa la vista en pantalla: el widget ampliado (2D) o, lo habitual, el cuadro del
# presentador 3D proyectado con la camara.
func _view_screen_rect() -> Rect2:
	var widget: Control = _mount.get_widget()
	if is_instance_valid(widget):
		var scaled: Vector2 = widget.rect_size * widget.rect_scale
		return Rect2(widget.rect_global_position + widget.rect_pivot_offset - scaled * 0.5, scaled)
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
	_set_virtual_mouse_enabled(false)
	_sync_widget_pointer() # el dial se apunta con el mouse capturado
	_view_host.visible = false
	_hint.visible = false
	Gesture.mark_hold_discovered()

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
	if _selector.has_selection():
		_selector.confirm() # -> _select, ya sin hold activo: la pantalla se queda
	elif _mount.is_showing() or is_instance_valid(_active_focused_screen):
		_selector.close()
		_set_virtual_mouse_enabled(true)
		# Visible salvo en una pantalla con foco, donde el cursor se dibuja dentro del Viewport.
		_virtual_mouse.visible = not (is_instance_valid(_active_focused_screen) \
			and _active_focused_screen.has_method("forward_view_input"))
		_view_host.visible = true
		_sync_widget_pointer()
	else:
		_exit()

func _select(index: int) -> void:
	var suit_os: Node = _suit_os()
	if index < 0 or index >= _screen_ids.size():
		return
	if _tab_hold_active:
		_picked_during_hold = true
	suit_os.pin_screen(_screen_ids[index])
	_show_screen(_screen_ids[index])

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
	# El hold es invisible: se avisa una vez, hasta el primer uso, y solo si hay a donde cambiar.
	_hint.visible = _screen_ids.size() > 1 and not Gesture.hold_discovered()
	_sync_widget_pointer()

# Un hudable sin Pantalla muestra su widget ampliado, y a diferencia del terminal (que dibuja su
# cursor dentro de su Viewport, forward_view_input) no trae puntero: el modo HUD deja el mouse
# capturado y no habia con que hacerle clic. Mientras se ve el widget el mouse queda libre; con
# gamepad lo toma el mouse virtual (habilitado en _show_screen). El dial lo vuelve a capturar.
func _sync_widget_pointer() -> void:
	if is_instance_valid(_mount.get_widget()) and not _selector.is_open():
		if _mouse_mode_before_widget < 0:
			_mouse_mode_before_widget = Input.get_mouse_mode()
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		_restore_widget_pointer()

func _restore_widget_pointer() -> void:
	if _mouse_mode_before_widget < 0:
		return
	Input.set_mouse_mode(_mouse_mode_before_widget)
	_mouse_mode_before_widget = -1

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
	_pending_focus_screen = null
	_pending_focus_camera = null
	_pending_swap_screen = null
	if is_instance_valid(_virtual_mouse):
		_virtual_mouse.visible = true
	if VisualServer.is_connected("frame_post_draw", self, "_complete_focus_swap"):
		VisualServer.disconnect("frame_post_draw", self, "_complete_focus_swap")
	if is_instance_valid(_active_focused_screen):
		if _active_focused_screen.has_method("set_source_view_visible"):
			_active_focused_screen.set_source_view_visible(true)
		if _active_focused_screen.has_method("exit_focus_mode"):
			_active_focused_screen.exit_focus_mode()
	_active_focused_screen = null

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
	if screen.has_method("set_source_view_visible"):
		screen.set_source_view_visible(false)
	_view_host.visible = true

func _exit() -> void: # SuitOS saca el overlay y le devuelve la pausa a PauseManager
	_restore_widget_pointer()
	_cleanup_focus()
	if is_instance_valid(_virtual_mouse):
		_virtual_mouse.visible = false
	_suit_os().close_hud_mode()

func _suit_os() -> Node:
	return get_node_or_null("/root/SuitOS")
