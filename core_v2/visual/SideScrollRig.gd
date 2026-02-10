tool
extends CinematicRigV2
class_name SideScrollRig

# SideScrollRig.gd - A cinematic rig that tracks the player on specific axes (2D constraint)

export(Vector3) var constraint_axis := Vector3(1, 1, 0) # Default: Follow X and Y, Lock Z (Standard SideScroll)
export(Vector3) var offset := Vector3(0, 5, 10) # Relative to tracked position
export(float) var smoothing_speed := 5.0

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
		# Otherwise we keep the current rig position (Lock) relative to world start,
		# effectively staying on the "Track Line" defined by the initial position.

		if constraint_axis.x > 0.5:
			desired_pos.x = target_pos.x + offset.x
		if constraint_axis.y > 0.5:
			desired_pos.y = target_pos.y + offset.y
		if constraint_axis.z > 0.5:
			desired_pos.z = target_pos.z + offset.z

		# Smoothing
		if dt > 0:
			global_transform.origin = global_transform.origin.linear_interpolate(desired_pos, smoothing_speed * dt)
		else:
			global_transform.origin = desired_pos
