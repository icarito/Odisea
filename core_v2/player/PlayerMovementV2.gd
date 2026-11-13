extends Node

# PlayerMovementV2.gd - Componente para movimiento horizontal suavizado

export(float) var acceleration := 30.0
export(float) var ground_friction := 30.0
export(float) var air_friction := 10.0
export(float) var move_speed := 5.0
export(float) var run_speed_multiplier := 1.8
export(float) var crouch_speed_multiplier := 0.5
export(float, 0.0, 1.0) var ice_movement_multiplier := 1.0
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
export(float, 0.0, 1.0) var tank_strafe_blend := 0.5 # 0.0 = pure strafe, 1.0 = pure tank turn
export(float, 0.0, 1.0) var tank_turn_zone_end := 0.0 # 0.0 = continuous blend, 1.0 = binary tank turn, 0.75 = Pilot target
export(float, 0.0, 1.0) var diagonal_turn_blend := 0.5 # Turning reduction multiplier when moving diagonally
export(float, 0.0, 1.0) var stationary_turn_speed_multiplier := 1.0
export(float, 0.0, 1.0) var tank_turn_stationary_axis_deadzone := 0.15

# Slope Handling (inspired by Terrestrial Characters)
export(float, 0, 90) var floor_max_angle_degrees := 45.0
export var enable_slope_resistance := true
export(float, 0, 1) var slope_resistance_factor := 0.2 # Reduced for agile character
export(float, 0, 90) var min_resistance_angle_degrees := 25.0 # Only resist on steeper slopes

# FD-320: Landing Roll / Slide (Mirror's Edge + Mario 64 momentum conservation)
export(float) var landing_roll_duration := 0.48
export(float) var landing_roll_min_fall_vy := -6.0
export(float) var landing_roll_vertical_conversion := 0.45
export(float) var landing_roll_min_speed := 8.5
export(float) var landing_roll_max_speed := 13.5
export(float) var landing_roll_friction := 3.5

# State
var horizontal_velocity := Vector3.ZERO
var _floor_normal := Vector3.UP # Cached floor normal for alignment
var wish_direction := Vector3.ZERO
# FD-320: ticks de vuelo balistico pendientes de confirmar despegue (>0 = lanzado).
var _ballistic_ticks := 0
const BALLISTIC_LIFTOFF_TICKS := 4
var _roll_timer := 0.0
var _roll_direction := Vector3.ZERO

# External Velocity State
var external_velocity := Vector3.ZERO
var external_source_is_static := true

# Tank Turn State
var camera_input_timer := 0.0
var is_tank_turn_mode := true
var current_turn_time := 0.0
var _mouse_used_this_move := false

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

# FD-320: una maquina le transfiere momentum horizontal al jugador. Mientras siga en el
# aire no hay friccion de aire: el momentum se conserva y el input solo redirige.
func add_launch_velocity(v: Vector3) -> void:
	horizontal_velocity += Vector3(v.x, 0.0, v.z)
	_ballistic_ticks = BALLISTIC_LIFTOFF_TICKS

func start_landing_roll(forward_dir: Vector3, impact_vy: float) -> void:
	var dir := Vector3(forward_dir.x, 0.0, forward_dir.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3(horizontal_velocity.x, 0.0, horizontal_velocity.z)
	if dir.length_squared() < 0.0001:
		dir = Vector3.BACK
	dir = dir.normalized()
	_roll_direction = dir
	_roll_timer = landing_roll_duration
	var h_speed := Vector3(horizontal_velocity.x, 0.0, horizontal_velocity.z).length()
	var converted := max(0.0, -impact_vy) * landing_roll_vertical_conversion
	var roll_speed := clamp(
		max(h_speed + converted * 0.5, landing_roll_min_speed + converted * 0.25),
		landing_roll_min_speed,
		landing_roll_max_speed
	)
	horizontal_velocity = dir * roll_speed
	_ballistic_ticks = 0

func is_rolling() -> bool:
	return _roll_timer > 0.0

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

func get_floor_normal() -> Vector3:
	return _floor_normal

func align_to_floor(vector: Vector3) -> Vector3:
	"""Rotates a horizontal vector to lie along the floor plane.
	Prevents lateral drift when moving sideways on slopes."""
	if _floor_normal == Vector3.UP or _floor_normal.length_squared() < 0.9:
		return vector

	var cross = Vector3.UP.cross(vector)
	if cross.length_squared() < 0.001:
		return vector

	var aligned_vector = cross.cross(_floor_normal).normalized() * vector.length()
	return aligned_vector

func apply_slope_resistance(velocity: Vector3) -> Vector3:
	"""Slows movement when going uphill past min_resistance_angle."""
	if not enable_slope_resistance:
		return velocity

	if velocity.dot(Vector3.UP) <= 0:
		return velocity

	var angle = rad2deg(acos(velocity.normalized().dot(Vector3.UP)))
	if angle < min_resistance_angle_degrees:
		return velocity

	var resistance = velocity * (1.0 - slope_resistance_factor)
	return resistance

func update_tank_mode(dt: float, mouse_delta: Vector2, _move_vec: Vector2, _jump: bool, _sprint: bool, hardware_mouse: bool = false) -> void:
	if mouse_delta.length() > 0.1:
		camera_input_timer = 0.0
		is_tank_turn_mode = false
		# Only lock tank turn through movement for real hardware mouse, not joystick
		if hardware_mouse:
			_mouse_used_this_move = true
	else:
		# If mouse was used during this movement, keep timer reset while still moving.
		if _mouse_used_this_move and _move_vec.length() > 0.1:
			camera_input_timer = 0.0
		else:
			camera_input_timer += dt
			# Clear the flag once we've stopped moving
			if _move_vec.length() <= 0.1:
				_mouse_used_this_move = false
		
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
			
		var multiplier = -1.0
		var active_blend = tank_strafe_blend
		var turn_speed := tank_turn_speed
		var is_stationary_turn := abs(move_vec.y) <= tank_turn_stationary_axis_deadzone
		if is_stationary_turn:
			turn_speed *= stationary_turn_speed_multiplier
		
		# Standard Tank Turn: Left/Right rotate character relative to its own axis.
		# No inversion in reverse (classic tank behavior).
		if not is_stationary_turn: # Forward or backward intent beyond the stick deadzone.
			multiplier = -1.0
			active_blend = diagonal_turn_blend
			
		return move_vec.x * turn_speed * speed_factor * active_blend * dt * multiplier
	
	current_turn_time = 0.0
	return 0.0

func get_full_snapshot() -> Dictionary:
	return {
		"horizontal_velocity": [horizontal_velocity.x, horizontal_velocity.y, horizontal_velocity.z],
		"external_velocity": [external_velocity.x, external_velocity.y, external_velocity.z],
		"camera_input_timer": camera_input_timer,
		"is_tank_turn_mode": is_tank_turn_mode,
		"current_turn_time": current_turn_time,
		"_mouse_used_this_move": _mouse_used_this_move,
		"_ballistic_ticks": _ballistic_ticks,
		"_roll_timer": _roll_timer,
		"_roll_direction": [_roll_direction.x, _roll_direction.y, _roll_direction.z]
	}

func restore_snapshot(data: Dictionary) -> void:
	var hv = data.get("horizontal_velocity", [0, 0, 0])
	horizontal_velocity = Vector3(hv[0], hv[1], hv[2])
	var ev = data.get("external_velocity", [0, 0, 0])
	external_velocity = Vector3(ev[0], ev[1], ev[2])
	camera_input_timer = data.get("camera_input_timer", 0.0)
	is_tank_turn_mode = data.get("is_tank_turn_mode", true)
	current_turn_time = data.get("current_turn_time", 0.0)
	_mouse_used_this_move = data.get("_mouse_used_this_move", false)
	_ballistic_ticks = int(data.get("_ballistic_ticks", 0))
	_roll_timer = float(data.get("_roll_timer", 0.0))
	var rd = data.get("_roll_direction", [0, 0, 0])
	_roll_direction = Vector3(rd[0], rd[1], rd[2])

static func tank_lateral_input(x: float, zone_end: float, blend: float) -> float:
	var ax := abs(x)
	if ax <= zone_end:
		return 0.0
	else:
		var ramp := clamp(inverse_lerp(zone_end, 1.0, ax), 0.0, 1.0)
		return sign(x) * ramp * (1.0 - blend)

func process_movement(dt: float, move_vec: Vector2, basis: Basis, sprint: bool, is_on_floor: bool, crouch: bool = false) -> void:
	var speed_multiplier = 1.0
	if crouch:
		speed_multiplier = crouch_speed_multiplier
	elif sprint:
		speed_multiplier = run_speed_multiplier

	var target_speed = move_speed * speed_multiplier * ice_movement_multiplier
	
	var forward = - basis.z
	forward.y = 0.0
	forward = forward.normalized()
	
	var right = basis.x
	
	var lateral_input = move_vec.x
	var input_strength := 1.0
	if is_tank_turn_mode:
		lateral_input = tank_lateral_input(move_vec.x, tank_turn_zone_end, tank_strafe_blend)
		input_strength = min(Vector2(lateral_input, move_vec.y).length(), 1.0)
		
	var wish_dir = forward * (-move_vec.y) + right * lateral_input
	wish_direction = wish_dir.normalized() if wish_dir.length_squared() > 0.0 else Vector3.ZERO
	wish_dir = wish_direction * target_speed * input_strength
	
	if _roll_timer > 0.0:
		if not is_on_floor:
			_roll_timer = 0.0
		else:
			_roll_timer = max(0.0, _roll_timer - dt)
			if wish_direction.length_squared() > 0.001:
				_roll_direction = _roll_direction.linear_interpolate(wish_direction, min(1.0, 6.0 * dt)).normalized()
			wish_direction = _roll_direction
			var flat_speed := Vector3(horizontal_velocity.x, 0.0, horizontal_velocity.z).length()
			var floor_speed := move_speed * run_speed_multiplier * ice_movement_multiplier
			var next_roll_speed := max(floor_speed, flat_speed - landing_roll_friction * dt)
			horizontal_velocity = _roll_direction * next_roll_speed
			if horizontal_velocity.length_squared() > 0.001:
				horizontal_velocity = align_to_floor(horizontal_velocity)
				horizontal_velocity = apply_slope_resistance(horizontal_velocity)
			return

	# Aplicar fricción más agresiva cuando no hay input
	var accel: float
	if wish_dir.length_squared() > 0.0:
		accel = acceleration
		# Reducir control en el aire
		if not is_on_floor:
			accel *= air_control_multiplier
	else:
		accel = ground_friction if is_on_floor else air_friction
	
	if _ballistic_ticks > 0:
		# El piso del tick de lanzamiento todavia figura como contacto: se le dan unos
		# ticks para despegar antes de dar el vuelo por terminado.
		if is_on_floor:
			_ballistic_ticks -= 1
		var carried_speed: float = horizontal_velocity.length()
		if wish_dir.length_squared() == 0.0:
			accel = 0.0
		elif carried_speed > wish_dir.length():
			wish_dir = wish_direction * carried_speed
	horizontal_velocity = horizontal_velocity.move_toward(wish_dir, accel * dt)
	# print("[PlayerMovementV2] h_vel=%s" % horizontal_velocity)

	
	# Apply floor alignment when on ground (prevents sideways drift on slopes)
	if is_on_floor and horizontal_velocity.length_squared() > 0.001:
		horizontal_velocity = align_to_floor(horizontal_velocity)
		horizontal_velocity = apply_slope_resistance(horizontal_velocity)
	
	# Forzar a cero solo si no hay input y estamos muy lentos, para evitar micro-movimientos
	if wish_dir.length_squared() == 0.0 and horizontal_velocity.length() < stop_threshold:
		horizontal_velocity = Vector3.ZERO

func get_horizontal_velocity() -> Vector3:
	return horizontal_velocity

func set_ice_movement_multiplier(value: float) -> void:
	ice_movement_multiplier = clamp(value, 0.0, 1.0)
