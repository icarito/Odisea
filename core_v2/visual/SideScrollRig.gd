tool
extends CinematicRigV2
class_name SideScrollRig

# SideScrollRig.gd - A cinematic rig that tracks the player on specific axes (2D constraint)

export(Vector3) var constraint_axis := Vector3(1, 1, 0) # Default: Follow X and Y, Lock Z (Standard SideScroll)
export(Vector3) var offset := Vector3(0, 5, 10) # Relative to tracked position
export(float) var smoothing_speed := 5.0
export(bool) var allow_depth_movement := false

var _target: Spatial = null

func _ready():
	._ready() # Call parent ready logic
	if not is_in_group("SideScrollRig"):
		add_to_group("SideScrollRig")

func _find_target():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_target = players[0]

func _update_rig(dt: float):
	if not _target:
		_find_target()

	if _target:
		var target_pos = _target.global_transform.origin
		var current_pos = global_transform.origin

		var desired_pos = current_pos

		# If constraint_axis component > 0.5, we TRACK (Follow) that axis.
		# Otherwise we keep the current rig position (Lock) relative to world start.

		var is_z_locked = (constraint_axis.z < 0.5)
		var is_x_locked = (constraint_axis.x < 0.5)

		if not is_x_locked:
			desired_pos.x = target_pos.x + offset.x
		if constraint_axis.y > 0.5:
			desired_pos.y = target_pos.y + offset.y
		if not is_z_locked:
			desired_pos.z = target_pos.z + offset.z

		# Smoothing
		if dt > 0:
			var weight = clamp(smoothing_speed * dt, 0.0, 1.0)
			global_transform.origin = global_transform.origin.linear_interpolate(desired_pos, weight)
		else:
			global_transform.origin = desired_pos

		# Strict Orthogonal Rotation Logic
		# We orient the rig to face PERPENDICULAR to the locked plane.
		# Default Forward is -Z.

		var look_dir = Vector3(0, 0, -1) # Default
		var up_dir = Vector3.UP

		if is_x_locked:
			# Z-Scroll (Player moves Z). Lock X.
			# We view from Offset.X.
			# If Offset.X > 0, we are at Right, Look Left (-X).
			# If Offset.X < 0, we are at Left, Look Right (+X).
			# If Offset.X == 0, we look -X (default assumption).
			if offset.x >= 0:
				look_dir = Vector3(-1, 0, 0)
			else:
				look_dir = Vector3(1, 0, 0)

		elif is_z_locked:
			# Standard SideScroll (Player moves X). Lock Z.
			# We view from Offset.Z.
			# If Offset.Z > 0 (Standard), we are Front, Look Back (-Z).
			# If Offset.Z < 0, we are Back, Look Front (+Z).
			if offset.z >= 0:
				look_dir = Vector3(0, 0, -1)
			else:
				look_dir = Vector3(0, 0, 1)

		# Apply Rotation
		# We construct a Basis looking at look_dir
		# look_at(pos + look_dir) works, but manual basis is cleaner
		var b_z = -look_dir.normalized() # Godot Z is backward
		var b_x = up_dir.cross(b_z).normalized()
		var b_y = b_z.cross(b_x).normalized()
		global_transform.basis = Basis(b_x, b_y, b_z)
