extends Node

# OverTheShoulder.gd - Component to slide the camera to the side when zooming in.
# Natural feeling OTS view that activates as the spring arm length decreases.
# This component should be placed under the "Logic" node of the PlayerController.

# --- EXPORTED TUNING ---

# Max horizontal displacement when fully zoomed in.
export(float) var max_side_offset := 0.65

# Vertical displacement when fully zoomed in (negative = down towards shoulder).
export(float) var max_height_offset := -0.25

# Forward/Backward displacement when fully zoomed in (positive = move closer to head).
export(float) var max_forward_offset := 0.2

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

var _current_offset := Vector3.ZERO
var _player: KinematicBody = null
var _spring_arm: Spatial = null

func _ready():
	_player = get_parent().get_parent() as KinematicBody
	if not _player:
		# Search if not directly under Logic
		var p = get_parent()
		while p and not (p is KinematicBody):
			p = p.get_parent()
		_player = p as KinematicBody

	if _player:
		# Locate the spring arm in the player's camera rig
		_spring_arm = _player.get_node_or_null("CameraRig/Yaw/Pitch/SpringArm")

func _physics_process(delta: float):
	if not _player or not _spring_arm:
		return

	# Safety check: Only apply OTS in FREE control mode (standard third person)
	# We don't want to interfere with fixed cameras or sidescroll modes.
	var cinematic_manager = get_node_or_null("/root/CinematicManager")
	if cinematic_manager and cinematic_manager.get_control_mode() != cinematic_manager.ControlMode.FREE:
		_reset_offset(delta)
		return

	# We use the current_length from the spring arm as the driver.
	# This ensures OTS kicks in both when zooming in AND when in tight spaces (collision).
	var current_len = _spring_arm.get("current_length")
	if current_len == null:
		# Fallback to player's zoom state if spring arm is a standard SpringArm3D without current_length
		current_len = _player.get("current_spring_length")

	if current_len == null:
		_reset_offset(delta)
		return

	# Calculate desired weight based on current spring length [0.0 to 1.0]
	var raw_weight = 1.0 - clamp((current_len - distance_min) / (distance_max - distance_min), 0.0, 1.0)

	# Apply easing curve for a "softer" curve into the shoulder
	var weight = pow(raw_weight, curve_power)

	var target_offset = Vector3.ZERO
	target_offset.x = max_side_offset * weight * (1.0 if right_side else -1.0)
	target_offset.y = max_height_offset * weight
	target_offset.z = max_forward_offset * weight

	# Smoothly interpolate to target to avoid jitter
	_current_offset = _current_offset.linear_interpolate(target_offset, lerp_speed * delta)

	# Apply offset to the SpringArm's local translation.
	# KinematicArm3D uses its own global_transform.origin as the raycast start point,
	# so shifting it locally here correctly moves the "orbit pivot".
	_spring_arm.translation = _current_offset

func _reset_offset(delta: float):
	# Gently return to center when OTS is disabled or not applicable.
	if _current_offset.length_squared() > 0.00001:
		_current_offset = _current_offset.linear_interpolate(Vector3.ZERO, lerp_speed * delta)
		if _spring_arm:
			_spring_arm.translation = _current_offset
	elif _spring_arm and _spring_arm.translation != Vector3.ZERO:
		_spring_arm.translation = Vector3.ZERO
