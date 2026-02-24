extends InteractableBaseV2
class_name SlidingObjectV2
tool

# SlidingObjectV2.gd - Deterministic Sliding Door/Drawer
# Uses linear interpolation for smooth, deterministic sliding motion.

# --- EXPORTED TUNING ---
export(Vector3) var slide_vector := Vector3(0, 2, 0) setget set_slide_vector
export(Vector3) var size := Vector3(2, 2, 0.25) setget set_size
export(int, "Linear", "EaseInOut", "EaseIn", "EaseOut") var easing_type := 1

# --- INTERNAL STATE ---
var _start_position := Vector3.ZERO
var _initialized := false

func _ready():
	# Store initial position before parent _ready
	_start_position = translation
	_initialized = true
	
	# Call parent ready (adds to groups, calculates speed)
	._ready()
	
	# Apply size
	_update_size()

func set_slide_vector(v: Vector3):
	slide_vector = v
	if Engine.editor_hint and _initialized:
		_update_visuals()

func set_size(s: Vector3):
	size = s
	if is_inside_tree():
		_update_size()

func _update_size():
	var col = get_node_or_null("CollisionShape")
	if col and col.shape:
		if not col.shape.resource_local_to_scene:
			col.shape = col.shape.duplicate()
		if col.shape is BoxShape:
			col.shape.extents = size / 2.0
	
	var default_mesh = get_node_or_null("MeshInstance")
	_update_mesh_visibility(default_mesh)
		
	if default_mesh:
		# If using CSGBox, update dimensions
		if default_mesh is CSGBox:
			default_mesh.width = size.x
			default_mesh.height = size.y
			default_mesh.depth = size.z
		# If using CubeMesh, update size
		elif default_mesh.mesh and default_mesh.mesh is CubeMesh:
			if not default_mesh.mesh.resource_local_to_scene:
				default_mesh.mesh = default_mesh.mesh.duplicate()
			default_mesh.mesh.size = size

func _update_mesh_visibility(default_mesh: MeshInstance):
	var custom_mesh_found = false
	
	# Check for other MeshInstances or visual nodes acting as custom visuals
	for child in get_children():
		if child is MeshInstance and child.name != "MeshInstance":
			custom_mesh_found = true
			break
		if child is Spatial and not child is CollisionShape and not child is RayCast and child.name != "MeshInstance":
			# Any other Spatial that isn't a known utility node might be a custom visual
			custom_mesh_found = true
			break
			
	if default_mesh:
		default_mesh.visible = not custom_mesh_found

func _update_visuals() -> void:
	"""Interpolate position based on animation progress."""
	if not _initialized:
		return
	
	var eased = _apply_easing(anim_progress)
	var new_pos = _start_position.linear_interpolate(_start_position + slide_vector, eased)
	if debug and translation != new_pos:
		print("[SlidingObjectV2] ", name, " anim_progress=", anim_progress, " target=", target_progress, " pos: ", translation, " -> ", new_pos)
	translation = new_pos

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
	# Include start position for full restoration
	snap["start_pos"] = [_start_position.x, _start_position.y, _start_position.z]
	return snap

func restore_snapshot(data: Dictionary) -> void:
	if data.has("start_pos"):
		var sp = data["start_pos"]
		_start_position = Vector3(sp[0], sp[1], sp[2])
	
	.restore_snapshot(data)

# --- EDITOR PREVIEW ---

func _process(_delta):
	if Engine.editor_hint:
		# In editor, show closed position
		if not _initialized:
			_start_position = translation
			_initialized = true
		
		# Ensure placeholder hides immediately if user adds a custom mesh in the editor scene tree
		_update_mesh_visibility(get_node_or_null("MeshInstance"))
