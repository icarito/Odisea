extends Node

# CinematicLogicV2.gd - Component for handling cinematic input transformations

# Exported variables for adjustment as requested
export(float) var input_smoothing := 0.1

func transform_input(move_vec: Vector2, cam: Camera, mode: int) -> Vector3:
	if not cam:
		return Vector3(move_vec.x, 0, move_vec.y)

	var basis = cam.global_transform.basis
	var direction = Vector3.ZERO
	var CM = CinematicManager.ControlMode

	match mode:
		CM.FREE:
			# Free mode relative to cinematic camera (following standard convention)
			var forward = basis.z # In this project, basis.z seems to be forward
			forward.y = 0
			forward = forward.normalized()
			var right = basis.x
			right.y = 0
			right = right.normalized()
			direction = right * move_vec.x + forward * move_vec.y

		CM.SIDESCROLL:
			# Restrict to a plane (X or Z).
			var cam_right = basis.x
			if abs(cam_right.x) > abs(cam_right.z):
				# Move along global X axis
				var sign_x = sign(cam_right.x)
				direction = Vector3(1, 0, 0) * (move_vec.x * sign_x)
			else:
				# Move along global Z axis
				var sign_z = sign(cam_right.z)
				direction = Vector3(0, 0, 1) * (move_vec.x * sign_z)

		CM.LOCKED_VIEW:
			# "Up" on stick is "To the background"
			# We use camera negative Z (forward in Godot) projected to floor
			var forward_depth = -basis.z
			forward_depth.y = 0
			forward_depth = forward_depth.normalized()

			var right = basis.x
			right.y = 0
			right = right.normalized()

			# Stick Up (positive Y) -> Towards background (forward_depth)
			direction = right * move_vec.x + forward_depth * move_vec.y

		CM.FIXED_AXIS:
			# Global axes: X is right, Y is forward/backward (-Z in Godot global)
			direction = Vector3(move_vec.x, 0, -move_vec.y)

	return direction
