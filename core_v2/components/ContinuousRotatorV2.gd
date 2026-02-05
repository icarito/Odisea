extends Spatial
class_name ContinuousRotatorV2
tool

# ContinuousRotatorV2.gd - Deterministic Rotating Machinery
# Rotates infinitely based on time and speed.

# --- EXPORTED TUNING ---
export(Vector3) var rotation_speed_degrees := Vector3(0, 90, 0)
export(bool) var is_active := true setget set_is_active
export(float) var ramp_up_time := 2.0 # Time to reach full speed or stop

# --- INTERNAL STATE ---
var current_speed_scale := 0.0 # 0.0 to 1.0
var accumulated_rotation := Vector3.ZERO

func _ready():
	add_to_group("replay_sync")

	if Engine.editor_hint:
		return

	# Initialize speed scale
	if is_active:
		# If starting active, assume fully spun up unless we want a warm-up on level load
		# For now, let's assume fully active to avoid desync on load if not handled carefully
		current_speed_scale = 1.0
	else:
		current_speed_scale = 0.0

func set_is_active(val):
	is_active = val

func step(dt: float):
	if Engine.editor_hint:
		return

	# Update speed scale
	var target_scale = 1.0 if is_active else 0.0

	if ramp_up_time > 0:
		current_speed_scale = move_toward(current_speed_scale, target_scale, (1.0 / ramp_up_time) * dt)
	else:
		current_speed_scale = target_scale

	if current_speed_scale == 0 and not is_active:
		return

	# Calculate rotation step
	var delta_rot = rotation_speed_degrees * current_speed_scale * dt
	accumulated_rotation += delta_rot

	# Wrap accumulation to keep precision high, but carefully so it doesn't jump visuals incorrectly if strictly interpolating (though rotation handles wrap)
	accumulated_rotation.x = fmod(accumulated_rotation.x, 360.0)
	accumulated_rotation.y = fmod(accumulated_rotation.y, 360.0)
	accumulated_rotation.z = fmod(accumulated_rotation.z, 360.0)

	# Apply rotation
	rotation_degrees = accumulated_rotation

func _physics_process(delta):
	step(delta)

# --- SNAPSHOT OVERRIDE ---

func get_snapshot() -> Dictionary:
	return {
		"active": is_active,
		"speed_scale": current_speed_scale,
		"accum_rot": [accumulated_rotation.x, accumulated_rotation.y, accumulated_rotation.z]
	}

func restore_snapshot(data: Dictionary):
	is_active = data.get("active", false)
	current_speed_scale = data.get("speed_scale", 0.0)
	if data.has("accum_rot"):
		var ar = data["accum_rot"]
		accumulated_rotation = Vector3(ar[0], ar[1], ar[2])
		rotation_degrees = accumulated_rotation
