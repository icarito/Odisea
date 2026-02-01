extends InteractableBaseV2
class_name PressurePlateV2
tool

# PressurePlateV2.gd - Deterministic Weight-based Switch
# Activates when bodies are on top of it.

# --- EXPORTED TUNING ---
export(Vector3) var sink_vector := Vector3(0, -0.15, 0)
export(bool) var is_latched := false # If true, stays active once pressed

# --- INTERNAL STATE ---
var _start_position := Vector3.ZERO
var _initialized := false
var _detection_area: Area = null

func _ready():
	_start_position = translation
	_initialized = true
	
	# Find a child Area to use for weight detection
	for child in get_children():
		if child is Area:
			_detection_area = child
			break
			
	._ready()

func _update_visuals() -> void:
	if not _initialized:
		return
	
	var eased = _ease_in_out(anim_progress)
	translation = _start_position + (sink_vector * eased)

func step(dt: float) -> void:
	# Deterministic weighted detection
	var bodies = []
	if _detection_area:
		bodies = _detection_area.get_overlapping_bodies()
	
	var has_weight = false
	
	for body in bodies:
		if body == self: continue
		# Ignore triggers or non-physical objects if needed
		# For now, any body triggers it
		has_weight = true
		break
	
	if has_weight:
		if not is_active:
			set_active(true)
	else:
		if is_active and not is_latched:
			set_active(false)
			
	.step(dt)

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
