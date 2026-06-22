extends Node
class_name ZeroGravitySettings

# Zero-G movement. max_speed is the target drift speed before sprint.
export(float) var max_speed := 8.0
# Multiplies max_speed while sprint is held.
export(float) var sprint_multiplier := 2.0
# How quickly velocity approaches the desired 0G movement vector.
export(float) var acceleration := 15.0
# Per-60Hz damping applied when there is no thrust input.
export(float, 0.0, 1.0) var idle_damping := 0.95

# Newtonian Inertia (FD-233)
# 0.0 = kinematic pure, 1.0 = inertia pure
export(float, 0.0, 1.0) var inertia_factor := 0.3
# Thrust force in Newtons
export(float) var thrust_force := 40.0
# Player mass in kg
export(float) var mass := 80.0
# Spatial friction per frame (0.995-1.0)
export(float, 0.995, 1.0) var space_damping := 0.998
# Absolute cap for inertial velocity (m/s)
export(float) var max_inertia_speed := 12.0

# Zero-G camera. The rig inherits full 6DOF orientation; the mesh does not inherit pitch/roll.
export(float) var roll_speed_deg := 90.0
# Fixed trailing distance for the dedicated 0G camera.
export(float) var camera_distance := 4.0
# FOV used by the dedicated 0G camera.
export(float) var camera_fov := 75.0
# Smooth follow rate for the zero-G rig origin. Lower values increase inertial lag.
export(float) var camera_follow_smooth := 8.0

# Zero-G mesh presentation. The mesh only turns toward horizontal forward
# while advancing; camera pitch/roll stay camera-only.
export(float) var mesh_rotation_smooth := 8.0
export(Vector3) var mesh_center_offset := Vector3(0.0, 1.0, 0.0)
# Input must exceed this before the mesh chooses a new facing direction.
export(float) var mesh_align_input_deadzone := 0.1

func configure_camera_rig(rig: Node) -> void:
	if rig and rig.has_method("apply_zero_g_settings"):
		rig.apply_zero_g_settings(self)
