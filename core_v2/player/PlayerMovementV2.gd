extends Node

# PlayerMovementV2.gd - Componente para movimiento horizontal suavizado

export(float) var acceleration := 20.0
export(float) var ground_friction := 40.0
export(float) var air_friction := 10.0
export(float) var move_speed := 5.0
export(float) var run_speed_multiplier := 1.8
export(float) var air_control_multiplier := 0.5 # Reducir aceleración en el aire
export(float) var stop_threshold := 0.01 # Threshold para forzar velocidad a cero

# Refactored Movements Exports
export(float) var external_decay_rate := 2.0
export(float) var tank_turn_speed := 3.0
export(float) var tank_turn_transition_time := 1.0
export(Curve) var tank_turn_curve
export(float) var tank_turn_ramp_time := 0.5
export(Curve) var move_response_curve
export(Curve) var camera_response_curve
export(float) var strafe_turn_multiplier := 0.4
export(float) var strafe_speed_multiplier := 0.6

# Slope Handling (inspired by Terrestrial Characters)
export(float, 0, 90) var floor_max_angle_degrees := 45.0
export var enable_slope_resistance := true
export(float, 0, 1) var slope_resistance_factor := 0.4  # Reduced for agile character
export(float, 0, 90) var min_resistance_angle_degrees := 25.0  # Only resist on steeper slopes

# State
var horizontal_velocity := Vector3.ZERO
var _floor_normal := Vector3.UP  # Cached floor normal for alignment
var wish_direction := Vector3.ZERO

# External Velocity State
var external_velocity := Vector3.ZERO
var external_source_is_static := true

# Tank Turn State
var camera_input_timer := 0.0
var is_tank_turn_mode := true
var current_turn_time := 0.0

func _ready() -> void:
	if not tank_turn_curve:
		var curve_path = "res://data/curves/Exponential.tres"
		if ResourceLoader.exists(curve_path):
			tank_turn_curve = load(curve_path)
			
			tank_turn_curve = load(curve_path)
			
	if not move_response_curve:
		var curve_path = "res://data/curves/Exponential.tres"
		if ResourceLoader.exists(curve_path):
			move_response_curve = load(curve_path)

	if not camera_response_curve:
		var curve_path = "res://data/curves/Exponential.tres"
		if ResourceLoader.exists(curve_path):
			camera_response_curve = load(curve_path)

func set_external_velocity(v: Vector3) -> void:
	external_velocity = v

func set_external_source_is_static(is_static: bool) -> void:
	external_source_is_static = is_static

func integrate_external_velocity(delta: float) -> Vector3:
	if external_velocity.length() < 0.001:
		external_velocity = Vector3.ZERO
		return Vector3.ZERO
	external_velocity = external_velocity.linear_interpolate(Vector3.ZERO, external_decay_rate * delta)
	return external_velocity

# --- SLOPE HANDLING (from Terrestrial Characters) ---

func set_floor_normal(normal: Vector3) -> void:
	"""Called by PlayerControllerV2 after move_and_slide to update floor info."""
	_floor_normal = normal

func align_to_floor(vector: Vector3) -> Vector3:
	"""Rotates a horizontal vector to lie along the floor plane.
	Prevents lateral drift when moving sideways on slopes."""
	if _floor_normal == Vector3.UP or _floor_normal.length_squared() < 0.9:
		return vector
	
	# Cross product trick: project vector onto floor plane
	var cross = Vector3.UP.cross(vector)
	if cross.length_squared() < 0.001:
		return vector
	return cross.cross(_floor_normal).normalized() * vector.length()

func apply_slope_resistance(velocity: Vector3) -> Vector3:
	"""Slows movement when going uphill past min_resistance_angle."""
	if not enable_slope_resistance:
		return velocity
	
	# Only apply if moving uphill (velocity has upward component)
	if velocity.dot(Vector3.UP) <= 0:
		return velocity
	
	var floor_angle = _floor_normal.angle_to(Vector3.UP)
	var min_angle = deg2rad(min_resistance_angle_degrees)
	var max_angle = deg2rad(floor_max_angle_degrees)
	
	if floor_angle < min_angle:
		return velocity
	
	# Calculate resistance based on how steep the slope is
	var resistance = clamp(
		(floor_angle - min_angle) / (max_angle - min_angle) * slope_resistance_factor,
		0.0, 1.0
	)
	
	# Slide out the uphill component proportionally
	var cross_vector = Vector3.UP.cross(_floor_normal).normalized()
	if cross_vector.length_squared() < 0.001:
		return velocity
	
	var slided = velocity.slide(cross_vector)
	return velocity - slided * resistance

func update_tank_mode(dt: float, mouse_delta: Vector2, _move_vec: Vector2, _jump: bool, _sprint: bool) -> void:
	if mouse_delta.length() > 0.1:
		camera_input_timer = 0.0
		is_tank_turn_mode = false
	else:
		# Timer counts up as long as mouse is still.
		# This allows returning to tank mode even while moving.
		camera_input_timer += dt
		
		if camera_input_timer >= tank_turn_transition_time:
			is_tank_turn_mode = true
func get_tank_yaw_delta(dt: float, move_vec: Vector2) -> float:
	if is_tank_turn_mode:
		# Acceleration curve logic
		if abs(move_vec.x) > 0.01:
			current_turn_time += dt
		else:
			current_turn_time = 0.0
			
		current_turn_time = clamp(current_turn_time, 0.0, tank_turn_ramp_time)
		
		var speed_factor := 1.0
		if tank_turn_curve and tank_turn_ramp_time > 0:
			speed_factor = tank_turn_curve.interpolate(current_turn_time / tank_turn_ramp_time)
			
		var multiplier = 1.0
		# Invert rotation direction when moving backward (move_vec.y < 0)
		if move_vec.y < -0.01:
			multiplier = -1.0
		elif abs(move_vec.y) < 0.01:
			# If strafing (no forward/backward), turn slower and don't invert
			multiplier = strafe_turn_multiplier
			
		return move_vec.x * tank_turn_speed * speed_factor * dt * multiplier
	
	current_turn_time = 0.0
	return 0.0

func get_full_snapshot() -> Dictionary:
	return {
		"horizontal_velocity": [horizontal_velocity.x, horizontal_velocity.y, horizontal_velocity.z],
		"external_velocity": [external_velocity.x, external_velocity.y, external_velocity.z],
		"camera_input_timer": camera_input_timer,
		"is_tank_turn_mode": is_tank_turn_mode,
		"current_turn_time": current_turn_time
	}

func restore_snapshot(data: Dictionary) -> void:
	var hv = data.get("horizontal_velocity", [0, 0, 0])
	horizontal_velocity = Vector3(hv[0], hv[1], hv[2])
	var ev = data.get("external_velocity", [0, 0, 0])
	external_velocity = Vector3(ev[0], ev[1], ev[2])
	camera_input_timer = data.get("camera_input_timer", 0.0)
	is_tank_turn_mode = data.get("is_tank_turn_mode", true)
	current_turn_time = data.get("current_turn_time", 0.0)

func process_movement(dt: float, move_vec: Vector2, basis: Basis, sprint: bool, is_on_floor: bool) -> void:
	var target_speed = move_speed * (run_speed_multiplier if sprint else 1.0)
	
	var forward = basis.z
	forward.y = 0.0
	forward = forward.normalized()
	
	var right = basis.x
	
	var lateral_input = 0.0
	if not is_tank_turn_mode:
		lateral_input = move_vec.x
	elif abs(move_vec.y) < 0.01:
		# If in tank mode and NOT moving forward/backward, allow slow strafing
		lateral_input = move_vec.x * strafe_speed_multiplier
		
	var wish_dir = forward * move_vec.y + right * lateral_input
	wish_direction = wish_dir.normalized() if wish_dir.length_squared() > 0.0 else Vector3.ZERO
	wish_dir = wish_direction * target_speed
	
	# Aplicar fricción más agresiva cuando no hay input
	var accel: float
	if wish_dir.length_squared() > 0.0:
		accel = acceleration
		# Reducir control en el aire
		if not is_on_floor:
			accel *= air_control_multiplier
	else:
		accel = ground_friction if is_on_floor else air_friction
	
	horizontal_velocity = horizontal_velocity.move_toward(wish_dir, accel * dt)
	
	# Apply floor alignment when on ground (prevents sideways drift on slopes)
	if is_on_floor and horizontal_velocity.length_squared() > 0.001:
		horizontal_velocity = align_to_floor(horizontal_velocity)
		horizontal_velocity = apply_slope_resistance(horizontal_velocity)
	
	# Forzar a cero solo si no hay input y estamos muy lentos, para evitar micro-movimientos
	if wish_dir.length_squared() == 0.0 and horizontal_velocity.length() < stop_threshold:
		horizontal_velocity = Vector3.ZERO

func get_horizontal_velocity() -> Vector3:
	return horizontal_velocity