extends Reference
class_name InputProviderV2

enum Mode {
	LIVE,
	REPLAY
}

var mode = Mode.LIVE
var playback_buffer := []
var playback_index := 0
var mouse_delta_accum := Vector2()
var zoom_delta_accum := 0.0
var move_response_curve: Curve
var camera_response_curve: Curve
var hardware_input_enabled := true

var joy_look_sensitivity := 15.0
var joy_move_sensitivity := 1.0
var hardware_look_sensitivity := 1.0
var touch_camera_sensitivity := 0.003
const JOY_DEADZONE := 0.2
const DIGITAL_ZOOM_SENSITIVITY := 0.1
const ANBERNIC_DEVICE_HINTS := [
	"anbernic",
	"rg351",
	"351",
	"351v",
	"351elec",
	"gameforce"
]

var _touch_camera_drag := Vector2.ZERO
var _touch_camera_zoom := 0.0
var _axis_profile_resolved := false
var _invert_joy_move_x := false
var _invert_joy_move_y := false
var _invert_joy_look_x := false
var _invert_joy_look_y := false
var handheld_axis_correction_enabled := false
var handheld_axis_profile := "none"

func _init() -> void:
	pass


# Universal input getter
# Ultimo input entregado por get_input() en este frame. Existe para que otros sistemas
# (consolas, menus de prop) puedan LEER el input del frame sin consumirlo: get_input()
# avanza playback_index, asi que llamarlo desde fuera del bucle del jugador se comia
# entradas del buffer y desincronizaba la reproduccion entera.
var last_input: InputDataV2 = null


func peek_input() -> InputDataV2:
	return last_input


func get_input() -> InputDataV2:
	if mode == Mode.REPLAY:
		if playback_index < playback_buffer.size():
			var entry = playback_buffer[playback_index]
			var d = InputDataV2.new()
			if typeof(entry) == TYPE_DICTIONARY and entry.has("input"):
				d.from_dict(entry["input"])
			else:
				d.from_dict(entry)
			playback_index += 1
			last_input = d
			return d
		else:
			# Buffer ended, return null to signal end of replay
			return null
	else:
		last_input = _read_live_input()
		return last_input


func _q(v):
	return round(v * 1000.0) / 1000.0

func _apply_curve(v: Vector2, curve: Curve) -> Vector2:
	if not curve:
		return v
	
	var length = v.length()
	if length < 0.001:
		return Vector2.ZERO
		
	# Normalize input length 0-1 for curve lookup
	# Assuming joystick input is roughly 0-1.
	length = clamp(length, 0.0, 1.0)
	var curved_length = curve.interpolate(length)
	
	return v.normalized() * curved_length


func _is_digital_move_vector(v: Vector2) -> bool:
	# Keyboard-style movement yields exact 0/1 action strengths.
	# We use this to avoid forcing sprint on desktop keyboard movement.
	var x = abs(v.x)
	var y = abs(v.y)
	var x_is_digital = is_equal_approx(x, 0.0) or is_equal_approx(x, 1.0)
	var y_is_digital = is_equal_approx(y, 0.0) or is_equal_approx(y, 1.0)
	return x_is_digital and y_is_digital



func _ensure_axis_profile_resolved() -> void:
	if _axis_profile_resolved:
		return

	var detected_anbernic = false
	var resolved_profile = "none"
	var forced_device = OS.get_environment("ODISEA_DEVICE").to_lower().strip_edges()
	if _contains_any_hint(forced_device, ANBERNIC_DEVICE_HINTS):
		detected_anbernic = true
		resolved_profile = "anbernic_env_invert_xy"

	_axis_profile_resolved = true
	handheld_axis_correction_enabled = detected_anbernic
	handheld_axis_profile = resolved_profile if detected_anbernic else "none"
	_invert_joy_move_x = detected_anbernic
	_invert_joy_move_y = detected_anbernic
	_invert_joy_look_x = detected_anbernic
	_invert_joy_look_y = detected_anbernic

func _contains_any_hint(text: String, hints: Array) -> bool:
	if text == "":
		return false
	for raw_hint in hints:
		var hint = String(raw_hint).strip_edges().to_lower()
		if hint != "" and text.find(hint) != -1:
			return true
	return false


func _action_strength(action_name: String) -> float:
	if not InputMap.has_action(action_name):
		return 0.0
	return Input.get_action_strength(action_name)


func _action_pressed(action_name: String) -> bool:
	if not InputMap.has_action(action_name):
		return false
	return Input.is_action_pressed(action_name)


func _action_just_pressed(action_name: String) -> bool:
	if not InputMap.has_action(action_name):
		return false
	return Input.is_action_just_pressed(action_name)


func _read_live_input() -> InputDataV2:
	var d = InputDataV2.new()

	if hardware_input_enabled:
		_ensure_axis_profile_resolved()

		var raw_move_vec = Vector2(
			_action_strength("move_right") - _action_strength("move_left"),
			_action_strength("move_backward") - _action_strength("move_forward")
		)

		d.jump = _action_pressed("jump")
		d.sprint = _action_pressed("run")
		d.crouch = _action_pressed("crouch")
		d.interact = _action_just_pressed("interact")
		d.focus = _action_just_pressed("focus")
		d.rotate_left = _action_pressed("rotate_left")
		d.rotate_right = _action_pressed("rotate_right")
		d.roll_left = _action_pressed("zero_g_roll_left")
		d.roll_right = _action_pressed("zero_g_roll_right")
		d.tool_fire_primary = _action_pressed("tool_fire_primary")
		d.tool_fire_secondary = _action_pressed("tool_fire_secondary")
		d.tool_next_mode = _action_just_pressed("tool_next_mode")
		d.tool_prev_mode = _action_just_pressed("tool_prev_mode")
		d.cargol_ability = _action_pressed("cargol_ability")

		# --- JOYSTICK SPRINT (Physical) ---
		var joy_move_x = Input.get_joy_axis(0, JOY_AXIS_0)
		var joy_move_y = Input.get_joy_axis(0, JOY_AXIS_1)
		if _invert_joy_move_x:
			joy_move_x = - joy_move_x
		if _invert_joy_move_y:
			joy_move_y = - joy_move_y
		var joy_move = Vector2(
			joy_move_x,
			joy_move_y
		)
		var move_source_vec = raw_move_vec
		if joy_move.length() > JOY_DEADZONE:
			move_source_vec = joy_move
		d.move_vec = _apply_curve(move_source_vec, move_response_curve)
		d.move_vec *= joy_move_sensitivity
		d.move_vec.x = _q(d.move_vec.x)
		d.move_vec.y = _q(d.move_vec.y)
		if joy_move.length() > 0.8:
			d.sprint = true
		
		# --- VIRTUAL/ANALOG AUTO SPRINT ---
		# Keep auto sprint for analog-like input, but do not force sprint for digital keyboard vectors.
		if not _is_digital_move_vector(move_source_vec) and d.move_vec.length() > 0.85:
			d.sprint = true

		# Acumula y consume mouse_delta localmente
		var mouse_d = Vector2(_q(mouse_delta_accum.x), _q(-mouse_delta_accum.y))
		mouse_d *= hardware_look_sensitivity
		d.hardware_mouse_active = mouse_d.length() > 0.1

		# --- JOYSTICK CAMERA (Right Stick) ---
		var joy_look_x = Input.get_joy_axis(0, JOY_AXIS_2)
		var joy_look_y = Input.get_joy_axis(0, JOY_AXIS_3)
		if _invert_joy_look_x:
			joy_look_x = - joy_look_x
		if _invert_joy_look_y:
			joy_look_y = - joy_look_y
		var joy_look = Vector2(
			joy_look_x,
			- joy_look_y
		)
		if joy_look.length() > JOY_DEADZONE:
			joy_look = _apply_curve(joy_look, camera_response_curve)
			mouse_d += joy_look * joy_look_sensitivity

		# --- D-PAD CAMERA (Digital) ---
		var digital_look_x = _action_strength("camera_right") - _action_strength("camera_left")
		mouse_d.x += digital_look_x * joy_look_sensitivity

		# --- TOUCH CAMERA (from TouchCameraControls) ---
		if _touch_camera_drag.length_squared() > 0.001:
			mouse_d += _touch_camera_drag
			_touch_camera_drag = Vector2.ZERO

		d.mouse_delta = mouse_d

		# --- ZOOM ---
		var digital_zoom = (_action_strength("zoom_out") - _action_strength("zoom_in")) * DIGITAL_ZOOM_SENSITIVITY
		
		# Robustness: Many handhelds/controllers overlap Stick Click with D-pad indices.
		# If the movement stick is active, we ignore digital (button-based) zoom to avoid accidents.
		if joy_move.length() > 0.4:
			digital_zoom = 0.0
			
		d.zoom_delta = zoom_delta_accum + digital_zoom + _touch_camera_zoom
		_touch_camera_zoom = 0.0

	# Limpiamos los acumuladores real aquí SIEMPRE para evitar fugas si se re-activa
	mouse_delta_accum = Vector2()
	zoom_delta_accum = 0.0

	return d


func set_replay_data(data: Array):
	playback_buffer = data
	playback_index = 0
	mode = Mode.REPLAY

func set_live_mode():
	playback_buffer.clear()
	playback_index = 0
	mode = Mode.LIVE

func add_touch_camera_drag(delta: Vector2) -> void:
	_touch_camera_drag += delta

func add_touch_camera_zoom(delta: float) -> void:
	_touch_camera_zoom += delta
