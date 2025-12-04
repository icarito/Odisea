extends Node

class_name PlayerMovement

# @export_range(0.0, 10.0, 0.1) var walk_speed := 1.3
export var walk_speed := 3.3
# @export_range(0.0, 20.0, 0.1) var run_speed := 5.5
export var run_speed := 7.5
# @export_range(0.0, 1.0, 0.01) var joystick_deadzone := 0.12
export var joystick_deadzone := 0.12
enum JoystickCurveType { LINEAR, EXPONENTIAL, INVERSE_S }
export (JoystickCurveType) var joystick_curve_type = JoystickCurveType.EXPONENTIAL
# @export_range(0.0, 1.0, 0.01) var analog_run_threshold := 0.7
export var analog_run_threshold := 0.7
# @export_range(0.0, 50.0, 1.0) var acceleration := 15.0
export var acceleration := 15.0
# @export_range(0.0, 50.0, 1.0) var friction := 60.0
export var friction := 60.0

var _CURVE_RESOURCES = [
	load("res://data/Curves/Linear.tres"),
	load("res://data/Curves/Exponential.tres"),
	load("res://data/Curves/Inverse_S.tres")
]

var horizontal_velocity := Vector3.ZERO
var direction := Vector3.ZERO
var movement_speed := 0.0
var is_walking := false
var is_running := false

func get_input_vector() -> Vector2:
	var ax := (Input.get_action_strength("left") - Input.get_action_strength("right")) + Input.get_joy_axis(0, 0)
	var az := (Input.get_action_strength("forward") - Input.get_action_strength("backward")) + Input.get_joy_axis(0, 1)
	return Vector2(ax, az)

func process_input(input_vec: Vector2, delta: float, cam_basis: Basis, is_aiming: bool, has_input: bool) -> void:
	if not has_input or is_aiming:
		is_walking = false
		is_running = false
		direction = Vector3.ZERO
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, friction * delta)
		return

	var mag := input_vec.length()
	var processed_mag := 0.0
	var processed_dir := Vector2.ZERO

	if mag > joystick_deadzone:
		processed_dir = input_vec.normalized()
		var curve: Curve = _CURVE_RESOURCES[joystick_curve_type]
		processed_mag = curve.interpolate(clamp(mag, 0.0, 1.0))

	if processed_mag <= 0.0:
		is_walking = false
		is_running = false
		direction = Vector3.ZERO
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, friction * delta)
	else:
		var cam_forward := cam_basis.z.normalized()
		var cam_right := cam_basis.x.normalized()
		var forward_input := processed_dir.y
		var right_input := processed_dir.x
		var dir3 := (cam_forward * forward_input) + (cam_right * right_input)
		direction = dir3.normalized()
		is_walking = true
		if Input.is_action_pressed("sprint") or processed_mag > analog_run_threshold:
			movement_speed = run_speed
			is_running = true
		else:
			movement_speed = walk_speed
			is_running = false
		movement_speed *= processed_mag

	var target_velocity = direction * movement_speed
	horizontal_velocity = horizontal_velocity.linear_interpolate(target_velocity, acceleration * delta)

func get_horizontal_velocity() -> Vector3:
	return horizontal_velocity
