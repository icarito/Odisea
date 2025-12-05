extends Node

class_name PlayerMovement

export var walk_speed := 3.3
export var run_speed := 7.5
export var joystick_deadzone := 0.12
enum JoystickCurveType { LINEAR, EXPONENTIAL, INVERSE_S }
export (JoystickCurveType) var joystick_curve_type = JoystickCurveType.EXPONENTIAL
export var analog_run_threshold := 0.7
export var sprint_threshold := 0.7
export var tank_turn_speed := 0.3
export var analog_turn_multiplier := 1.0
export var acceleration := 15.0
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

func process_input(delta: float, cam_basis: Basis, has_input: bool) -> void:
	if not has_input:
		is_walking = false
		is_running = false
		direction = Vector3.ZERO
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, friction * delta)
		return

	var input_vec = get_input_vector()
	var mag = input_vec.length()
	var processed_mag := 0.0
	var processed_dir := Vector2.ZERO

	if mag > joystick_deadzone:
		processed_dir = input_vec.normalized()
		var curve: Curve = _CURVE_RESOURCES[joystick_curve_type]
		processed_mag = curve.interpolate(clamp(mag, 0.0, 1.0))
		# Reescalar por fuera de la zona muerta
		processed_mag = clamp(processed_mag, 0.0, 1.0)
		# Para input digital, aplicar threshold de walk si no sprint
		if processed_mag == 1.0 and not Input.is_action_pressed("sprint"):
			processed_mag = sprint_threshold

	var cam_forward := cam_basis.z.normalized()
	var cam_right := cam_basis.x.normalized()
	var forward_input := processed_dir.y
	var right_input := processed_dir.x

	# Dirección de movimiento: combinación de cam_forward y cam_right
	direction = (cam_forward * forward_input) + (cam_right * right_input)
	direction = direction.normalized()
	
	is_walking = true
	# Solo walk o run: caminar por defecto, correr si sprint o threshold
	if Input.is_action_pressed("sprint") or (processed_mag > sprint_threshold and processed_mag < 1.0):
		movement_speed = run_speed
		is_running = true
	else:
		movement_speed = walk_speed
		is_running = false
	# Escalar velocidad por magnitud
	movement_speed *= processed_mag

	var target_velocity = direction * movement_speed
	horizontal_velocity = horizontal_velocity.linear_interpolate(target_velocity, acceleration * delta)

func get_horizontal_velocity() -> Vector3:
	return horizontal_velocity

func get_turn_input() -> float:
	var input_vec = get_input_vector()
	var mag = input_vec.length()
	if mag > joystick_deadzone:
		var processed_dir = input_vec.normalized()
		return processed_dir.x * analog_turn_multiplier
	return 0.0

func process_input_vector(delta: float, cam_basis: Basis, input_vec: Vector2, is_sprinting: bool) -> void:
	var mag = input_vec.length()
	if mag < joystick_deadzone:
		is_walking = false
		is_running = false
		direction = Vector3.ZERO
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, friction * delta)
		return

	var processed_mag := 0.0
	var processed_dir := input_vec.normalized()
	var curve: Curve = _CURVE_RESOURCES[joystick_curve_type]
	processed_mag = curve.interpolate(clamp(mag, 0.0, 1.0))
	processed_mag = clamp(processed_mag, 0.0, 1.0)

	var cam_forward := cam_basis.z.normalized()
	var cam_right := cam_basis.x.normalized()
	var forward_input := processed_dir.y
	var right_input := processed_dir.x

	direction = (cam_forward * forward_input) + (cam_right * right_input)
	direction = direction.normalized()

	is_walking = true
	if is_sprinting or (processed_mag > sprint_threshold):
		movement_speed = run_speed
		is_running = true
	else:
		movement_speed = walk_speed
		is_running = false
	movement_speed *= processed_mag

	var target_velocity = direction * movement_speed
	horizontal_velocity = horizontal_velocity.linear_interpolate(target_velocity, acceleration * delta)
