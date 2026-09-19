extends Control

# Cursor de UI para gamepad. Las acciones cursor_* ya apuntan al stick izquierdo
# y cursor_click_* a A/B en project.godot.

const SPEED := 650.0
const DEADZONE := 0.02
const CURSOR := preload("res://assets/cursor_none.svg")
const HOTSPOT := Vector2(7, 10)
const EXPONENTIAL_CURVE := preload("res://Curves/Exponential.tres")
const InputProviderV2 := preload("res://core_v2/input/InputProviderV2.gd")
const UIScaleCompensator := preload("res://core_v2/ui/UIScaleCompensator.gd")

# El cursor tiene que dibujarse sobre CUALQUIER UI clickeable: OverlayUIManager (115),
# ProtocolManager (120), MobileUIManager (100), y los Popup del arbol. Como hijo directo
# de un Control quedaba en la capa 0 y lo tapaba cualquiera de esas; move_child() no
# alcanzaba porque el orden entre CanvasLayers no sale del arbol. Debajo del 1000 de
# TransitionLayer: el fundido de carga si debe cubrirlo.
const LAYER := 200

var _position := Vector2.ZERO
var _active := false
var _desktop_mouse_mode := false
var _desktop_mouse_restore_mode := Input.MOUSE_MODE_VISIBLE
var _injecting_motion := false
var _ignore_warp_motion := false
var _skip_next_injected_motion := false
var _invert_axes := Vector2.ONE
# Con el drawer abierto el mando navega la lista directo (A/X/B + stick) y el cursor del gamepad
# inyectaria un click por cada boton encima de la fila. El mouse real sigue dibujando su cursor.
var gamepad_cursor_enabled := true
# Todo lo que el cursor mide esta en pixeles del viewport de render, que encoge con
# render_scale y se estira a la pantalla: sin compensar, en el handheld el cursor sale
# 1/escala mas grande y 1/escala mas rapido que la UI, que si esta compensada.
var _ui_scale := 1.0
# Con un destino holografico (la pantalla con foco del modo HUD) el cursor no camina por la
# pantalla: su movimiento se entrega como relative, escalado a las unidades del destino, sin warp
# ni tope. El terminal tiene su propio cursor en pixeles de SU Viewport (1280x816): movido en
# pixeles de pantalla, este se frenaba en el borde de la pantalla antes de que el del terminal
# llegara al suyo; y con el mouse capturado cada warp generaba un salto de ida y el re-centrado
# otro de vuelta, que el terminal recibia como movimiento. ZERO = modo normal.
var relative_target_scale := Vector2.ZERO

# Cuelga un cursor en su propia capa, arriba de todo. Preferir esto a add_child() directo:
# un cursor tapado por la UI que deberia poder clickear no sirve de nada.
# El cursor es uno solo y puede colgar de la raiz (PauseMenu, RemotePairingDialog), pero solo vive
# mientras alguna UI que lo pidio esta visible: `requester` (por defecto `parent`). Colgado de la
# raiz y siempre activo, en pleno juego el stick izquierdo lo movia e inyectaba movimiento de
# mouse — la camara seguia al stick — y A/B se volvian clicks consumidos.
static func attach_to(parent: Node, requester: Node = null) -> Control:
	var owner_node: Node = requester if requester != null else parent
	for existing in parent.get_tree().get_nodes_in_group("virtual_mouse"):
		if is_instance_valid(existing):
			existing.add_requester(owner_node)
			return existing as Control
	var host := CanvasLayer.new()
	host.name = "VirtualMouseLayer"
	host.layer = LAYER
	var cursor: Control = load("res://core_v2/ui/VirtualMouse.gd").new()
	cursor.name = "VirtualMouse"
	cursor.add_to_group("virtual_mouse")
	cursor.add_requester(owner_node)
	host.add_child(cursor)
	parent.add_child(host)
	return cursor

var _requesters := []
# Puñero liberado a proposito en pleno juego (ui_cancel / clic derecho): no hay UI que pida el
# cursor, pero el jugador espera un puntero. El nativo no se muestra: lo dibuja el virtual.
var _released := false

func add_requester(node: Node) -> void:
	if not node in _requesters:
		_requesters.append(node)

# Estandar para popups: cuelga el cursor compartido con el popup como solicitante y lo prende en
# modo desktop al aparecer. Asi el puntero queda oculto y lo dibuja el cursor virtual, aunque el
# juego lo tuviera capturado. Si el popup declara un nodo que se muestra/oculta distinto de si
# mismo (p. ej. su panel), se pasa como `requester`.
static func attach_popup(popup: Node, requester: Node = null) -> Control:
	var wanted: Node = requester if requester != null else popup
	var parent: Node = popup.get_tree().root if popup.is_inside_tree() else popup
	var cursor: Control = attach_to(parent, wanted)
	cursor._watch_visibility(wanted)
	return cursor

func _watch_visibility(node: Node) -> void:
	if node == self or not node is CanvasItem:
		return
	if not node.is_connected("visibility_changed", self, "_on_requester_visibility_changed"):
		node.connect("visibility_changed", self, "_on_requester_visibility_changed")

func _on_requester_visibility_changed() -> void:
	if is_wanted():
		set_desktop_mouse_mode(true, get_viewport().get_mouse_position())

# Alguna UI que pidio el cursor sigue viva y visible (un Node sin dibujo, como un test, cuenta).
func is_wanted() -> bool:
	if _released:
		return true
	return _wanted_by_requester()

# Una UI viva (menu, popup, pantalla) pide el cursor ahora mismo. Distinto de is_wanted(): no
# cuenta el puntero liberado por el juego, asi que sirve para no recapturar el mouse encima de
# un popup que lo necesita.
static func is_ui_wanted() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	for existing in tree.get_nodes_in_group("virtual_mouse"):
		var cursor: Control = existing as Control
		if is_instance_valid(cursor) and cursor._wanted_by_requester():
			return true
	return false

func _wanted_by_requester() -> bool:
	for node in _requesters:
		if is_instance_valid(node) and (not node is CanvasItem or node.is_visible_in_tree()):
			return true
	return false

# Cursor global sin UI que lo pida: lo usa el juego cuando el jugador libera el puntero. Si no
# existe todavia, se cuelga de la raiz y se devuelve.
static func ensure_global() -> Control:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for existing in tree.get_nodes_in_group("virtual_mouse"):
		if is_instance_valid(existing):
			return existing as Control
	var host := CanvasLayer.new()
	host.name = "VirtualMouseLayer"
	host.layer = LAYER
	var cursor: Control = load("res://core_v2/ui/VirtualMouse.gd").new()
	cursor.name = "VirtualMouse"
	cursor.add_to_group("virtual_mouse")
	host.add_child(cursor)
	tree.root.add_child(host)
	return cursor

# Estandar para el juego: liberar el puntero (ui_cancel/clic derecho) sin mostrar el nativo. Al
# soltar, el cursor queda dibujado en modo desktop; al recapturar, no queda nada colgado.
static func set_pointer_released(released: bool) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var cursor: Control = null
	for existing in tree.get_nodes_in_group("virtual_mouse"):
		if is_instance_valid(existing):
			cursor = existing as Control
			break
	if cursor == null:
		if not released:
			return
		cursor = ensure_global()
	if cursor == null:
		return
	# Una UI pudo haberlo apagado (modo HUD/pantalla): el puntero liberado necesita volver a
	# escuchar el mouse real aunque el cursor ya exista.
	cursor.set_process(true)
	cursor.set_process_input(true)
	cursor._released = released
	if released:
		cursor.set_desktop_mouse_mode(true, cursor.get_viewport().get_mouse_position())
	elif cursor._desktop_mouse_mode:
		cursor.set_desktop_mouse_mode(false)
	cursor.update()

func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Popup/ConfirmationDialog se registra como subwindow y toma prioridad de input sobre
	# los controles raiz; el cursor debe serlo tambien. El orden de DIBUJO no sale de aca
	# sino de la capa: ver attach_to().
	set_as_toplevel(true)
	anchor_right = 1.0
	anchor_bottom = 1.0
	_position = get_viewport_rect().size * 0.5
	# Las acciones cursor_* salen del InputMap sin pasar por InputProviderV2.step(),
	# que es donde se aplica la inversion manual de ejes (Opciones). Sin el mismo
	# signo, el cursor va al reves que caminar y la camara en el mismo aparato.
	_invert_axes = InputProviderV2.axis_inversion()
	# set_screen_stretch() (SettingsManager.apply_render_resolution, AdaptiveRenderScale)
	# redimensiona el viewport en vivo: la escala y el tope del cursor se recalculan ahi.
	var viewport := get_viewport()
	if viewport != null and not viewport.is_connected("size_changed", self, "_on_viewport_resized"):
		viewport.connect("size_changed", self, "_on_viewport_resized")
	_on_viewport_resized()
	set_process(true)
	# Sin esto el cursor no recibe el mouse real: se dibuja pero queda clavado. attach_to() no lo
	# prendia (las UIs lo apagan/prenden aparte) y el cursor global del puntero liberado nacia mudo.
	set_process_input(true)

func _on_viewport_resized() -> void:
	_ui_scale = UIScaleCompensator.scale_for(self)
	var bounds: Vector2 = get_viewport_rect().size
	_position.x = clamp(_position.x, 0.0, bounds.x)
	_position.y = clamp(_position.y, 0.0, bounds.y)
	update()

func _process(delta: float) -> void:
	if not _active and not _desktop_mouse_mode:
		return
	if not is_wanted():
		# La UI que lo pidio se cerro: no mover, no dibujar, y devolver el modo del mouse que la
		# UI habia guardado (en juego lo maneja la camara).
		_active = false
		if _desktop_mouse_mode:
			set_desktop_mouse_mode(false)
		update()
		return
	if not _active:
		return
	var direction := Vector2(
		Input.get_action_strength("cursor_right") - Input.get_action_strength("cursor_left"),
		Input.get_action_strength("cursor_down") - Input.get_action_strength("cursor_up")
	)
	# Se re-lee cada frame: la preferencia se puede cambiar en Opciones con una UI
	# que tiene el cursor abierto (el PauseMenu).
	_invert_axes = InputProviderV2.axis_inversion()
	direction *= _invert_axes
	var magnitude: float = direction.length()
	if magnitude < DEADZONE:
		return
	var step: Vector2 = direction.normalized() * EXPONENTIAL_CURVE.interpolate(magnitude) * SPEED * _ui_scale * delta
	if relative_target_scale != Vector2.ZERO:
		_emit_motion(step * relative_target_scale)
		return
	var previous := _position
	_position += step
	# El viewport, no rect_size: bajo un UIScaleCompensator el rect del padre mide el
	# espacio nominal (viewport/escala) y el cursor se iba fuera de la pantalla.
	var bounds: Vector2 = get_viewport_rect().size
	_position.x = clamp(_position.x, 0.0, bounds.x)
	_position.y = clamp(_position.y, 0.0, bounds.y)
	if _position == previous:
		return
	update()
	# Los Control hacen hit-test con el puntero real, no solo con el evento inyectado.
	# Este warp era la parte que hacia clickeable al cursor original.
	_ignore_warp_motion = true
	# Viewport.warp_mouse y no Input.warp_mouse_position: la segunda quiere coordenadas de
	# VENTANA, y con stretch "viewport" (render_resolution * render_scale estirado a la
	# pantalla) eso no es lo mismo que _position. Ver _emit_event.
	get_viewport().warp_mouse(_position)
	call_deferred("_clear_warp_motion")
	_emit_motion(_position - previous)

func _input(event: InputEvent) -> void:
	if not is_wanted():
		return
	if event is InputEventMouseMotion:
		if _desktop_mouse_mode:
			_position = event.position
			update()
			return
		if _injecting_motion:
			return
		# SceneTree entrega input_event en el siguiente pase de input en algunos
		# backends; sin este latch nuestro propio movimiento se volveria a inyectar.
		if _skip_next_injected_motion:
			_skip_next_injected_motion = false
			return
		if _ignore_warp_motion:
			_ignore_warp_motion = false
			return
		# El mouse real siempre toma el control: el cursor del sistema no se muestra nunca, el
		# virtual lo reemplaza siguiendo al puntero (modo desktop). Antes se soltaba el grab y se
		# mostraba el del sistema; eso ahora queda dentro de set_desktop_mouse_mode.
		if not _active or event.relative.length_squared() > 0.0:
			set_desktop_mouse_mode(true, event.position)
		return
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		if gamepad_cursor_enabled:
			_activate()
	if not event is InputEventJoypadButton:
		return
	if not gamepad_cursor_enabled:
		return
	# Conserva el mapeo directo A/B del cursor original; no depende de que ui_accept
	# consuma antes la accion de InputMap.
	var button := BUTTON_LEFT if event.button_index == JOY_BUTTON_0 else BUTTON_RIGHT if event.button_index == JOY_BUTTON_1 else 0
	if button == 0:
		return
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.pressed = event.pressed
	click.position = _position
	click.global_position = _position
	_emit_event(click)
	get_tree().set_input_as_handled()

func _activate() -> void:
	if _desktop_mouse_mode:
		set_desktop_mouse_mode(false)
	if _active:
		return
	_active = true
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	update()

func set_gamepad_cursor_enabled(enabled: bool) -> void:
	# Con el drawer abierto el mando navega la lista directo: el cursor del gamepad inyectaria un
	# click por cada boton. El mouse real sigue dibujando su cursor.
	gamepad_cursor_enabled = enabled

func is_desktop_mouse_mode() -> bool:
	return _desktop_mouse_mode

func set_desktop_mouse_mode(enabled: bool, position: Vector2 = Vector2.ZERO) -> void:
	# Al prender se reafirma HIDDEN y se reposiciona SIEMPRE, aunque ya estuviera en desktop: si el
	# juego habia vuelto a capturar el mouse (o el modo quedo desincronizado), el early-return de
	# antes dejaba el cursor dibujado pero con el puntero grabado, o sea clavado en el centro.
	if enabled:
		if not _desktop_mouse_mode:
			_desktop_mouse_restore_mode = Input.get_mouse_mode()
		_desktop_mouse_mode = true
		_active = false
		_position = position
		visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	elif _desktop_mouse_mode:
		_desktop_mouse_mode = false
		if Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN:
			Input.set_mouse_mode(_desktop_mouse_restore_mode)
	update()

func _emit_motion(relative: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = _position
	motion.global_position = _position
	motion.relative = relative
	_skip_next_injected_motion = true
	_injecting_motion = true
	_emit_event(motion)
	_injecting_motion = false

# SceneTree.input_event() pasa por Viewport::_make_input_local(), que aplica
# final_transform^-1: el evento se interpreta como coordenadas de VENTANA. _position esta
# en coordenadas del viewport (asi llega por _input, asi se dibuja), y con la ventana del
# handheld mas chica que el viewport de render el click caia lejos del cursor dibujado.
# Viewport.input() toma el evento ya local y no lo vuelve a transformar.
func _emit_event(event: InputEvent) -> void:
	get_viewport().input(event)

func _clear_warp_motion() -> void:
	_ignore_warp_motion = false

func _draw() -> void:
	if not _active and not _desktop_mouse_mode:
		return
	draw_texture_rect(CURSOR, Rect2(_position - HOTSPOT * _ui_scale, CURSOR.get_size() * _ui_scale), false)
