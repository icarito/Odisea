# /mnt/sdd/home/icarito/Proyectos/Odisea_Game/src/core_v2/sim/SideScrollLogicV2.gd
extends Node

# Componente para manejar el estado y las restricciones del modo 2.5D

# --- CAMERA SETTINGS ---
export(float) var lerp_speed := 2.5
export(float) var target_fov := 45.0
export(float) var target_pitch_deg := 0.0
export(float) var target_y_offset := 0.0
export(float) var target_spring_length := 7.0
export(float) var camera_smoothing := 4.0
export(float) var zoom_smoothing := 2.0
export(float) var min_rig_height := 0.5
export(float) var spring_min := 2.0
export(float) var spring_max := 20.0

# --- DEPTH MOTION ZOOM ---
export(float) var depth_zoom_factor := 0.5 # How much to zoom based on depth distance
export(float) var depth_zoom_max := 3.0 # Max extra zoom from depth

# --- LOOK-AHEAD (Rule of Thirds) ---
export(float) var lookahead_angle := 15.0 # Camera yaw offset for rule of thirds
export(float) var lookahead_speed := 2.0 # How fast camera rotates to look ahead
export(float) var turn_delay := 2.0 # Delay in seconds before camera follows turn

# --- MANUAL CAMERA CONTROL ---
export(float) var mouse_sensitivity := 0.002 # Sensitivity for manual camera control (radians per pixel)
export(float) var manual_yaw_limit := 15.0 # Max manual yaw offset in degrees
export(float) var manual_pitch_limit := 15.0 # Max manual pitch offset in degrees
export(float) var manual_return_speed := 2.0 # Speed to return to auto position
export(float) var manual_decay_delay := 2.0 # Seconds of no input before returning


var is_active := false
var lock_axis := 0 # 0: None, 1: X, 2: Z
var lock_value := 0.0
var invert_side := false
var transition_alpha := 0.0
var allow_depth := false
var current_target_lock_value := 0.0
var current_target_spring_length := 7.0
var current_target_fov := 70.0
var current_target_y_offset := 0.0

# Camera tracking state
var virtual_center := Vector3.ZERO
var lagging_center := Vector3.ZERO
var facing_sign := 1.0

# Look-ahead state (simplified)
var camera_yaw := 0.0 # Current camera yaw offset
var target_camera_yaw := 0.0 # Desired camera yaw based on facing
var time_since_turn := 0.0 # Time elapsed since last direction change

# Manual camera control state
var manual_yaw := 0.0 # Manual yaw offset (from mouse)
var manual_pitch := 0.0 # Manual pitch offset (from mouse)
var time_since_input := 0.0 # Time since last manual input

# Depth zoom smoothing
var current_depth_zoom := 0.0 # Current applied depth zoom (smoothed)

var _first_frame := true

func enter_mode(axis: int, value: float, invert: bool, current_pos_val: float = -1e9, depth_allowed: bool = false):
	var was_inactive = not is_active
	var axis_changed = axis != lock_axis
	var invert_changed = invert != invert_side
	var entering_constrained = allow_depth and not depth_allowed # Going from depth to no-depth
	
	# Hard reset ONLY when:
	# - Entering from 3D mode (was_inactive)
	# - Changing axis (X to Z or vice versa)
	# - Flipping orientation (invert)
	var needs_hard_reset = was_inactive or axis_changed or invert_changed
	
	if needs_hard_reset:
		# Full reset for clean state
		if current_pos_val > -1e8:
			current_target_lock_value = current_pos_val
		virtual_center = Vector3.ZERO
		lagging_center = Vector3.ZERO
		_first_frame = true
		facing_sign = 1.0
		time_since_turn = turn_delay
		manual_yaw = 0.0
		manual_pitch = 0.0
		time_since_input = manual_decay_delay + 1.0
	elif entering_constrained and current_pos_val > -1e8:
		# When going from depth-allowed to constrained,
		# start the lock value from where the player IS now,
		# so they don't get yanked to the new zone's lock value
		current_target_lock_value = current_pos_val
	
	# Always update these
	lock_axis = axis
	lock_value = value
	invert_side = invert
	is_active = true
	allow_depth = depth_allowed
	lock_axis = axis
	lock_value = value
	invert_side = invert
	
	current_target_spring_length = target_spring_length
	current_target_fov = target_fov
	current_target_y_offset = target_y_offset

func exit_mode():
	is_active = false

func step(dt: float):
	var target_alpha = 1.0 if is_active else 0.0
	if transition_alpha != target_alpha:
		var step_val = lerp_speed * dt
		if transition_alpha < target_alpha:
			transition_alpha = min(transition_alpha + step_val, target_alpha)
		else:
			transition_alpha = max(transition_alpha - step_val, target_alpha)
	
	# Smoothly transition internal parameters even when already active
	if is_active:
		current_target_lock_value = lerp(current_target_lock_value, lock_value, lerp_speed * dt)
		current_target_spring_length = lerp(current_target_spring_length, target_spring_length, lerp_speed * dt)
		current_target_fov = lerp(current_target_fov, target_fov, lerp_speed * dt)
		current_target_y_offset = lerp(current_target_y_offset, target_y_offset, lerp_speed * dt)

func get_smooth_alpha() -> float:
	# Cubic easing (smoothstep): 3t^2 - 2t^3
	return transition_alpha * transition_alpha * (3.0 - 2.0 * transition_alpha)

func get_constrained_input(move_vec: Vector2) -> Vector2:
	# Si permitimos profundidad, devolvemos el vector completo
	if allow_depth:
		return move_vec
	
	# Lo que bloqueamos es la profundidad (Y del Vector2) para mantener el plano.
	# Pero lo hacemos gradualmente usando transition_alpha para evitar tirones.
	var constrained = Vector2(move_vec.x, 0.0)
	return move_vec.linear_interpolate(constrained, get_smooth_alpha())

func apply_spatial_constraints(body: KinematicBody):
	if transition_alpha <= 0 or allow_depth: return
	
	var pos = body.global_transform.origin
	var s_alpha = get_smooth_alpha()
	
	if lock_axis == 2: # LOCK Z
		# Usamos lerp para que la entrada al eje sea suave
		pos.z = lerp(pos.z, current_target_lock_value, s_alpha)
	elif lock_axis == 1: # LOCK X
		pos.x = lerp(pos.x, current_target_lock_value, s_alpha)
	
	body.global_transform.origin = pos

func get_target_basis() -> Basis:
	var target_basis = Basis.IDENTITY
	
	# Apply base pitch (rig pitch)
	target_basis = target_basis.rotated(Vector3.RIGHT, deg2rad(target_pitch_deg))

	# Apply profile constraint rotation
	if lock_axis == 2: # Z blocked
		if invert_side:
			target_basis = target_basis.rotated(Vector3.UP, PI)
	elif lock_axis == 1: # X blocked
		target_basis = Basis(Vector3.UP, -PI / 2.0) * target_basis
		if invert_side:
			target_basis = target_basis.rotated(Vector3.UP, PI)
	
	# Apply manual control (from mouse) on top
	target_basis = target_basis.rotated(Vector3.UP, manual_yaw)
	target_basis = target_basis.rotated(target_basis.x, manual_pitch)
	
	return target_basis

func calculate_camera_pos(player_pos: Vector3, dt: float) -> Vector3:
	if _first_frame:
		virtual_center = player_pos
		lagging_center = player_pos
		_first_frame = false
		
		# Apply lock immediately on first frame
		if lock_axis == 2:
			lagging_center.z = current_target_lock_value
			virtual_center.z = current_target_lock_value
		elif lock_axis == 1:
			lagging_center.x = current_target_lock_value
			virtual_center.x = current_target_lock_value
		
		return lagging_center
	
	# Smooth follow player
	virtual_center = virtual_center.linear_interpolate(player_pos, camera_smoothing * dt)
	
	# Apply axis lock (unless depth is allowed)
	if not allow_depth:
		if lock_axis == 2:
			virtual_center.z = current_target_lock_value
		elif lock_axis == 1:
			virtual_center.x = current_target_lock_value
	
	# Lag for smoothness
	lagging_center = lagging_center.linear_interpolate(virtual_center, camera_smoothing * dt)
	
	# Safety height check
	if lagging_center.y < min_rig_height:
		lagging_center.y = min_rig_height
	
	return lagging_center

func get_depth_zoom_offset(player_pos: Vector3) -> float:
	"""Calculate zoom offset based on player distance from lock plane (depth motion areas)."""
	var target_zoom = 0.0
	
	if allow_depth:
		# Calculate distance from lock plane
		var depth_distance = 0.0
		if lock_axis == 2: # Z locked, measure Z distance
			depth_distance = abs(player_pos.z - lock_value)
		elif lock_axis == 1: # X locked, measure X distance
			depth_distance = abs(player_pos.x - lock_value)
		
		# Scale and clamp the zoom offset
		target_zoom = min(depth_distance * depth_zoom_factor, depth_zoom_max)
	
	# Smooth interpolation to avoid zoom jumps
	var dt = get_physics_process_delta_time()
	if dt > 0:
		current_depth_zoom = lerp(current_depth_zoom, target_zoom, zoom_smoothing * dt)
	
	return current_depth_zoom

func get_cam_rotation() -> Vector3:
	"""Returns Euler angles for local camera rotation (look-ahead yaw)."""
	# Calculate target based on facing direction (rule of thirds)
	target_camera_yaw = deg2rad(facing_sign * lookahead_angle)
	
	# Apply turn delay: camera rotates slowly right after direction change
	var effective_speed = lookahead_speed
	if time_since_turn < turn_delay:
		effective_speed *= 0.1 # Very slow during delay period (gives weight to turn)
	
	# Smoothly rotate camera toward target
	var dt = get_physics_process_delta_time()
	if dt > 0:
		camera_yaw = lerp(camera_yaw, target_camera_yaw, effective_speed * dt)
	
	# Decay manual input after delay
	time_since_input += dt
	if time_since_input > manual_decay_delay:
		manual_yaw = lerp(manual_yaw, 0.0, manual_return_speed * dt)
		manual_pitch = lerp(manual_pitch, 0.0, manual_return_speed * dt)
	
	return Vector3(0.0, camera_yaw, 0.0)

func get_zoom_offset(_speed: float) -> float:
	return 0.0 # Simplified: no velocity-based zoom

func update_facing(move_x: float, dt: float):
	"""Update facing direction and reset turn timer when direction changes."""
	if abs(move_x) > 0.1:
		var new_sign = sign(move_x)
		if new_sign != facing_sign:
			facing_sign = new_sign
			time_since_turn = 0.0 # Reset delay timer on turn
	
	# Increment timer to track time since last turn
	time_since_turn += dt

func apply_pan(mouse_delta: Vector2):
	"""Apply manual camera control from mouse input."""
	if mouse_delta.length_squared() < 0.01:
		return # Ignore extremely small noise
	
	# Reset input timer
	time_since_input = 0.0
	
	# Apply yaw (horizontal look)
	manual_yaw -= mouse_delta.x * mouse_sensitivity
	manual_yaw = clamp(manual_yaw, deg2rad(-manual_yaw_limit), deg2rad(manual_yaw_limit))
	
	# Apply pitch (vertical look)
	manual_pitch -= mouse_delta.y * mouse_sensitivity
	manual_pitch = clamp(manual_pitch, deg2rad(-manual_pitch_limit), deg2rad(manual_pitch_limit))

func get_full_snapshot() -> Dictionary:
	return {
		"active": is_active,
		"alpha": transition_alpha,
		"axis": lock_axis,
		"val": lock_value,
		"inv": invert_side,
		"tsl": target_spring_length,
		"vc": [virtual_center.x, virtual_center.y, virtual_center.z],
		"lc": [lagging_center.x, lagging_center.y, lagging_center.z],
		"cam_yaw": camera_yaw,
		"fs": facing_sign,
		"tst": time_since_turn,
		"my": manual_yaw,
		"mp": manual_pitch,
		"tsi": time_since_input,
		"cdz": current_depth_zoom,
		"ff": _first_frame
	}

func restore_snapshot(data: Dictionary):
	is_active = data.get("active", false)
	transition_alpha = data.get("alpha", 0.0)
	lock_axis = data.get("axis", 0)
	lock_value = data.get("val", 0.0)
	invert_side = data.get("inv", false)
	target_spring_length = data.get("tsl", target_spring_length)
	
	if data.has("vc"):
		var vc = data["vc"]
		virtual_center = Vector3(vc[0], vc[1], vc[2])
	if data.has("lc"):
		var lc = data["lc"]
		lagging_center = Vector3(lc[0], lc[1], lc[2])
	
	camera_yaw = data.get("cam_yaw", 0.0)
	facing_sign = data.get("fs", 1.0)
	time_since_turn = data.get("tst", 0.0)
	manual_yaw = data.get("my", 0.0)
	manual_pitch = data.get("mp", 0.0)
	time_since_input = data.get("tsi", 0.0)
	current_depth_zoom = data.get("cdz", 0.0)
	_first_frame = data.get("ff", true)
