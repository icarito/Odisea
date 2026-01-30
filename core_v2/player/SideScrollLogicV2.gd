# /mnt/sdd/home/icarito/Proyectos/Odisea_Game/src/core_v2/sim/SideScrollLogicV2.gd
extends Node

# Componente para manejar el estado y las restricciones del modo 2.5D

export(float) var lerp_speed := 3.0 # Slower transition (was 5.0)
export(float) var target_fov := 45.0
export(float) var target_pitch_deg := 0.0
export(float) var target_y_offset := 0.0
export(float) var target_spring_length := 7.0
export(float) var spring_min := 4.0
export(float) var spring_max := 20.0

# Camera Dead Zone and Smoothing
export(float) var deadzone_x := 1.5 # Reset to default (was 4.0)
export(float) var deadzone_y := 0.5
export(float) var camera_smoothing := 4.0 # Faster to keep up (was 2.0)
export(float) var zoom_smoothing := 2.0

# Mouse Pan Settings
export(float) var pan_sensitivity := 0.05
export(float) var pan_sensitivity_y_ratio := 0.5
export(float) var pan_max_offset := 10.0
export(float) var pan_return_speed := 3.0
export(float) var min_rig_height := 0.5

# Refined Tuning
export(float) var yaw_sensitivity := 0.2
export(float) var yaw_return_speed := 2.0
export(float) var turn_slowdown_duration := 0.6 # How long to move slow after turn
export(float) var turn_slowdown_factor := 0.2 # Multiplier for speed during slowdown
export(float) var pitch_sensitivity := 0.2
export(float) var pitch_return_speed := 3.0
export(float) var lookahead_yaw_degrees := 10.0 # Reduced from 15.0
export(float) var velocity_lookahead_factor := 2.0
export(float) var velocity_zoom_factor := 0.5
export(float) var velocity_zoom_smoothing := 2.0
export(float) var manual_input_decay_delay := 2.0 # Wait 2 seconds before returning manual cam


var is_active := false
var lock_axis := 0 # 0: None, 1: X, 2: Z
var lock_value := 0.0
var invert_side := false
var transition_alpha := 0.0

# State for deterministic camera tracking
var virtual_center := Vector3.ZERO
var lagging_center := Vector3.ZERO
var pan_offset := Vector2.ZERO # Deprecated for manual control, but still used for velocity lookahead
var yaw_offset := 0.0
var manual_yaw := 0.0 # Separated manual input
var manual_pitch := 0.0
var facing_sign := 1.0
var _time_since_turn := 0.0
var _time_since_input := 0.0
var _first_frame := true

func enter_mode(axis: int, value: float, invert: bool):
	is_active = true
	lock_axis = axis
	lock_value = value
	invert_side = invert
	_first_frame = true
	_time_since_input = manual_input_decay_delay + 1.0 # Ensure decay is active on enter
	
	# Reset state to prevent "yanking" from previous offsets
	pan_offset = Vector2.ZERO
	yaw_offset = 0.0
	manual_yaw = 0.0
	manual_pitch = 0.0
	facing_sign = 1.0 # Or detect from current velocity if possible? Defaulting to 1.0 is safe-ish.

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

func get_constrained_input(move_vec: Vector2) -> Vector2:
	# Siempre bloqueamos la profundidad (Y del Vector2) para mantener el plano
	return Vector2(move_vec.x, 0.0)

func apply_spatial_constraints(body: KinematicBody):
	if transition_alpha <= 0: return
	
	var pos = body.global_transform.origin
	if lock_axis == 2: # LOCK Z
		# Usamos lerp para que la entrada al eje sea suave
		pos.z = lerp(pos.z, lock_value, transition_alpha)
	elif lock_axis == 1: # LOCK X
		pos.x = lerp(pos.x, lock_value, transition_alpha)
	
	body.global_transform.origin = pos

func get_target_basis() -> Basis:
	var target_basis = Basis.IDENTITY
	
	# Apply Pitch deseado (Base Rig Pitch) - MUST BE FIRST (Local X)
	target_basis = target_basis.rotated(Vector3.RIGHT, deg2rad(target_pitch_deg))

	# 1. Base Rotation (Profile Constraint)
	if lock_axis == 2: # Z blocked
		if invert_side:
			target_basis = target_basis.rotated(Vector3.UP, PI)
	elif lock_axis == 1: # X blocked
		target_basis = Basis(Vector3.UP, -PI / 2.0) * target_basis
		if invert_side:
			target_basis = target_basis.rotated(Vector3.UP, PI)
	
	# 2. Manual Orbit (Rig Rotation)
	# Applied ON TOP of the constrained profile basis
	target_basis = target_basis.rotated(Vector3.UP, manual_yaw)
	target_basis = target_basis.rotated(target_basis.x, manual_pitch) # Pitch locally relative to current yaw
	
	return target_basis

func calculate_camera_pos(player_pos: Vector3, dt: float) -> Vector3:
	if _first_frame:
		virtual_center = player_pos
		lagging_center = player_pos
		pan_offset = Vector2.ZERO
		_first_frame = false
		return lagging_center
	
	# Horizontal tracking (Simple smoothed follow for the virtual center)
	# We'll use the deadzone as a look-ahead offset instead of a gap.
	virtual_center = virtual_center.linear_interpolate(player_pos, camera_smoothing * dt)
	
	if lock_axis == 2:
		virtual_center.z = lock_value
	elif lock_axis == 1:
		virtual_center.x = lock_value
	
	# 1. Update Velocity-based Look-Ahead
	var current_pos = player_pos
	var est_velocity_x = (current_pos.x - virtual_center.x) / dt if dt > 0.001 else 0.0
	var est_velocity_z = (current_pos.z - virtual_center.z) / dt if dt > 0.001 else 0.0
	
	var speed_magnitude = Vector2(est_velocity_x, est_velocity_z).length()
	
	# 2. Rotational Look-Ahead (Yaw)
	# Base Angle from Rule of Thirds
	var target_yaw_deg = facing_sign * lookahead_yaw_degrees
	
	# Velocity affects yaw angle too (Add to the SAME direction)
	var extra_yaw = min(speed_magnitude * velocity_lookahead_factor, 15.0)
	target_yaw_deg += facing_sign * extra_yaw
	
	# Turn Delay Logic:
	# If we just turned, use a MUCH slower speed to simulate "waiting" or weight
	var current_return_speed = yaw_return_speed
	if _time_since_turn < turn_slowdown_duration:
		current_return_speed *= turn_slowdown_factor
		_time_since_turn += dt
	
	# Smoothly interpolate auto-yaw
	yaw_offset = lerp(yaw_offset, deg2rad(target_yaw_deg), current_return_speed * dt)
	
	# Decay Manual Yaw/Pitch (Only if input inactive for a while)
	_time_since_input += dt
	if _time_since_input > manual_input_decay_delay:
		# Use slightly faster return speed for the "release" phase so it's noticeable
		var decay_speed = yaw_return_speed * 2.0
		manual_yaw = lerp(manual_yaw, 0.0, decay_speed * dt)
		manual_pitch = lerp(manual_pitch, 0.0, decay_speed * dt)
	
	# 3. Pan Logic (Deprecated for Lookahead, mostly zero)
	pan_offset = Vector2.ZERO # Reset pan, we use rotation now
	
	# Final target includes pan offset
	var target_lag = virtual_center
	
	# Lagging center smoothes the final target
	lagging_center = lagging_center.linear_interpolate(target_lag, camera_smoothing * dt)
	
	# Safety height check (prevent rig from going underground)
	if lagging_center.y < min_rig_height:
		lagging_center.y = min_rig_height
	
	return lagging_center

func get_cam_rotation() -> Vector3:
	# Returns Euler angles for Local Camera Rotation (relative to SpringArm/Rig)
	# Y = Yaw (Auto Look-Ahead only)
	# X = Pitch (None, manual pitch is now on Rig)
	return Vector3(0.0, yaw_offset, 0.0)

func get_zoom_offset(speed: float) -> float:
	return speed * velocity_zoom_factor

func update_facing(move_x: float):
	if abs(move_x) > 0.1:
		var new_sign = sign(move_x)
		if new_sign != facing_sign:
			facing_sign = new_sign
			_time_since_turn = 0.0 # Reset turn timer
	
	# Velocity hook could be added here if we passed dt and calculated it, 
	# but for now we trust the facing sign which is derived from input/movement.

func apply_pan(mouse_delta: Vector2):
	if mouse_delta.length_squared() > 1.0: # Ignore noise
		_time_since_input = 0.0 # valid input received
	
	# Proactive Manual Control: 
	# X -> Yaw (Look Left/Right)
	# Y -> Pitch (Look Up/Down)
	# Manual Yaw
	manual_yaw -= mouse_delta.x * pan_sensitivity * yaw_sensitivity
	var limit = deg2rad(15.0)
	manual_yaw = clamp(manual_yaw, -limit, limit)
	
	# Manual Pitch
	manual_pitch -= mouse_delta.y * pan_sensitivity * pitch_sensitivity
	manual_pitch = clamp(manual_pitch, -limit, limit)
	
	# If mouse pan is significant, change facing direction to match look intent
	if abs(mouse_delta.x) > 2.0:
		facing_sign = sign(mouse_delta.x)

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
		"yo": yaw_offset,
		"my": manual_yaw,
		"mp": manual_pitch,
		"fs": facing_sign,
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
	if data.has("po"):
		yaw_offset = data.get("yo", 0.0)
	manual_yaw = data.get("my", 0.0)
	manual_pitch = data.get("mp", 0.0)
	facing_sign = data.get("fs", 1.0)
	_first_frame = data.get("ff", true)
