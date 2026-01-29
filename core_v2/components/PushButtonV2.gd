extends InteractableBaseV2
class_name PushButtonV2
tool

# PushButtonV2.gd - Deterministic Wall Button
# Activates when clicked by the player.

# --- EXPORTED TUNING ---
export(Vector3) var push_vector := Vector3(0, 0, -0.1)
export(bool) var is_toggle := false # If false, it's a momentary push (springs back)

# --- INTERNAL STATE ---
var _start_position := Vector3.ZERO
var _initialized := false

func _ready():
	_start_position = translation
	_initialized = true
	._ready()
	
	if interaction_text == "Interact":
		interaction_text = "Push Button"

func _update_visuals() -> void:
	if not _initialized:
		return
	
	var eased = _ease_in_out(anim_progress)
	translation = _start_position + (push_vector * eased)

func _on_animation_completed() -> void:
	._on_animation_completed()
	
	# If not a toggle, deactivate after pushing in
	if is_active and not is_toggle:
		set_active(false)

# --- REPLAY SYSTEM ---

func get_snapshot() -> Dictionary:
	var snap =.get_snapshot()
	snap["start_pos"] = [_start_position.x, _start_position.y, _start_position.z]
	return snap

func restore_snapshot(data: Dictionary) -> void:
	if data.has("start_pos"):
		var sp = data["start_pos"]
		_start_position = Vector3(sp[0], sp[1], sp[2])
	.restore_snapshot(data)
