extends Control
class_name SuitOSWidgetHost

# SuitOSWidgetHost.gd - Widget Host component for OdiseaOS (FD-296 F1.5)
# Listens to SuitOS.widget_changed(slot, snapshot) and mounts/updates widget overlays in its
# own CanvasLayer (WIDGET_LAYER), below the touch controls and below any open HUD screen.

const UIScaleCompensatorScript = preload("res://core_v2/ui/UIScaleCompensator.gd")
const HudWidgetActionScript = preload("res://core_v2/ui/hud/HudWidgetAction.gd")

# Cada slot tiene su fila FIJA en la misma esquina (arriba a la izquierda): A arriba, B debajo.
# B no sube cuando A esta vacio, asi el layout es el mismo con uno o dos slots.
const SLOT_ROWS := ["slot_a", "slot_b"]
const SLOT_ROW_HEIGHT := 96.0 # el widget mas alto hoy (SystemStatusWidget) mide 90
const SLOT_GAP := 8.0
const SLOT_PADDING := 16.0
# En el telefono no hay TAB: el widget del slot ES el boton. Tap = su pantalla,
# hold (mismo umbral que TAB) = radial. Sale con el back de Android.
const HOLD_MSEC := 400
# Capa propia, por DEBAJO de la UI tactil (capa 10): el joystick y los botones se dibujan encima.
# Antes vivian en el slot HUD de OverlayUIManager (capa 115), que comparten el modo HUD y los
# avisos y no se puede bajar solo. Tambien quedan debajo del menu de pausa (50) y del modo HUD.
const WIDGET_LAYER := 5

var _active_screen_ids: Dictionary = {} # slot -> screen_id
var _press_msec: int = 0
# Donde cayo el ultimo toque o clic (pantalla) y si empezo sobre un boton del widget.
var _last_pointer_position := Vector2.ZERO
var _press_on_button := false
var _widget_root: Control = null

# Donde cuelgan los widgets (en la capa propia). Publico para los tests.
func get_widget_root() -> Control:
	if not is_instance_valid(_widget_root):
		var layer := CanvasLayer.new()
		layer.name = "SuitOSWidgetLayer"
		layer.layer = WIDGET_LAYER
		add_child(layer)
		_widget_root = Control.new()
		_widget_root.name = "Widgets"
		_widget_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_widget_root)
		_widget_root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	return _widget_root

func _ready() -> void:
	# Solo para _input: el toque sobre un widget tambien cuenta con el modo HUD en pausa.
	pause_mode = PAUSE_MODE_PROCESS
	if has_node("/root/SuitOS"):
		var suit_os = get_node("/root/SuitOS")
		if not suit_os.is_connected("widget_changed", self, "_on_widget_changed"):
			suit_os.connect("widget_changed", self, "_on_widget_changed")
		# Abrir o cerrar una pantalla en el modo HUD cambia si los widgets se ven.
		for signal_name in ["screen_opened", "screen_closed", "hud_mode_changed"]:
			if not suit_os.is_connected(signal_name, self, "_on_hud_state_changed"):
				suit_os.connect(signal_name, self, "_on_hud_state_changed")

		_on_widget_changed("slot_a", suit_os.get_slot_snapshot("slot_a"))
		_on_widget_changed("slot_b", suit_os.get_slot_snapshot("slot_b"))
	if not get_viewport().is_connected("size_changed", self, "_relayout"):
		get_viewport().connect("size_changed", self, "_relayout")

# Cuando se ven los widgets. PauseManager avisa al pausar y reanudar; SuitOS, al abrir o cerrar
# una pantalla del modo HUD.
# - Menu de pausa: ocultos.
# - Modo HUD con una pantalla abierta: ocultos. La pantalla va encima de los widgets, y cuando
#   es el holograma 3D ninguna capa 2D puede quedar debajo de el: la unica forma es no dibujarlos.
# - Modo HUD con solo el dial: visibles (el dial ya queda encima, en OverlayUIManager).
func refresh_visibility() -> void:
	var pause_mgr = get_node_or_null("/root/PauseManager")
	var in_hud_mode: bool = pause_mgr != null and pause_mgr.has_method("is_hud_mode_paused") \
		and pause_mgr.is_hud_mode_paused()
	var suit_os = get_node_or_null("/root/SuitOS")
	var screen_open: bool = suit_os != null and suit_os.is_hud_mode_active() \
		and not String(suit_os.get_active_screen_id()).empty()
	var hidden: bool = (get_tree().paused and not in_hud_mode) or screen_open
	if not is_instance_valid(_widget_root):
		return
	for slot in SLOT_ROWS:
		var overlay = _widget_root.get_node_or_null("SuitOS_Widget_" + slot)
		if is_instance_valid(overlay):
			overlay.visible = not hidden

func _on_hud_state_changed(_arg = null) -> void:
	refresh_visibility()

func _exit_tree() -> void:
	if has_node("/root/SuitOS"):
		var suit_os = get_node("/root/SuitOS")
		if suit_os.is_connected("widget_changed", self, "_on_widget_changed"):
			suit_os.disconnect("widget_changed", self, "_on_widget_changed")

	_remove_overlay_for_slot("slot_a")
	_remove_overlay_for_slot("slot_b")

func _on_widget_changed(slot: String, snapshot: Dictionary) -> void:
	var overlay_name: String = "SuitOS_Widget_" + slot
	var screen_id: String = String(snapshot.get("id", ""))

	if snapshot.empty() or screen_id.empty():
		_remove_overlay_for_slot(slot)
		return

	var prev_screen_id: String = String(_active_screen_ids.get(slot, ""))

	if screen_id == prev_screen_id and not prev_screen_id.empty():
		var slot_node = get_widget_root()
		if is_instance_valid(slot_node):
			var existing = slot_node.get_node_or_null(overlay_name)
			if is_instance_valid(existing) and not existing.is_queued_for_deletion():
				if existing.has_method("update_snapshot"):
					existing.update_snapshot(snapshot)
				elif existing.has_method("set_snapshot"):
					existing.set_snapshot(snapshot)
				elif existing is Label:
					(existing as Label).text = _format_fallback_text(snapshot)
				return

	_remove_overlay_for_slot(slot)

	var widget_scene: PackedScene = null
	if has_node("/root/SuitOS"):
		var suit_os = get_node("/root/SuitOS")
		if suit_os.has_screen(screen_id):
			var screen = suit_os.get_screen(screen_id)
			if is_instance_valid(screen):
				if screen.has_method("widget_scene"):
					widget_scene = screen.widget_scene()

	_active_screen_ids[slot] = screen_id

	if widget_scene != null:
		var overlay = widget_scene.instance()
		overlay.name = overlay_name
		get_widget_root().add_child(overlay)
		if is_instance_valid(overlay):
			if overlay.has_method("update_snapshot"):
				overlay.update_snapshot(snapshot)
			elif overlay.has_method("set_snapshot"):
				overlay.set_snapshot(snapshot)
			_place(overlay, slot)
	else:
		var slot_hud = get_widget_root()
		if is_instance_valid(slot_hud):
			var label := Label.new()
			label.name = overlay_name
			label.text = _format_fallback_text(snapshot)
			slot_hud.add_child(label)
			_place(label, slot)
	# Un widget que se monta o cambia con la pausa o una pantalla abierta nace oculto.
	refresh_visibility()

# Fila del slot, pegada al borde izquierdo, con la escala de UIScaleCompensator: en pixeles fijos
# el widget creceria (y el margen se despegaria del borde) al bajar render_scale. Todo lo nominal
# va por k. Sin las margenes de la UI tactil a proposito: con el joystick abajo a la izquierda,
# su borde derecho empujaba el widget a media pantalla (y ese calculo ni siquiera contaba la
# escala del contenedor compensado). El widget va arriba y el joystick abajo: no se pisan.
func _place(widget: Node, slot: String) -> void:
	var row: int = SLOT_ROWS.find(slot)
	if row < 0 or not (widget is Control):
		return
	var control: Control = widget as Control
	var k: float = UIScaleCompensatorScript.scale_for(self)
	var height: float = max(control.get_combined_minimum_size().y, 1.0)
	var fit: float = min(1.0, SLOT_ROW_HEIGHT / height) # nunca invade la fila vecina
	var inset: Vector2 = _screen_cutout_inset()
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.rect_scale = Vector2.ONE * fit * k
	control.rect_position = Vector2(inset.x + SLOT_PADDING * k,
		inset.y + (SLOT_PADDING + row * (SLOT_ROW_HEIGHT + SLOT_GAP)) * k)
	_make_tappable(control, slot)

# El recorte de la pantalla (camara en el borde), en pixeles del viewport: la safe area del
# sistema viene en pixeles de ventana y el viewport esta escalado por render_scale.
func _screen_cutout_inset() -> Vector2:
	var window: Vector2 = OS.window_size
	if window.x <= 0.0 or window.y <= 0.0:
		return Vector2.ZERO
	var safe: Rect2 = OS.get_window_safe_area()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(safe.position.x * viewport_size.x / window.x, safe.position.y * viewport_size.y / window.y)

func _relayout() -> void:
	if not is_instance_valid(_widget_root):
		return
	for slot in SLOT_ROWS:
		var widget = _widget_root.get_node_or_null("SuitOS_Widget_" + slot)
		if is_instance_valid(widget) and not widget.is_queued_for_deletion():
			_place(widget, slot)

func _remove_overlay_for_slot(slot: String) -> void:
	var overlay_name: String = "SuitOS_Widget_" + slot
	if is_instance_valid(_widget_root):
		var node = _widget_root.get_node_or_null(overlay_name)
		if is_instance_valid(node):
			# Fuera del arbol ya: en cola de borrado seguia ocupando el nombre, y el widget nuevo
			# del mismo slot entraba renombrado (el viejo era el que encontraba get_node).
			_widget_root.remove_child(node)
			node.queue_free()
	_active_screen_ids.erase(slot)

func _format_fallback_text(snapshot: Dictionary) -> String:
	var title: String = String(snapshot.get("title", snapshot.get("id", "Unknown Screen")))
	var source: String = String(snapshot.get("source", "online"))
	var active_str: String = "ACTIVE" if bool(snapshot.get("active", false)) else "INACTIVE"
	var focus_str: String = " (FOCUSED)" if bool(snapshot.get("focused", false)) else ""

	if source == "offline":
		return "[OFFLINE] %s: %s%s" % [title, active_str, focus_str]
	return "[HUD] %s: %s%s" % [title, active_str, focus_str]

# El widget entero recibe el toque: los hijos se apagan para que el pick no se quede en un
# Label o en el punto de estado de 8 px. Los botones NO: el toggle de la linterna se oprime con
# clic o con el dedo, igual que en el control remoto, y no abre la pantalla.
func _make_tappable(control: Control, slot: String) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in control.get_children():
		_ignore_mouse(child)
	if not control.is_connected("gui_input", self, "_on_widget_gui_input"):
		control.connect("gui_input", self, "_on_widget_gui_input", [control, slot])

func _ignore_mouse(node: Node) -> void:
	if node is BaseButton:
		return
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		_last_pointer_position = event.position

# ponytail: el hold se mide con el reloj, no con el stream — el widget no aprieta ninguna
# accion y no hay muestra grabada que contar. Si el modo HUD entra al replay, el tap tendria
# que empujar hud_mode al stream como TAB.
func _on_widget_gui_input(event: InputEvent, control: Control, slot: String) -> void:
	var pressed: bool = false
	if event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		pressed = event.pressed
	else:
		return
	# Un toque que empieza sobre un boton del widget es del boton (HudWidgetAction.pointer_on_button).
	if pressed:
		_press_on_button = HudWidgetActionScript.pointer_on_button(control, _last_pointer_position)
	if _press_on_button:
		if not pressed:
			_press_on_button = false
		return
	control.accept_event() # que el toque no arrastre tambien la camara
	if pressed:
		_press_msec = OS.get_ticks_msec()
		return
	var suit_os = get_node_or_null("/root/SuitOS")
	if suit_os == null:
		return
	if OS.get_ticks_msec() - _press_msec >= HOLD_MSEC:
		suit_os.open_hud_mode(true)
	else:
		suit_os.open_hud_mode(false, String(_active_screen_ids.get(slot, "")))
