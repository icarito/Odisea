extends Node

class_name PlayerMovement

export var walk_speed := 3.3 # Velocidad al caminar (discreta)
export var run_speed := 7.5 # Velocidad al correr (discreta)
# Umbral de zona muerta para joystick analógico. Debajo de este valor, el input se ignora.
export var joystick_deadzone := 0.12
enum JoystickCurveType { LINEAR, EXPONENTIAL, INVERSE_S }
export (JoystickCurveType) var joystick_curve_type = JoystickCurveType.EXPONENTIAL
# Umbral de magnitud analógica para correr. Si la magnitud del input >= analog_run_threshold, se considera "correr".
export var analog_run_threshold := 0.7
# Umbral para activar el estado de sprint (usado junto a is_sprinting)
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
var horizontal_velocity_fixed := {"x": 0, "y": 0, "z": 0} # Punto fijo sincronizado
var direction := Vector3.ZERO
var movement_speed := 0.0
var is_walking := false
var is_running := false # true solo si is_sprinting
var strafe_mode := false

func get_horizontal_velocity() -> Vector3:
	return horizontal_velocity

func get_turn_input_from_vector(input_vec: Vector2) -> float:
	var mag = input_vec.length()
	if mag > joystick_deadzone:
		# NOTE: This uses the RAW input vector's X component for turning.
		# This is how tank controls can work with a single stick.
		return input_vec.normalized().x * analog_turn_multiplier
	return 0.0

func process_input_vector(delta: float, cam_basis: Basis, input_vec: Vector2, is_sprinting: bool, is_on_floor: bool) -> void:
	var mag = input_vec.length()
	if mag < joystick_deadzone:
		is_walking = false
		is_running = false
		direction = Vector3.ZERO
		if is_on_floor:
			# La fricción ahora se maneja en PlayerController.gd
			pass
		return

	# --- LÓGICA DE VELOCIDAD DISCRETA ---
	# El input analógico se discretiza en tres estados:
	#   0: Quieto (sin movimiento)
	#   1: Caminar (walk_speed)
	#   2: Correr (run_speed)
	# Los umbrales se configuran con joystick_deadzone y analog_run_threshold.
	var processed_mag := 0.0
	var processed_dir := input_vec.normalized()
	if mag >= analog_run_threshold:
		processed_mag = 2 # correr
	elif mag >= joystick_deadzone:
		processed_mag = 1 # caminar
	else:
		processed_mag = 0 # quieto
	# processed_mag ahora es 0 (quieto), 1 (caminar), 2 (correr)

	var basis_to_use: Basis = cam_basis
	var forward := basis_to_use.z.normalized()
	var right := basis_to_use.x.normalized()
	var forward_input := processed_dir.y
	var right_input := processed_dir.x

	direction = (forward * forward_input) + (right * right_input)
	direction = direction.normalized()

	# El PlayerController es responsable de la rotación del cuerpo.
	# Este componente solo calcula dirección y velocidad.

	is_walking = processed_mag > 0
	is_running = processed_mag == 2 and is_sprinting

	if is_running:
		movement_speed = run_speed
	elif is_walking:
		movement_speed = walk_speed
	else:
		movement_speed = 0.0

	# No escalar por processed_mag, solo usar walk_speed o run_speed

	var target_velocity = direction * movement_speed
	horizontal_velocity = horizontal_velocity.linear_interpolate(target_velocity, acceleration * delta)

	# Sincronizar punto fijo
	var FixedVec3 = preload("res://scripts/utils/FVec3.gd")
	horizontal_velocity_fixed = FixedVec3.from_vec3(horizontal_velocity)

	# (El cálculo de dirección ya fue realizado antes en esta función)

	# Determinar si hay movimiento (caminar o correr)
	is_walking = processed_mag > 0.01
	# Correr es un sub-estado de caminar, activado por sprint
	is_running = is_walking and is_sprinting

	if is_running:
		movement_speed = run_speed
	elif is_walking:
		movement_speed = walk_speed
	else:
		pass # (Ya no se usa processed_mag para escalar la velocidad)
