extends Node

# OverTheShoulder.gd - Special zoom framing curve.
# Natural feeling OTS view that is derived from the effective spring arm length.
# Now includes jump compensation to keep the player framed during vertical movement.
# This component should be placed under the "Logic" node of the PlayerController.

# --- EXPORTED TUNING: OTS ---

# Max horizontal displacement when fully zoomed in.
export(float) var max_side_offset := 0.75

# Vertical displacement when fully zoomed in (negative = down towards shoulder).
export(float) var max_height_offset := -0.65

# Pivot offset when fully zoomed in (positive = move pivot back).
export(float) var max_pivot_z_offset := 0.2

# Spring length at which OTS is fully active (e.g., 1.5m from player).
export(float) var distance_min := 1.5

# Spring length at which OTS starts activating (e.g., at 4.5m it begins to slide).
export(float) var distance_max := 4.5

# Toggle which side to slide to (True = Right, False = Left).
export(bool) var right_side := true

# How fast the camera slides to the side (higher = snappier, lower = lazier).
export(float) var lerp_speed := 6.0

# Power of the transition curve. 1.0 is linear, > 1.0 makes the slide accelerate as it nears distance_min.
export(float) var curve_power := 1.5

# Smoothing speed while entering the zoom-driven OTS blend.
export(float) var distance_blend_speed := 2.0

# Smoothing speed while leaving OTS. Lower than enter speed to avoid a pop when
# a doorway/corner stops shortening the arm for only a moment.
export(float) var distance_unblend_speed := 1.2

# When the camera arm is colliding, only the shoulder side offset compresses
# toward center so the camera can sit behind the player while passing doors.
export(float) var side_clearance_blend_speed := 2.2
export(float) var side_restore_blend_speed := 1.4

# Centering only activates when the arm is compressed to this fraction of its
# target length or less. 1.0 = any collision; 0.55 = narrow passage only.
export(float) var centering_compression_threshold := 0.55

# Seconds of sustained heavy compression required before centering activates.
# Prevents centering on brief wall/prop touches during camera orbiting.
export(float) var centering_trigger_time := 0.20

# Seconds centering remains active after heavy compression clears.
# Avoids a pop when the player just exits a narrow doorway.
export(float) var centering_release_hold_time := 0.40

# --- EXPORTED TUNING: JUMP COMPENSATION ---

# How much the camera pivot moves back (+Z) when the player is rising.
export(float) var jump_recede_offset := 0.8

# How much the camera pivot moves up (+Y) when the player is rising.
export(float) var jump_rise_offset := 0.6

# Speed at which jump compensation is applied.
export(float) var jump_compensation_speed := 3.5

var _current_offset := Vector3.ZERO
var _jump_comp_weight := 0.0
var _distance_weight := 0.0
var _side_clearance_weight := 1.0
var _centering_build_timer := 0.0   # builds up while heavy compression is sustained
var _centering_hold_timer := 0.0    # keeps centering active briefly after compression clears
var _player: KinematicBody = null
var _spring_arm = null
var _ots_offset_parent: Spatial = null

func _ready():
	_player = get_parent().get_parent() as KinematicBody
	if not _player:
		# Search if not directly under Logic
		var p = get_parent()
		while p and not (p is KinematicBody):
			p = p.get_parent()
		_player = p as KinematicBody

	if _player:
		# Locate the spring arm and its OTS offset parent in the player's camera rig
		_spring_arm = _player.get_node_or_null("CameraRig/Yaw/Pitch/OTS_Offset/SpringArm")
		if not _spring_arm:
			_spring_arm = _player.get_node_or_null("CameraRig/Yaw/Pitch/SpringArm")
		if _spring_arm and _spring_arm.get_parent() is Spatial:
			_ots_offset_parent = _spring_arm.get_parent() as Spatial

func _physics_process(delta: float):
	if not _player or not _spring_arm:
		return

	# Safety check: Only apply OTS in FREE control mode (standard third person)
	var cinematic_manager = get_node_or_null("/root/CinematicManager")
	if cinematic_manager and cinematic_manager.get_control_mode() != cinematic_manager.ControlMode.FREE:
		_reset_offset(delta)
		return

	# 1. OTS zoom curve. Manual zoom and collision-shortened zoom both feed
	# the same curve; collision is not a separate shoulder mode.
	var effective_len := _get_effective_arm_length()
	var raw_weight := _compute_ots_weight(effective_len)
	var ots_weight := pow(raw_weight, curve_power)
	var zoom_blend_speed: float = distance_blend_speed if ots_weight >= _distance_weight else distance_unblend_speed
	_distance_weight = lerp(_distance_weight, ots_weight, _blend_alpha(zoom_blend_speed, delta))
	# Center only for significant arm compression (narrow passage), not any minor
	# collision touch while orbiting the camera near walls or furniture.
	var target_len_ref := _get_target_arm_length()
	var compression_ratio := effective_len / max(target_len_ref, 0.001)
	var heavy_collision := _has_active_arm_collision() and compression_ratio <= centering_compression_threshold

	if heavy_collision:
		_centering_build_timer = min(_centering_build_timer + delta, centering_trigger_time)
	else:
		# Decay twice as fast so a brief touch doesn't accumulate much credit.
		_centering_build_timer = max(_centering_build_timer - delta * 2.0, 0.0)

	if _centering_build_timer >= centering_trigger_time:
		# Refresh the hold timer each frame centering is fully active.
		_centering_hold_timer = centering_release_hold_time
	else:
		_centering_hold_timer = max(_centering_hold_timer - delta, 0.0)

	var centering_active := _centering_build_timer >= centering_trigger_time or _centering_hold_timer > 0.0
	var side_target: float = 0.0 if centering_active else 1.0
	var side_speed: float = side_restore_blend_speed if side_target > _side_clearance_weight else side_clearance_blend_speed
	_side_clearance_weight = lerp(_side_clearance_weight, side_target, _blend_alpha(side_speed, delta))

	# 2. Jump Compensation Calculation
	# We look for a rising state to pull the camera back and up.
	var is_rising = _player.velocity.y > 0.5 and not _player.is_on_floor()
	var target_jump_comp = 1.0 if is_rising else 0.0
	_jump_comp_weight = lerp(_jump_comp_weight, target_jump_comp, _blend_alpha(jump_compensation_speed, delta))

	# 3. Combine Offsets
	var target_offset := Vector3.ZERO

	# OTS follows zoom only. The arm decides distance; this component turns
	# that distance into framing.
	target_offset.x = max_side_offset * _distance_weight * _side_clearance_weight * (1.0 if right_side else -1.0)
	target_offset.y = max_height_offset * _distance_weight
	target_offset.z = max_pivot_z_offset * _distance_weight

	# Jump compensation
	target_offset.y += jump_rise_offset * _jump_comp_weight
	target_offset.z += jump_recede_offset * _jump_comp_weight

	# Smoothly interpolate to combined target
	_current_offset = _current_offset.linear_interpolate(target_offset, _blend_alpha(lerp_speed, delta))
	_apply_arm_offset(_current_offset)

func _reset_offset(delta: float):
	_distance_weight = lerp(_distance_weight, 0.0, _blend_alpha(distance_blend_speed, delta))
	_side_clearance_weight = lerp(_side_clearance_weight, 1.0, _blend_alpha(side_restore_blend_speed, delta))
	if _current_offset.length_squared() > 0.00001:
		_current_offset = _current_offset.linear_interpolate(Vector3.ZERO, _blend_alpha(lerp_speed, delta))
		_apply_arm_offset(_current_offset)
		_jump_comp_weight = 0.0
	elif _spring_arm:
		_apply_arm_offset(Vector3.ZERO)
		_jump_comp_weight = 0.0

func _blend_alpha(speed: float, delta: float) -> float:
	return 1.0 - exp(-max(speed, 0.0) * max(delta, 0.0))

func _get_effective_arm_length() -> float:
	var target_len := _get_target_arm_length()
	var current_len = _spring_arm.get("current_length")
	if current_len == null:
		current_len = _player.get("current_spring_length")
	if current_len == null:
		return target_len
	return min(float(current_len), target_len)

func _get_target_arm_length() -> float:
	var target_len = _spring_arm.get("target_length")
	if target_len == null:
		target_len = _spring_arm.get("spring_length")
	if target_len == null:
		target_len = _player.get("current_spring_length")
	if target_len == null:
		return 5.0
	return float(target_len)

func _compute_ots_weight(current_len: float) -> float:
	var distance_span := max(distance_max - distance_min, 0.001)
	return 1.0 - clamp((current_len - distance_min) / distance_span, 0.0, 1.0)

func _has_active_arm_collision() -> bool:
	if _spring_arm.has_method("has_active_collision"):
		return _spring_arm.has_active_collision()
	if _spring_arm.has_method("is_zoom_out_blocked"):
		return _spring_arm.is_zoom_out_blocked()
	var target_len := _get_target_arm_length()
	var current_len := _get_effective_arm_length()
	return current_len < target_len - 0.02

func _apply_arm_offset(offset: Vector3) -> void:
	if _spring_arm and _spring_arm.has_method("set_camera_local_offset"):
		_spring_arm.set_camera_local_offset(offset)
	elif _ots_offset_parent:
		_ots_offset_parent.translation = offset
