extends Control
class_name SuitOSWidgetHost

# SuitOSWidgetHost.gd - Widget Host component for OdiseaOS (FD-296 F1.5)
# Listens to SuitOS.widget_changed(slot, snapshot) and mounts/updates widget overlays in its
# own CanvasLayer (WIDGET_LAYER), below the touch controls and below any open HUD screen.

const UIScaleCompensatorScript = preload("res://core_v2/ui/UIScaleCompensator.gd")
const HudWidgetActionScript = preload("res://core_v2/ui/hud/HudWidgetAction.gd")
const HudSlots = preload("res://core_v2/ui/hud/HudSlots.gd")
const ZoomRulerScript = preload("res://core_v2/ui/hud/ZoomRuler.gd")

# Cada slot tiene su lugar FIJO (HudSlots.slot_position): 1 y 2 arriba a la izquierda, 3 y 4
# arriba a la derecha. Ninguno se corre cuando otro esta vacio.
# En el telefono no hay TAB: el widget del slot ES el boton. Tap = su pantalla,
# hold (mismo umbral que TAB) = radial que fija en ese slot. Sale con el back de Android.
const HOLD_MSEC := 400
# Swipe hacia afuera (hacia el borde de su lado) vacia el slot. En pixeles nominales.
const SWIPE_MIN := 48.0
const SWIPE_EXIT_DURATION := 0.18
const SWIPE_EXIT_DISTANCE := 96.0
# Un slot vacio muestra un contorno del tamaño de un widget, inerte: solo es destino al arrastrar.
const PLACEHOLDER_SIZE := Vector2(200, 72)
# Mantener un widget (HOLD_MSEC) y mover el dedo lo levanta para soltarlo en otro slot. En pixeles
# nominales: cuanto tiene que moverse despues del hold para contar como arrastre.
const DRAG_START := 12.0
const DRAG_ALPHA := 0.8
# Los widgets no traen estilo de panel propio y el PanelContainer del tema por defecto es
# translucido: sobre el juego se leian como transparentes. En la esquina van opacos.
# Mientras se arrastra un widget aparece arriba al centro, entre los slots de cada lado: soltarlo
# ahi lo quita de su slot. Abajo lo tapaba la mano que arrastra. Tamaño en pixeles nominales.
const RECYCLE_SIZE := 56.0
const RECYCLE_MARGIN := 20.0
const RECYCLE_COLOR := Color(0.42, 0.68, 0.76, 0.85)
const RECYCLE_COLOR_HOT := Color(1.0, 0.45, 0.35, 1.0)
const WIDGET_BG := Color(0.05, 0.08, 0.1, 1.0)
const WIDGET_BORDER := Color(0.24, 0.55, 0.65, 1.0)
# Capa propia, por DEBAJO de la UI tactil (capa 10): el joystick y los botones se dibujan encima.
# Antes vivian en el slot HUD de OverlayUIManager (capa 115), que comparten el modo HUD y los
# avisos y no se puede bajar solo. Tambien quedan debajo del menu de pausa (50) y del modo HUD.
const WIDGET_LAYER := 5

var _active_screen_ids: Dictionary = {} # slot -> screen_id
var _press_msec: int = 0
# Donde cayo el ultimo toque o clic (pantalla) y si empezo sobre un boton del widget.
var _last_pointer_position := Vector2.ZERO
var _press_position := Vector2.ZERO
# El widget donde empezo la pulsacion en curso. Soltar solo cuenta sobre ese mismo widget: el toque
# que cierra el modo HUD (fuera de la pantalla) termina con un release que Godot 3 le entrega al
# ultimo control con foco de mouse, que es el widget que quedo debajo, y lo abria otra vez.
var _pressed_control: Control = null
# Cuadro en que el modo HUD se abrio o cerro. Un toque trae dos eventos (el clic que emula el motor
# y el ScreenTouch) en el mismo cuadro: si el primero cerro el modo HUD tocando fuera de la
# pantalla, el segundo caia sobre el widget que acababa de reaparecer y lo volvia a abrir.
var _hud_state_frame := -1
# Arrastre de un widget a otro slot (o de un item del radial, que maneja HudModeOverlay).
var _dragging := false
var _drag_origin := Vector2.ZERO
var _exiting_controls := []
var _drop_targets_visible := false
var _highlighted_slot := -1
var _recycle: Control = null
var _recycle_hot := false
var _press_on_button := false
var _widget_root: Control = null
# De donde salen slots y pantallas: SuitOS en el juego, RemoteHudBackend en el control remoto (que
# lo asigna antes de add_child). Mismo contrato; ver RemoteHudBackend.gd.
var backend: Node = null

func _backend() -> Node:
	return backend if is_instance_valid(backend) else get_node_or_null("/root/SuitOS")

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
		# Las rallitas del zoom viven en la misma capa del HUD, abajo al centro.
		var ruler: Control = ZoomRulerScript.new()
		ruler.name = "ZoomRuler"
		ruler.backend = _backend()
		_widget_root.add_child(ruler)
	return _widget_root

func _ready() -> void:
	# Solo para _input: el toque sobre un widget tambien cuenta con el modo HUD en pausa.
	pause_mode = PAUSE_MODE_PROCESS
	# MobileUIManager pregunta a todos los hosts si un toque cae sobre un widget.
	add_to_group("hud_widget_host")
	var suit_os = _backend()
	if suit_os != null:
		if not suit_os.is_connected("widget_changed", self, "_on_widget_changed"):
			suit_os.connect("widget_changed", self, "_on_widget_changed")
		# Abrir o cerrar una pantalla en el modo HUD cambia si los widgets se ven.
		for signal_name in ["screen_opened", "screen_closed", "hud_mode_changed"]:
			if not suit_os.is_connected(signal_name, self, "_on_hud_state_changed"):
				suit_os.connect(signal_name, self, "_on_hud_state_changed")
		# Los contornos de slot vacio solo tienen sentido donde hay pantallas (no en el menu).
		for signal_name in ["screen_registered", "screen_unregistered"]:
			if not suit_os.is_connected(signal_name, self, "_on_screens_changed"):
				suit_os.connect(signal_name, self, "_on_screens_changed")

		for i in range(HudSlots.COUNT):
			var slot: String = HudSlots.slot_key(i)
			_on_widget_changed(slot, suit_os.get_slot_snapshot(slot))
	var mobile = get_node_or_null("/root/MobileUIManager")
	if mobile != null and mobile.has_signal("touch_active_changed") \
			and not mobile.is_connected("touch_active_changed", self, "_on_screens_changed"):
		mobile.connect("touch_active_changed", self, "_on_screens_changed")
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
	var suit_os = _backend()
	var screen_open: bool = suit_os != null and suit_os.is_hud_mode_active() \
		and not String(suit_os.get_active_screen_id()).empty()
	# En el telefono los widgets se van con los controles tactiles cuando no hay actividad, y vuelven
	# con el proximo toque (MobileUIManager.touch_active_changed). En escritorio no hay ese modo.
	var mobile = get_node_or_null("/root/MobileUIManager")
	var touch_idle: bool = mobile != null and mobile.is_mobile() and not mobile.is_touch_active() \
		and not in_hud_mode
	# Mientras se arrastra hacia un slot (tambien el widget de una pantalla abierta) se ven todos.
	var hidden: bool = (get_tree().paused and not in_hud_mode) or touch_idle \
		or (screen_open and not _drop_targets_visible)
	var has_screens: bool = suit_os != null and not suit_os.get_registered_screens().empty()
	if not is_instance_valid(_widget_root):
		return
	for i in range(HudSlots.COUNT):
		var overlay = _widget_root.get_node_or_null("SuitOS_Widget_" + HudSlots.slot_key(i))
		if is_instance_valid(overlay):
			# Sin pantallas registradas (el menu) no hay HUD: un slot fijado no se muestra "offline".
			overlay.visible = not hidden and has_screens
		var placeholder = _widget_root.get_node_or_null("SuitOS_Placeholder_" + HudSlots.slot_key(i))
		if is_instance_valid(placeholder):
			# Un slot vacio solo se ve en el modo HUD (sin pantalla abierta) o como destino de un
			# arrastre, que muestra todos, ocupados incluidos. Jugando no ensucia la pantalla.
			var hud_active: bool = suit_os != null and suit_os.is_hud_mode_active()
			placeholder.visible = not hidden and has_screens \
				and (_drop_targets_visible or (hud_active and not is_instance_valid(overlay)))

func _on_screens_changed(_id = "") -> void:
	refresh_visibility()

func _on_hud_state_changed(_arg = null) -> void:
	_hud_state_frame = Engine.get_idle_frames()
	# Abrir o cerrar el modo HUD (o una pantalla) corta la pulsacion en curso.
	if _dragging and is_instance_valid(_pressed_control):
		_pressed_control.modulate.a = 1.0
		_relayout()
		show_drop_targets(false)
		_show_recycle(false)
	_dragging = false
	_pressed_control = null
	refresh_visibility()

func _exit_tree() -> void:
	var suit_os = _backend()
	if suit_os != null:
		if suit_os.is_connected("widget_changed", self, "_on_widget_changed"):
			suit_os.disconnect("widget_changed", self, "_on_widget_changed")

	for i in range(HudSlots.COUNT):
		_remove_overlay_for_slot(HudSlots.slot_key(i))

func _on_widget_changed(slot: String, snapshot: Dictionary) -> void:
	var overlay_name: String = "SuitOS_Widget_" + slot
	var screen_id: String = String(snapshot.get("id", ""))

	if snapshot.empty() or screen_id.empty():
		_remove_overlay_for_slot(slot)
		_ensure_placeholder(slot)
		refresh_visibility()
		return

	var prev_screen_id: String = String(_active_screen_ids.get(slot, ""))
	var widget_scene: PackedScene = _widget_scene_for(screen_id)

	if screen_id == prev_screen_id and not prev_screen_id.empty():
		var slot_node = get_widget_root()
		if is_instance_valid(slot_node):
			var existing = slot_node.get_node_or_null(overlay_name)
			# Solo se actualiza en su lugar si sigue siendo lo mismo: un slot fijado antes de que su
			# pantalla exista (la linterna por defecto, desde el menu) nace como rotulo de reserva, y
			# cuando la pantalla aparece hay que cambiarlo por el widget de verdad.
			var same_kind: bool = (existing is Label) == (widget_scene == null)
			if is_instance_valid(existing) and not existing.is_queued_for_deletion() and same_kind:
				if existing.has_method("update_snapshot"):
					existing.update_snapshot(snapshot)
				elif existing.has_method("set_snapshot"):
					existing.set_snapshot(snapshot)
				elif existing is Label:
					(existing as Label).text = _format_fallback_text(snapshot)
				return

	_remove_overlay_for_slot(slot)

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
			if overlay is PanelContainer and not overlay.has_stylebox_override("panel"):
				overlay.add_stylebox_override("panel", _widget_panel_style())
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

# Uno por slot, fijo: se muestra u oculta (refresh_visibility), nunca se crea y destruye con cada
# cambio de widget.
func _widget_scene_for(screen_id: String) -> PackedScene:
	var suit_os = _backend()
	if suit_os == null or not suit_os.has_screen(screen_id):
		return null
	var screen = suit_os.get_screen(screen_id)
	return screen.widget_scene() if is_instance_valid(screen) and screen.has_method("widget_scene") else null

func _ensure_placeholder(slot: String) -> Control:
	var existing = get_widget_root().get_node_or_null("SuitOS_Placeholder_" + slot)
	if is_instance_valid(existing):
		return existing
	var box := Panel.new()
	box.name = "SuitOS_Placeholder_" + slot
	box.rect_min_size = PLACEHOLDER_SIZE
	box.rect_size = PLACEHOLDER_SIZE
	# Un slot vacio no responde al toque ni se arrastra: solo se ve como destino. El toque sigue de
	# largo (a la camara).
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_stylebox_override("panel", _placeholder_style(false))
	get_widget_root().add_child(box)
	get_widget_root().move_child(box, 0) # debajo de los widgets
	_place(box, slot)
	return box

# --- Reciclaje ---

func recycle_rect() -> Rect2:
	var k: float = UIScaleCompensatorScript.scale_for(self)
	var size := Vector2(RECYCLE_SIZE, RECYCLE_SIZE) * k
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	return Rect2(Vector2((viewport_size.x - size.x) * 0.5, _safe_rect().position.y + RECYCLE_MARGIN * k), size)

func _show_recycle(visible: bool, hot: bool = false) -> void:
	if not visible and not is_instance_valid(_recycle):
		return
	if not is_instance_valid(_recycle):
		_recycle = Control.new()
		_recycle.name = "RecycleZone"
		_recycle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_widget_root().add_child(_recycle)
		_recycle.connect("draw", self, "_draw_recycle")
	var rect: Rect2 = recycle_rect()
	_recycle.rect_position = rect.position
	_recycle.rect_size = rect.size
	_recycle.visible = visible
	get_widget_root().move_child(_recycle, get_widget_root().get_child_count() - 1)
	_recycle_hot = hot
	_recycle.update()

# Tres flechas curvas en circulo (el simbolo de reciclaje), dibujadas: no hay icono en los assets.
func _draw_recycle() -> void:
	var size: Vector2 = _recycle.rect_size
	var center: Vector2 = size * 0.5
	var radius: float = min(size.x, size.y) * 0.3
	var color: Color = RECYCLE_COLOR_HOT if _recycle_hot else RECYCLE_COLOR
	var width: float = max(2.0, radius * 0.16)
	_recycle.draw_circle(center, min(size.x, size.y) * 0.5, Color(0.0, 0.05, 0.08, 0.7))
	var gap: float = 0.32
	for i in range(3):
		var from: float = -PI / 2.0 + i * TAU / 3.0 + gap
		var to: float = from + TAU / 3.0 - gap * 2.0
		_recycle.draw_arc(center, radius, from, to, 16, color, width, true)
		# Punta de flecha al final del arco, apuntando en el sentido del giro.
		var tip_base: Vector2 = center + Vector2(cos(to), sin(to)) * radius
		var tangent: Vector2 = Vector2(-sin(to), cos(to))
		var radial: Vector2 = Vector2(cos(to), sin(to))
		var head: float = width * 2.2
		_recycle.draw_colored_polygon(PoolVector2Array([
			tip_base + tangent * head,
			tip_base + radial * head * 0.8,
			tip_base - radial * head * 0.8,
		]), color)

func _widget_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = WIDGET_BG
	style.border_color = WIDGET_BORDER
	style.set_border_width_all(1)
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style

func _placeholder_style(highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.2, 0.27, 0.45) if highlighted else Color(0.0, 0.05, 0.08, 0.2)
	style.border_color = Color(0.0, 0.83, 1.0, 0.9) if highlighted else Color(0.42, 0.68, 0.76, 0.35)
	style.set_border_width_all(2 if highlighted else 1)
	return style

# --- Soltar en un slot (arrastre de un widget, o de un item del radial desde HudModeOverlay) ---

# El slot bajo un punto de pantalla, o -1. La caja es la fila entera del slot (sus widgets miden
# distinto), un poco agrandada para que soltar cerca tambien acierte.
func slot_at(point: Vector2) -> int:
	for i in range(HudSlots.COUNT):
		if slot_rect(i).has_point(point):
			return i
	return -1

func slot_rect(index: int) -> Rect2:
	var k: float = UIScaleCompensatorScript.scale_for(self)
	var size := Vector2(PLACEHOLDER_SIZE.x, HudSlots.SLOT_ROW_HEIGHT) * k
	return Rect2(HudSlots.slot_position(index, size, _safe_rect(), k), size).grow(HudSlots.SLOT_GAP * k)

# Mientras se arrastra: todos los contornos visibles, y el del slot bajo el dedo resaltado y encima
# de su widget. -1 lo apaga todo.
func show_drop_targets(active: bool, highlighted_slot: int = -1) -> void:
	_drop_targets_visible = active
	var target: int = highlighted_slot if active else -1
	if target != _highlighted_slot:
		for i in [_highlighted_slot, target]:
			if i < 0:
				continue
			var slot: String = HudSlots.slot_key(i)
			var box: Control = _ensure_placeholder(slot)
			box.add_stylebox_override("panel", _placeholder_style(i == target))
			get_widget_root().move_child(box, get_widget_root().get_child_count() - 1 if i == target else 0)
		_highlighted_slot = target
	refresh_visibility()

# Lugar del slot, pegado a su borde, con la escala de UIScaleCompensator: en pixeles fijos el
# widget creceria (y el margen se despegaria del borde) al bajar render_scale. Todo lo nominal
# va por k. Sin las margenes de la UI tactil a proposito: con el joystick abajo a la izquierda,
# su borde derecho empujaba el widget a media pantalla (y ese calculo ni siquiera contaba la
# escala del contenedor compensado). Los widgets van arriba y los controles abajo: no se pisan.
func _place(widget: Node, slot: String) -> void:
	var index: int = HudSlots.index_of(slot)
	if index < 0 or not is_instance_valid(widget) or not (widget is Control):
		return
	if _exiting_controls.has(widget):
		return
	# El que va en la mano no vuelve a su slot: sus datos cambian mientras se arrastra (la bateria de
	# la linterna, cada cuadro), eso lo redimensiona, y reubicarlo lo tironeaba de vuelta.
	if _dragging and widget == _pressed_control:
		return
	var control: Control = widget as Control
	var k: float = UIScaleCompensatorScript.scale_for(self)
	var min_size: Vector2 = control.get_combined_minimum_size()
	var height: float = max(min_size.y, 1.0)
	var fit: float = min(1.0, HudSlots.SLOT_ROW_HEIGHT / height) # nunca invade la fila vecina
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.rect_scale = Vector2.ONE * fit * k
	var size: Vector2 = Vector2(max(control.rect_size.x, min_size.x), height) * fit * k
	control.rect_position = HudSlots.slot_position(index, size, _safe_rect(), k)
	if control.name.begins_with("SuitOS_Placeholder_"):
		return
	# Un widget cambia de tamaño al llegarle datos (textos mas largos): sin volver a ubicarlo, el de
	# un slot derecho crecia hacia el borde y dejaba menos margen que los de la izquierda.
	if not control.is_connected("resized", self, "_on_slot_widget_resized"):
		control.connect("resized", self, "_on_slot_widget_resized", [control, slot])
	_make_tappable(control, slot)

func _on_slot_widget_resized(control: Control, slot: String) -> void:
	if is_instance_valid(control) and control.is_inside_tree() and not control.is_queued_for_deletion():
		call_deferred("_place", control, slot)

# El area util (sin el recorte de la camara en el borde), en pixeles del viewport: la safe area
# del sistema viene en pixeles de ventana y el viewport esta escalado por render_scale.
func _safe_rect() -> Rect2:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var window: Vector2 = OS.window_size
	if window.x <= 0.0 or window.y <= 0.0:
		return Rect2(Vector2.ZERO, viewport_size)
	var safe: Rect2 = OS.get_window_safe_area()
	var to_viewport: Vector2 = viewport_size / window
	# El recorte (camara perforada) esta de un solo lado en horizontal: se usa el mayor de los dos
	# en ambos, para que los slots de la derecha queden tan despegados del borde como los de la
	# izquierda.
	var side: float = max(safe.position.x, window.x - safe.end.x) * to_viewport.x
	var top: float = safe.position.y * to_viewport.y
	return Rect2(Vector2(side, top), Vector2(viewport_size.x - side * 2.0, viewport_size.y - top))

func _relayout() -> void:
	if not is_instance_valid(_widget_root):
		return
	for i in range(HudSlots.COUNT):
		var slot: String = HudSlots.slot_key(i)
		var placeholder = _widget_root.get_node_or_null("SuitOS_Placeholder_" + slot)
		if is_instance_valid(placeholder):
			_place(placeholder, slot)
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
	# TouchCameraControls no toma los toques que empiezan sobre este grupo: arrastrar un widget
	# giraba tambien la camara.
	control.add_to_group("touch_control")
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
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and is_instance_valid(_pressed_control):
		_last_pointer_position = event.position
		_drive_drag(_pressed_control)

# El widget apretado se levanta cuando, pasado el hold, el dedo se mueve; desde ahi lo sigue.
func _drive_drag(control: Control) -> void:
	var moved: Vector2 = _last_pointer_position - _press_position
	if not _dragging:
		var k: float = UIScaleCompensatorScript.scale_for(self)
		if OS.get_ticks_msec() - _press_msec < HOLD_MSEC or moved.length() < DRAG_START * k:
			return
		_dragging = true
		Input.vibrate_handheld(HudSlots.LIFT_VIBRATION_MSEC)
		_drag_origin = control.rect_position
		control.modulate.a = DRAG_ALPHA
		get_widget_root().move_child(control, get_widget_root().get_child_count() - 1)
	control.rect_position = _drag_origin + moved
	var over_recycle: bool = recycle_rect().has_point(_last_pointer_position)
	show_drop_targets(true, -1 if over_recycle else slot_at(_last_pointer_position))
	_show_recycle(true, over_recycle)

# Soltar un widget arrastrado: sobre el reciclaje se quita; en otro slot se intercambian; fuera de
# todo slot, un swipe hacia afuera lo vacia y cualquier otra cosa lo devuelve a su lugar.
func _end_drag(control: Control, slot: String) -> void:
	_dragging = false
	show_drop_targets(false)
	var over_recycle: bool = recycle_rect().has_point(_last_pointer_position)
	_show_recycle(false)
	var suit_os = _backend()
	var index: int = HudSlots.index_of(slot)
	var target: int = slot_at(_last_pointer_position)
	var swipe_min: float = SWIPE_MIN * UIScaleCompensatorScript.scale_for(self)
	control.modulate.a = 1.0
	if suit_os != null and over_recycle:
		Input.vibrate_handheld(HudSlots.DROP_VIBRATION_MSEC)
		suit_os.clear_slot(index)
	elif suit_os != null and target >= 0 and target != index:
		Input.vibrate_handheld(HudSlots.DROP_VIBRATION_MSEC)
		suit_os.move_slot(index, target)
	elif suit_os != null and target < 0 \
			and HudSlots.outward_swipe(index, _last_pointer_position - _press_position, swipe_min):
		_animate_swipe_exit(control, index, _last_pointer_position - _press_position)
	else:
		_place(control, slot)

func _animate_swipe_exit(control: Control, index: int, direction: Vector2) -> void:
	_exiting_controls.append(control)
	var tween := Tween.new()
	tween.pause_mode = PAUSE_MODE_PROCESS
	add_child(tween)
	var from: Vector2 = control.rect_position
	var distance: float = SWIPE_EXIT_DISTANCE * UIScaleCompensatorScript.scale_for(self)
	var to: Vector2 = from + direction.normalized() * distance
	var faded := control.modulate
	faded.a = 0.0
	tween.interpolate_property(control, "rect_position", from, to, SWIPE_EXIT_DURATION,
		Tween.TRANS_QUAD, Tween.EASE_IN)
	tween.interpolate_property(control, "modulate", control.modulate, faded, SWIPE_EXIT_DURATION,
		Tween.TRANS_QUAD, Tween.EASE_IN)
	tween.start()
	yield(tween, "tween_all_completed")
	_exiting_controls.erase(control)
	var suit_os: Node = _backend()
	if is_instance_valid(suit_os):
		suit_os.clear_slot(index)
	tween.queue_free()

# No cuenta el resto del toque que abrio o cerro el modo HUD. Con el dial a la vista los widgets si
# se tocan y se arrastran; con una pantalla abierta estan ocultos.
func _ignores_widget_taps() -> bool:
	return Engine.get_idle_frames() == _hud_state_frame

# Un widget de slot visible bajo el punto (el modo HUD le deja ese toque: no es "fuera del dial").
func widget_at(point: Vector2) -> bool:
	return not _widget_hit(point).empty()

func _widget_hit(point: Vector2) -> Array:
	if not is_instance_valid(_widget_root):
		return []
	for i in range(HudSlots.COUNT):
		var slot: String = HudSlots.slot_key(i)
		var widget = _widget_root.get_node_or_null("SuitOS_Widget_" + slot)
		if is_instance_valid(widget) and widget is Control and widget.is_visible_in_tree():
			var xf: Transform2D = widget.get_global_transform_with_canvas()
			if Rect2(xf.origin, widget.rect_size * xf.get_scale()).has_point(point):
				return [widget, slot]
	return []

# Con el dial del modo HUD a la vista la GUI no le entregaba el toque al widget (medido en
# Dome_Intro: ningun control recibia el evento). El overlay se lo pasa directo: tocarlo, arrastrarlo,
# o su boton si el toque cae ahi.
var _forwarded: Array = []

func forward_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		_forwarded = _widget_hit(event.position)
	if _forwarded.empty():
		return false
	var target: Array = _forwarded
	_last_pointer_position = event.position
	if not event.pressed:
		_forwarded = []
		if _press_on_button and not _dragging \
				and (event.position - _press_position).length() < DRAG_START * UIScaleCompensatorScript.scale_for(self):
			HudWidgetActionScript.press_button_at(target[0], event.position)
	elif event.pressed:
		_press_position = event.position
	_on_widget_gui_input(event, target[0], target[1])
	return true

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
	if pressed and _ignores_widget_taps():
		return
	if pressed:
		_press_msec = OS.get_ticks_msec()
		_press_position = _last_pointer_position
		_pressed_control = control
		return
	if _pressed_control != control:
		return
	_pressed_control = null
	if _dragging:
		_end_drag(control, slot)
		return
	var suit_os = _backend()
	if suit_os == null:
		return
	var index: int = HudSlots.index_of(slot)
	var screen_id: String = String(_active_screen_ids.get(slot, ""))
	var swipe_min: float = SWIPE_MIN * UIScaleCompensatorScript.scale_for(self)
	if HudSlots.outward_swipe(index, _last_pointer_position - _press_position, swipe_min):
		_animate_swipe_exit(control, index, _last_pointer_position - _press_position)
	elif OS.get_ticks_msec() - _press_msec >= HOLD_MSEC:
		pass # mantener sin mover no abre nada: mantener y mover arrastra
	elif not suit_os.has_screen(screen_id):
		suit_os.open_hud_mode(true, "", index) # fijada a una pantalla de otra escena: a reasignar
	else:
		suit_os.open_hud_mode(false, String(_active_screen_ids.get(slot, "")))
