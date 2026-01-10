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

# State
var horizontal_velocity := Vector3.ZERO
var wish_direction := Vector3.ZERO

# External Velocity State
var external_velocity := Vector3.ZERO
var external_source_is_static := true

# Tank Turn State
var camera_input_timer := 0.0
var is_tank_turn_mode := true

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

func update_tank_mode(dt: float, mouse_delta: Vector2, move_vec: Vector2, jump: bool, sprint: bool) -> void:
	if mouse_delta.length() > 0.1:
		camera_input_timer = 0.0
		is_tank_turn_mode = false
	else:
		# If in strafing mode, any active movement/action resets the timer
		var is_input_active = move_vec.length() > 0.1 or jump or sprint
		if not is_tank_turn_mode and is_input_active:
			camera_input_timer = 0.0
		else:
			camera_input_timer += dt
		
		if camera_input_timer >= tank_turn_transition_time:
			is_tank_turn_mode = true

func get_tank_yaw_delta(dt: float, move_vec: Vector2) -> float:
	if is_tank_turn_mode:
		var multiplier = 1.0
		# Invert rotation direction when moving backward (move_vec.y > 0)
		if move_vec.y > 0.01:
			multiplier = -1.0
		return move_vec.x * tank_turn_speed * dt * multiplier
	return 0.0

func get_full_snapshot() -> Dictionary:
	return {
		"horizontal_velocity": [horizontal_velocity.x, horizontal_velocity.y, horizontal_velocity.z],
		"external_velocity": [external_velocity.x, external_velocity.y, external_velocity.z],
		"camera_input_timer": camera_input_timer,
		"is_tank_turn_mode": is_tank_turn_mode
	}

func restore_snapshot(data: Dictionary) -> void:
	var hv = data.get("horizontal_velocity", [0, 0, 0])
	horizontal_velocity = Vector3(hv[0], hv[1], hv[2])
	var ev = data.get("external_velocity", [0, 0, 0])
	external_velocity = Vector3(ev[0], ev[1], ev[2])
	camera_input_timer = data.get("camera_input_timer", 0.0)
	is_tank_turn_mode = data.get("is_tank_turn_mode", true)

func process_movement(dt: float, move_vec: Vector2, basis: Basis, sprint: bool, is_on_floor: bool) -> void:
	var target_speed = move_speed * (run_speed_multiplier if sprint else 1.0)
	
	var forward = - basis.z
	forward.y = 0.0
	forward = forward.normalized()
	
	var right = basis.x
	
	var lateral_input = 0.0 if is_tank_turn_mode else move_vec.x
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

	
	# Forzar a cero solo si no hay input y estamos muy lentos, para evitar micro-movimientos
	if wish_dir.length_squared() == 0.0 and horizontal_velocity.length() < stop_threshold:
		horizontal_velocity = Vector3.ZERO

func get_horizontal_velocity() -> Vector3:
	return horizontal_velocity