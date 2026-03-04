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
var _invert_joystick_y := false
var _invert_joystick_x := false
const DIGITAL_ZOOM_SENSITIVITY := 0.1

var _touch_camera_drag := Vector2.ZERO
var _touch_camera_zoom := 0.0

func _init() -> void:
	_detect_inverted_joystick()

func _detect_inverted_joystick() -> void:
	# Check environment variable override first
	var force_invert = OS.get_environment("ODISEA_INVERT_JOYSTICK").to_lower()
	if force_invert in ["1", "true", "yes", "on"]:
		_invert_joystick_y = true
		_invert_joystick_x = true
		print("[InputProviderV2] Inverted joystick axes via ODISEA_INVERT_JOYSTICK")
		return
	
	# Check for Anbernic device via ODISEA_DEVICE env var OR cmdline args
	var device = OS.get_environment("ODISEA_DEVICE").to_lower()
	var cmdline_args = OS.get_cmdline_args()
	for arg in cmdline_args:
		if arg.begins_with("ODISEA_DEVICE="):
			device = arg.substr(15).to_lower()
	
	if device in ["anbernic", "351", "rg351", "rk3326"]:
		_invert_joystick_y = true
		_invert_joystick_x = true
		print("[InputProviderV2] Inverted joystick axes for Anbernic device: " + device)
		return
	
	# Check via HardwareProfile (for Anbernic detection)
	var hw_profile = null
	var main_loop = Engine.get_main_loop()
	if main_loop and main_loop is SceneTree:
		var scene_tree: SceneTree = main_loop
		if scene_tree.root:
			hw_profile = scene_tree.root.get_node_or_null("HardwareProfile")
	if hw_profile and "_detected_device_name" in hw_profile:
		var hw_device = str(hw_profile._detected_device_name).to_lower()
		if "anbernic" in hw_device or "351" in hw_device or "rg351" in hw_device:
			_invert_joystick_y = true
			_invert_joystick_x = true
			print("[InputProviderV2] Inverted joystick axes via HardwareProfile: " + hw_device)
			return
	
	# Check for Anbernic via /sys/firmware/devicetree/base/model
	var file = File.new()
	if file.file_exists("/sys/firmware/devicetree/base/model"):
		if file.open("/sys/firmware/devicetree/base/model", File.READ) == OK:
			var model = file.get_line().to_lower()
			file.close()
			if "351" in model or "rg351" in model or "anbernic" in model:
				_invert_joystick_y = true
				_invert_joystick_x = true
				print("[InputProviderV2] Inverted joystick axes for Anbernic device via devicetree")


# Universal input getter
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
			return d
		else:
			# Buffer ended, return null to signal end of replay
			return null
	else:
		return _read_live_input()


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


func _read_live_input() -> InputDataV2:
	var d = InputDataV2.new()

	if hardware_input_enabled:
		var raw_move_vec = Vector2(
			Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
		)
		d.move_vec = raw_move_vec

		# Apply curve to raw move vector (affects analog stick)
		d.move_vec = _apply_curve(d.move_vec, move_response_curve)
		d.move_vec *= joy_move_sensitivity

		d.move_vec.x = _q(d.move_vec.x)
		d.move_vec.y = _q(d.move_vec.y)

		d.jump = Input.is_action_pressed("jump")
		d.sprint = Input.is_action_pressed("run")
		d.crouch = Input.is_action_pressed("crouch")
		d.interact = Input.is_action_just_pressed("interact")

		# --- JOYSTICK SPRINT (Physical) ---
		var joy_move_x = Input.get_joy_axis(0, JOY_AXIS_0)
		var joy_move_y = Input.get_joy_axis(0, JOY_AXIS_1)
		if _invert_joystick_x:
			joy_move_x = - joy_move_x
		if _invert_joystick_y:
			joy_move_y = - joy_move_y
		var joy_move = Vector2(
			joy_move_x,
			joy_move_y
		)
		if joy_move.length() > 0.8:
			d.sprint = true
		
		# --- VIRTUAL/ANALOG AUTO SPRINT ---
		# Keep auto sprint for analog-like input, but do not force sprint for digital keyboard vectors.
		if not _is_digital_move_vector(raw_move_vec) and d.move_vec.length() > 0.85:
			d.sprint = true

		# Acumula y consume mouse_delta localmente
		var mouse_d = Vector2(_q(mouse_delta_accum.x), _q(-mouse_delta_accum.y))
		mouse_d *= hardware_look_sensitivity
		d.hardware_mouse_active = mouse_d.length() > 0.1

		# --- JOYSTICK CAMERA (Right Stick) ---
		var joy_look_x = Input.get_joy_axis(0, JOY_AXIS_2)
		var joy_look_y = Input.get_joy_axis(0, JOY_AXIS_3)
		if _invert_joystick_x:
			joy_look_x = - joy_look_x
		if _invert_joystick_y:
			joy_look_y = - joy_look_y
		var joy_look = Vector2(
			joy_look_x,
			- joy_look_y
		)
		if joy_look.length() > JOY_DEADZONE:
			joy_look = _apply_curve(joy_look, camera_response_curve)
			mouse_d += joy_look * joy_look_sensitivity

		# --- D-PAD CAMERA (Digital) ---
		var digital_look_x = Input.get_action_strength("camera_right") - Input.get_action_strength("camera_left")
		mouse_d.x += digital_look_x * joy_look_sensitivity

		# --- TOUCH CAMERA (from TouchCameraControls) ---
		if _touch_camera_drag.length_squared() > 0.001:
			mouse_d += _touch_camera_drag
			_touch_camera_drag = Vector2.ZERO

		d.mouse_delta = mouse_d

		# --- ZOOM ---
		var digital_zoom = (Input.get_action_strength("zoom_out") - Input.get_action_strength("zoom_in")) * DIGITAL_ZOOM_SENSITIVITY
		
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
