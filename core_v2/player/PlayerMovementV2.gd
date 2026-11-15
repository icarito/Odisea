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

# MagRail (PISTA D)
export(float) var rail_drift_max := 0.35
export(float) var rail_drift_recovery := 6.0
export(float) var rail_input_accel := 10.0
export(float) var rail_exit_cooldown := 0.25

# State
var horizontal_velocity := Vector3.ZERO
var _floor_normal := Vector3.UP # Cached floor normal for alignment
var wish_direction := Vector3.ZERO
# FD-320: ticks de vuelo balistico pendientes de confirmar despegue (>0 = lanzado).
var _ballistic_ticks := 0
const BALLISTIC_LIFTOFF_TICKS := 4
var _roll_timer := 0.0
var _roll_direction := Vector3.ZERO

# MagRail State
var is_on_rail := false
var rail_node_path := ""
var _rail_offset := 0.0
var _rail_direction := 1.0
var _rail_speed := 0.0
var _rail_drift_offset := 0.0
var _rail_cooldown := 0.0
var _rail_last_tangent := Vector3.FORWARD
var _rail_last_platform_vel := Vector3.ZERO

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

func can_engage_rail() -> bool:
	return not is_on_rail and _rail_cooldown <= 0.0

func tick_rail_cooldown(dt: float) -> void:
	if _rail_cooldown > 0.0:
		_rail_cooldown = max(0.0, _rail_cooldown - dt)

func enter_rail(rail: Node, world_pos: Vector3, current_vel: Vector3) -> Dictionary:
	var info: Dictionary = rail.get_closest_point_info(world_pos)
	if info.empty():
		return {}
	var base_tan: Vector3 = info["tangent"]
	var dir_sign := 1.0
	if rail.bidirectional:
		var ref_vel := Vector3(current_vel.x, 0.0, current_vel.z)
		if ref_vel.length_squared() < 0.05:
			ref_vel = wish_direction
		if ref_vel.length_squared() >= 0.01 and ref_vel.dot(Vector3(base_tan.x, 0.0, base_tan.z)) < 0.0:
			dir_sign = -1.0
	var horiz_speed := Vector3(current_vel.x, 0.0, current_vel.z).length()
	var start_speed: float = clamp(
		max(horiz_speed * rail.speed_multiplier, rail.min_rail_speed),
		rail.min_rail_speed,
		rail.max_rail_speed
	)
	is_on_rail = true
	rail_node_path = String(rail.get_path())
	_rail_offset = float(info["offset"])
	_rail_direction = dir_sign
	_rail_speed = start_speed
	_rail_drift_offset = 0.0
	_rail_last_tangent = (base_tan * dir_sign).normalized()
	_rail_last_platform_vel = rail.get_platform_velocity_at(info["world_pos"], 0.0)
	_ballistic_ticks = 0
	_roll_timer = 0.0
	horizontal_velocity = Vector3(_rail_last_tangent.x, 0.0, _rail_last_tangent.z) * _rail_speed
	return {
		"offset": _rail_offset,
		"direction": _rail_direction,
		"speed": _rail_speed,
		"target_pos": info["world_pos"] + Vector3.UP * rail.player_offset_y
	}

func exit_rail(cooldown: float = -1.0) -> void:
	is_on_rail = false
	rail_node_path = ""
	_rail_drift_offset = 0.0
	_rail_cooldown = rail_exit_cooldown if cooldown < 0.0 else cooldown

func step_rail(dt: float, rail: Node, move_vec: Vector2, _wish_dir: Vector3, jump_pressed: bool) -> Dictionary:
	if not is_on_rail:
		return {"active": false, "exit_reason": "none", "launch_velocity": Vector3.ZERO}
	if not is_instance_valid(rail):
		var fallback_vel := _rail_last_tangent * _rail_speed + _rail_last_platform_vel
		exit_rail()
		add_launch_velocity(fallback_vel)
		return {"active": false, "exit_reason": "lost", "launch_velocity": fallback_vel}

	var cur_sample: Dictionary = rail.sample_at_offset(_rail_offset, _rail_direction)
	var cur_pos: Vector3 = cur_sample.get("world_pos", Vector3.ZERO)
	_rail_last_platform_vel = rail.get_platform_velocity_at(cur_pos, dt)
	var cur_tan: Vector3 = cur_sample.get("tangent", _rail_last_tangent)
	_rail_last_tangent = cur_tan

	if jump_pressed:
		var jump_launch: Vector3 = cur_tan * _rail_speed + _rail_last_platform_vel
		exit_rail()
		add_launch_velocity(jump_launch)
		return {"active": false, "exit_reason": "jump", "launch_velocity": jump_launch}

	var length: float = rail.get_curve_length()
	var closed: bool = rail.is_curve_closed()
	_rail_offset += _rail_direction * _rail_speed * dt
	if closed and length > 0.001:
		_rail_offset = fposmod(_rail_offset, length)
	elif _rail_offset <= 0.0 or _rail_offset >= length:
		_rail_offset = clamp(_rail_offset, 0.0, length)
		var end_launch: Vector3 = cur_tan * _rail_speed + _rail_last_platform_vel
		exit_rail()
		add_launch_velocity(end_launch)
		return {"active": false, "exit_reason": "end", "launch_velocity": end_launch}

	var sample: Dictionary = rail.sample_at_offset(_rail_offset, _rail_direction)
	if sample.empty():
		var empty_launch: Vector3 = cur_tan * _rail_speed + _rail_last_platform_vel
		exit_rail()
		add_launch_velocity(empty_launch)
		return {"active": false, "exit_reason": "end", "launch_velocity": empty_launch}

	var target_speed: float = clamp(
		move_speed * run_speed_multiplier * rail.speed_multiplier,
		rail.min_rail_speed,
		rail.max_rail_speed
	)
	if move_vec.y < -0.1:
		target_speed = clamp(target_speed + 2.0 * (-move_vec.y), rail.min_rail_speed, rail.max_rail_speed)
	elif move_vec.y > 0.1:
		target_speed = clamp(target_speed - 3.0 * move_vec.y, rail.min_rail_speed, rail.max_rail_speed)

	var curvature: float = float(sample.get("curvature", 0.0))
	var drift_force: float = curvature * rail.drift_factor * 0.55 - move_vec.x * 0.25
	_rail_drift_offset += drift_force * dt * 4.0
	_rail_drift_offset = lerp(_rail_drift_offset, 0.0, clamp(rail_drift_recovery * dt * 0.5, 0.0, 1.0))
	_rail_drift_offset = clamp(_rail_drift_offset, -rail_drift_max, rail_drift_max)

	# Penalizacion suave por derrape excesivo en curva sin contrapeso.
	var curve_drag: float = abs(curvature) * abs(_rail_drift_offset) * 2.5
	target_speed = max(rail.min_rail_speed, target_speed - curve_drag)
	_rail_speed = move_toward(_rail_speed, target_speed, rail.rail_inertia * dt)

	var next_tan: Vector3 = sample["tangent"]
	_rail_last_tangent = next_tan
	var lateral: Vector3 = next_tan.cross(Vector3.UP)
	if lateral.length_squared() > 0.0001:
		lateral = lateral.normalized()
	else:
		lateral = Vector3.RIGHT

	var target_pos: Vector3 = sample["world_pos"] + Vector3.UP * rail.player_offset_y + lateral * _rail_drift_offset
	var rail_vel: Vector3 = next_tan * _rail_speed + _rail_last_platform_vel
	horizontal_velocity = Vector3(rail_vel.x, 0.0, rail_vel.z)
	var horiz_tan := Vector3(next_tan.x, 0.0, next_tan.z)
	if horiz_tan.length_squared() > 0.0001:
		wish_direction = horiz_tan.normalized()

	return {
		"active": true,
		"target_pos": target_pos,
		"tangent": next_tan,
		"velocity": rail_vel,
		"drift": _rail_drift_offset
	}

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
		"_roll_direction": [_roll_direction.x, _roll_direction.y, _roll_direction.z],
		"is_on_rail": is_on_rail,
		"rail_node_path": rail_node_path,
		"_rail_offset": _rail_offset,
		"_rail_direction": _rail_direction,
		"_rail_speed": _rail_speed,
		"_rail_drift_offset": _rail_drift_offset,
		"_rail_cooldown": _rail_cooldown,
		"_rail_last_tangent": [_rail_last_tangent.x, _rail_last_tangent.y, _rail_last_tangent.z],
		"_rail_last_platform_vel": [_rail_last_platform_vel.x, _rail_last_platform_vel.y, _rail_last_platform_vel.z]
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
	is_on_rail = bool(data.get("is_on_rail", false))
	rail_node_path = str(data.get("rail_node_path", ""))
	_rail_offset = float(data.get("_rail_offset", 0.0))
	_rail_direction = float(data.get("_rail_direction", 1.0))
	_rail_speed = float(data.get("_rail_speed", 0.0))
	_rail_drift_offset = float(data.get("_rail_drift_offset", 0.0))
	_rail_cooldown = float(data.get("_rail_cooldown", 0.0))
	var rlt = data.get("_rail_last_tangent", [0, 0, -1])
	_rail_last_tangent = Vector3(rlt[0], rlt[1], rlt[2])
	var rlp = data.get("_rail_last_platform_vel", [0, 0, 0])
	_rail_last_platform_vel = Vector3(rlp[0], rlp[1], rlp[2])

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
