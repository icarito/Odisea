extends InteractableBaseV2
class_name RotatingObjectV2
tool

# RotatingObjectV2.gd - Deterministic Rotating Lever/Valve
# Uses angular interpolation for smooth, deterministic rotation.

# --- EXPORTED TUNING ---
export(Vector3) var rotation_axis := Vector3.RIGHT setget set_rotation_axis
export(float) var rotation_amount := 90.0 setget set_rotation_amount
export(int, "Linear", "EaseInOut", "EaseIn", "EaseOut") var easing_type := 1

# --- INTERNAL STATE ---
var _start_rotation := Vector3.ZERO
var _initialized := false

func _ready():
	# Store initial rotation before parent _ready
	_start_rotation = rotation_degrees_property()
	_initialized = true
	
	# Call parent ready
	._ready()

func rotation_degrees_property() -> Vector3:
	"""Get rotation in degrees (wrapper for property name conflict)."""
	return Vector3(
		rad2deg(rotation.x),
		rad2deg(rotation.y),
		rad2deg(rotation.z)
	)

func set_rotation_axis(v: Vector3):
	rotation_axis = v.normalized() if v.length() > 0.001 else Vector3.RIGHT
	if Engine.editor_hint and _initialized:
		_update_visuals()

func set_rotation_amount(d: float):
	rotation_amount = d
	if Engine.editor_hint and _initialized:
		_update_visuals()

func _update_visuals() -> void:
	"""Interpolate rotation based on animation progress."""
	if not _initialized:
		return
	
	var eased = _apply_easing(anim_progress)
	var angle = lerp(0.0, deg2rad(rotation_amount), eased)
	
	# Reset to start rotation then apply animated rotation
	rotation = Vector3(
		deg2rad(_start_rotation.x),
		deg2rad(_start_rotation.y),
		deg2rad(_start_rotation.z)
	)
	rotate(rotation_axis, angle)
	force_update_transform()

func _apply_easing(t: float) -> float:
	match easing_type:
		0: return t # Linear
		1: return _ease_in_out(t)
		2: return _ease_in(t)
		3: return _ease_out(t)
	return t

# --- SNAPSHOT OVERRIDE ---

func get_snapshot() -> Dictionary:
	var snap =.get_snapshot()
	# Include start rotation for full restoration
	snap["start_rot"] = [_start_rotation.x, _start_rotation.y, _start_rotation.z]
	return snap

func restore_snapshot(data: Dictionary) -> void:
	if data.has("start_rot"):
		var sr = data["start_rot"]
		_start_rotation = Vector3(sr[0], sr[1], sr[2])
	
	.restore_snapshot(data)

# --- EDITOR PREVIEW ---

func _process(_delta):
	if Engine.editor_hint:
		if not _initialized:
			_start_rotation = rotation_degrees_property()
			_initialized = true
