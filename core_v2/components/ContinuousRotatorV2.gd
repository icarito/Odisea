extends KinematicBody
class_name ContinuousRotatorV2

# ContinuousRotatorV2.gd - Deterministic infinite rotation
# Suitable for Turbines, Fans, Radar Dishes, etc.

# --- EXPORTED TUNING ---
export(Vector3) var rotation_speed := Vector3(0, 360, 0) # Degrees per second
export(bool) var is_active := true
export(float) var ramp_up_time := 1.0 # Time to reach full speed

# --- INTERNAL STATE ---
var current_speed_mult := 0.0 # 0.0 to 1.0
var accumulated_rotation := Vector3.ZERO

func _ready():
	add_to_group("replay_sync")
	if is_active:
		current_speed_mult = 1.0
	else:
		current_speed_mult = 0.0

	# Initial rotation snap
	accumulated_rotation = rotation_degrees

func step(dt: float):
	# Ramp logic
	var target_mult = 1.0 if is_active else 0.0
	if ramp_up_time > 0:
		current_speed_mult = move_toward(current_speed_mult, target_mult, (1.0 / ramp_up_time) * dt)
	else:
		current_speed_mult = target_mult

	# Apply rotation
	var delta_rot = rotation_speed * current_speed_mult * dt
	accumulated_rotation += delta_rot

	# Keep angles manageable
	accumulated_rotation.x = fmod(accumulated_rotation.x, 360.0)
	accumulated_rotation.y = fmod(accumulated_rotation.y, 360.0)
	accumulated_rotation.z = fmod(accumulated_rotation.z, 360.0)

	rotation_degrees = accumulated_rotation

func _physics_process(delta):
	# Only auto-step if NOT in replay mode or manual mode
	if not SessionManager.is_manual_mode:
		step(delta)

func set_active(active: bool):
	is_active = active

# --- REPLAY SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"is_active": is_active,
		"speed_mult": current_speed_mult,
		"rot": [accumulated_rotation.x, accumulated_rotation.y, accumulated_rotation.z]
	}

func restore_snapshot(data: Dictionary):
	is_active = data.get("is_active", true)
	current_speed_mult = data.get("speed_mult", 0.0)
	var rot = data.get("rot", [0, 0, 0])
	accumulated_rotation = Vector3(rot[0], rot[1], rot[2])
	rotation_degrees = accumulated_rotation
