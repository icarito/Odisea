extends InteractableBaseV2
class_name PressurePlateV2
# tool

# PressurePlateV2.gd - Deterministic Weight-based Switch
# Activates when bodies are on top of it.

# --- EXPORTED TUNING ---
export(Vector3) var sink_vector := Vector3(0, -0.15, 0)
export(bool) var is_latched := false # If true, stays active once pressed

# --- INTERNAL STATE ---
var _start_position := Vector3.ZERO
var _initialized := false
var _detection_area: Area = null
var _debug_weight_override := false

func interact() -> void:
	if debug or Engine.editor_hint:
		_debug_weight_override = not _debug_weight_override
		print("[PressurePlateV2] Debug override toggled: ", _debug_weight_override)
		return
	.interact()

func _ready():
	_start_position = translation
	# Find the detector area
	# Ensure the scene tree path matches the structure in PressurePlate.tscn
	if has_node("Detector"):
		_detection_area = $Detector
	else:
		# Fallback or error logging
		printerr("[PressurePlateV2] Error: 'Detector' Area node not found! Collision logic will fail.")
	
	_initialized = true
	_update_visuals()

func step(dt: float) -> void:
	# Deterministic weighted detection
	var bodies = []
	if _detection_area:
		bodies = _detection_area.get_overlapping_bodies()
		# if bodies.size() > 0: print("[PressurePlateV2] Detect: ", bodies)
	
	var has_weight = false
	
	for body in bodies:
		if body == self: continue
		has_weight = true
		break
		
	if _debug_weight_override:
		has_weight = true
	
	# Debug state
	# ... (logging)

	if has_weight:
		if not is_active:
			# ...
			set_active(true)
	else:
		if is_active and not is_latched:
			# ...
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

func _update_visuals() -> void:
	# Move the plate towards sink target based on animation progress
	# InteractableBase handles the progress interpolation (0.0 to 1.0)
	var offset = sink_vector * anim_progress
	translation = _start_position + offset
