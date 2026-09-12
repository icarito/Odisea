extends Control

# Cursor de UI para gamepad. Las acciones cursor_* ya apuntan al stick izquierdo
# y cursor_click_* a A/B en project.godot.

const SPEED := 650.0
const DEADZONE := 0.02
const CURSOR := preload("res://assets/cursor_none.svg")
const EXPONENTIAL_CURVE := preload("res://Curves/Exponential.tres")
const InputProviderV2 := preload("res://core_v2/input/InputProviderV2.gd")

var _position := Vector2.ZERO
var _active := false
var _injecting_motion := false
var _ignore_warp_motion := false
var _skip_next_injected_motion := false
var _invert_axes := false

func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	_position = get_viewport_rect().size * 0.5
	# Las acciones cursor_* salen del InputMap sin pasar por InputProviderV2.step(),
	# que es donde se corrigen los ejes invertidos del handheld. Sin esto el cursor
	# va al reves que caminar y la camara en el mismo aparato.
	_invert_axes = InputProviderV2.wants_handheld_axis_inversion()
	set_process(true)

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
	var previous := _position
	_position += direction.normalized() * EXPONENTIAL_CURVE.interpolate(magnitude) * SPEED * delta
	_position.x = clamp(_position.x, 0.0, rect_size.x)
	_position.y = clamp(_position.y, 0.0, rect_size.y)
	if _position == previous:
		return
	update()
	# Los Control hacen hit-test con el puntero real, no solo con el evento inyectado.
	# Este warp era la parte que hacia clickeable al cursor original.
	_ignore_warp_motion = true
	Input.warp_mouse_position(_position)
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
			var relative: Vector2 = event.relative
			if relative.length_squared() > 0.0:
				_position += relative
				_position.x = clamp(_position.x, 0.0, rect_size.x)
				_position.y = clamp(_position.y, 0.0, rect_size.y)
				update()
				_emit_motion(relative)
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
	get_tree().input_event(click)
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
	get_tree().input_event(motion)
	_injecting_motion = false

func _clear_warp_motion() -> void:
	_ignore_warp_motion = false

func _draw() -> void:
	if _active:
		draw_texture(CURSOR, _position - Vector2(7, 10))
