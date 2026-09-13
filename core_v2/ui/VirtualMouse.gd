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
var _injecting_motion := false
var _ignore_warp_motion := false
var _skip_next_injected_motion := false
var _invert_axes := false
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
static func attach_to(parent: Node) -> Control:
	var host := CanvasLayer.new()
	host.name = "VirtualMouseLayer"
	host.layer = LAYER
	var cursor: Control = load("res://core_v2/ui/VirtualMouse.gd").new()
	cursor.name = "VirtualMouse"
	host.add_child(cursor)
	parent.add_child(host)
	return cursor

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
	# que es donde se corrigen los ejes invertidos del handheld. Sin esto el cursor
	# va al reves que caminar y la camara en el mismo aparato.
	_invert_axes = InputProviderV2.wants_handheld_axis_inversion()
	# set_screen_stretch() (SettingsManager.apply_render_resolution, AdaptiveRenderScale)
	# redimensiona el viewport en vivo: la escala y el tope del cursor se recalculan ahi.
	var viewport := get_viewport()
	if viewport != null and not viewport.is_connected("size_changed", self, "_on_viewport_resized"):
		viewport.connect("size_changed", self, "_on_viewport_resized")
	_on_viewport_resized()
	set_process(true)

func _on_viewport_resized() -> void:
	_ui_scale = UIScaleCompensator.scale_for(self)
	var bounds: Vector2 = get_viewport_rect().size
	_position.x = clamp(_position.x, 0.0, bounds.x)
	_position.y = clamp(_position.y, 0.0, bounds.y)
	update()

func _process(delta: float) -> void:
	if not _active:
		return
	var direction := Vector2(
		Input.get_action_strength("cursor_right") - Input.get_action_strength("cursor_left"),
		Input.get_action_strength("cursor_down") - Input.get_action_strength("cursor_up")
	)
	if _invert_axes:
		direction = -direction
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
	if event is InputEventMouseMotion:
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
		if _active:
			if event.relative.length_squared() > 0.0:
				_active = false
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				_position = event.position
				update()
		else:
			_position = event.position
			update()
		return
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		_activate()
	if not event is InputEventJoypadButton:
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
	if _active:
		return
	_active = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
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
	if not _active:
		return
	draw_texture_rect(CURSOR, Rect2(_position - HOTSPOT * _ui_scale, CURSOR.get_size() * _ui_scale), false)
