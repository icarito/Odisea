extends Node

# OverTheShoulder.gd - Component to slide the camera to the side when zooming in.
# Natural feeling OTS view that activates as the spring arm length decreases.
# Now includes jump compensation to keep the player framed during vertical movement.
# This component should be placed under the "Logic" node of the PlayerController.

# --- EXPORTED TUNING: OTS ---

# Max horizontal displacement when fully zoomed in.
export(float) var max_side_offset := 0.65

# Vertical displacement when fully zoomed in (negative = down towards shoulder).
export(float) var max_height_offset := -0.25

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

# Smoothing speed for the distance-driven OTS blend.
export(float) var distance_blend_speed := 8.0

# Smoothing speed for the collision shoulder assist.
export(float) var collision_blend_speed := 10.0

# --- EXPORTED TUNING: JUMP COMPENSATION ---

# How much the camera pivot moves back (+Z) when the player is rising.
export(float) var jump_recede_offset := 0.5

# How much the camera pivot moves up (+Y) when the player is rising.
export(float) var jump_rise_offset := 0.4

# Speed at which jump compensation is applied.
export(float) var jump_compensation_speed := 3.5

var _current_offset := Vector3.ZERO
var _jump_comp_weight := 0.0
var _distance_weight := 0.0
var _collision_weight := 0.0
var _player: KinematicBody = null
var _spring_arm = null
var _ots_offset: Spatial = null

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
			_ots_offset = _spring_arm.get_parent() as Spatial

func _physics_process(delta: float):
	if not _player or not _spring_arm or not _ots_offset:
		return

	# Safety check: Only apply OTS in FREE control mode (standard third person)
	var cinematic_manager = get_node_or_null("/root/CinematicManager")
	if cinematic_manager and cinematic_manager.get_control_mode() != cinematic_manager.ControlMode.FREE:
		_reset_offset(delta)
		return

	# 1. OTS Calculation
	var current_len := _get_current_arm_length()
	var collision_active := _has_active_arm_collision(current_len)
	var raw_weight := _compute_ots_weight(current_len)
	var ots_weight := pow(raw_weight, curve_power)
	_distance_weight = lerp(_distance_weight, ots_weight, _blend_alpha(distance_blend_speed, delta))
	_collision_weight = lerp(_collision_weight, 1.0 if collision_active else 0.0, _blend_alpha(collision_blend_speed, delta))
	var effective_ots_weight := max(_distance_weight, _collision_weight)

	# 2. Jump Compensation Calculation
	# We look for a rising state to pull the camera back and up.
	var is_rising = _player.velocity.y > 0.5 and not _player.is_on_floor()
	var target_jump_comp = 1.0 if is_rising else 0.0
	_jump_comp_weight = lerp(_jump_comp_weight, target_jump_comp, _blend_alpha(jump_compensation_speed, delta))

	# 3. Combine Offsets
	var target_offset := Vector3.ZERO

	# OTS horizontal and vertical.
	# Horizontal/Z framing may receive extra collision help, but vertical framing
	# always follows the smooth distance-based OTS blend so we don't snap above
	# the head or dive toward the feet when the arm jitters against geometry.
	target_offset.x = max_side_offset * effective_ots_weight * (1.0 if right_side else -1.0)
	target_offset.y = max_height_offset * _distance_weight
	target_offset.z = max_pivot_z_offset * effective_ots_weight

	# Jump compensation
	target_offset.y += jump_rise_offset * _jump_comp_weight
	target_offset.z += jump_recede_offset * _jump_comp_weight

	# Smoothly interpolate to combined target
	_current_offset = _current_offset.linear_interpolate(target_offset, _blend_alpha(lerp_speed, delta))
	_apply_arm_offset(_current_offset)

func _reset_offset(delta: float):
	_distance_weight = lerp(_distance_weight, 0.0, _blend_alpha(distance_blend_speed, delta))
	_collision_weight = lerp(_collision_weight, 0.0, _blend_alpha(collision_blend_speed, delta))
	if _current_offset.length_squared() > 0.00001:
		_current_offset = _current_offset.linear_interpolate(Vector3.ZERO, _blend_alpha(lerp_speed, delta))
		_apply_arm_offset(_current_offset)
		_jump_comp_weight = 0.0
	elif _spring_arm:
		_apply_arm_offset(Vector3.ZERO)
		_jump_comp_weight = 0.0

func _blend_alpha(speed: float, delta: float) -> float:
	return 1.0 - exp(-max(speed, 0.0) * max(delta, 0.0))

func _get_current_arm_length() -> float:
	var current_len = _spring_arm.get("current_length")
	if current_len == null:
		current_len = _player.get("current_spring_length")
	if current_len == null:
		return 5.0
	return float(current_len)

func _get_target_arm_length() -> float:
	var target_len = _spring_arm.get("target_length")
	if target_len == null:
		target_len = _spring_arm.get("spring_length")
	if target_len == null:
		target_len = _player.get("current_spring_length")
	if target_len == null:
		return 5.0
	return float(target_len)

func _has_active_arm_collision(current_len: float) -> bool:
	if _spring_arm.has_method("has_active_collision"):
		return _spring_arm.has_active_collision()
	if _spring_arm.has_method("is_zoom_out_blocked") and _spring_arm.is_zoom_out_blocked():
		return true
	var target_len := _get_target_arm_length()
	return current_len < target_len - 0.02

func _compute_ots_weight(current_len: float) -> float:
	var distance_span := max(distance_max - distance_min, 0.001)
	return 1.0 - clamp((current_len - distance_min) / distance_span, 0.0, 1.0)

func _apply_arm_offset(offset: Vector3) -> void:
	if not _ots_offset:
		return
	_ots_offset.translation = offset
