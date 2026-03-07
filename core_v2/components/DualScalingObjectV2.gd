extends InteractableBaseV2
class_name DualScalingObjectV2
tool

# DualScalingObjectV2.gd - Deterministic Dual Scaling Doors
# Controls two separate meshes moving and scaling based on a single anim_progress.

# --- EXPORTED TUNING ---
export(NodePath) var mesh_a_path
export(NodePath) var mesh_b_path
export(Vector3) var slide_vector_a := Vector3(-0.75, 0, 0)
export(Vector3) var slide_vector_b := Vector3(0.75, 0, 0)
export(Vector3) var scale_vector_a := Vector3(-0.95, 0, 0)
export(Vector3) var scale_vector_b := Vector3(-0.95, 0, 0)
export(int, "Linear", "EaseInOut", "EaseIn", "EaseOut") var easing_type := 1

# --- INTERNAL STATE ---
var _mesh_a: Spatial = null
var _mesh_b: Spatial = null
var _start_pos_a := Vector3.ZERO
var _start_pos_b := Vector3.ZERO
var _start_scale_a := Vector3.ONE
var _start_scale_b := Vector3.ONE
var _initialized := false

func _ready():
	# Cache meshes
	if mesh_a_path:
		_mesh_a = get_node_or_null(mesh_a_path)
	if mesh_b_path:
		_mesh_b = get_node_or_null(mesh_b_path)

	# Store initial positions and scales
	if _mesh_a:
		_start_pos_a = _mesh_a.translation
		_start_scale_a = _mesh_a.scale
	if _mesh_b:
		_start_pos_b = _mesh_b.translation
		_start_scale_b = _mesh_b.scale

	_initialized = true

	# Call parent ready
	._ready()

func _update_visuals() -> void:
	"""Interpolate position and scale based on animation progress."""
	if not _initialized:
		return

	var eased = _apply_easing(anim_progress)

	if _mesh_a:
		_mesh_a.translation = _start_pos_a.linear_interpolate(_start_pos_a + slide_vector_a, eased)
		_mesh_a.scale = _start_scale_a.linear_interpolate(_start_scale_a + scale_vector_a, eased)
		if _mesh_a is CollisionObject: _mesh_a.force_update_transform()
		elif _mesh_a is CSGShape: _mesh_a.force_update_transform()

	if _mesh_b:
		_mesh_b.translation = _start_pos_b.linear_interpolate(_start_pos_b + slide_vector_b, eased)
		_mesh_b.scale = _start_scale_b.linear_interpolate(_start_scale_b + scale_vector_b, eased)
		if _mesh_b is CollisionObject: _mesh_b.force_update_transform()
		elif _mesh_b is CSGShape: _mesh_b.force_update_transform()

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
	# Include start positions and scale for full restoration
	snap["start_pos_a"] = [_start_pos_a.x, _start_pos_a.y, _start_pos_a.z]
	snap["start_pos_b"] = [_start_pos_b.x, _start_pos_b.y, _start_pos_b.z]
	snap["start_scale_a"] = [_start_scale_a.x, _start_scale_a.y, _start_scale_a.z]
	snap["start_scale_b"] = [_start_scale_b.x, _start_scale_b.y, _start_scale_b.z]
	return snap

func restore_snapshot(data: Dictionary) -> void:
	if data.has("start_pos_a"):
		var sp = data["start_pos_a"]
		_start_pos_a = Vector3(sp[0], sp[1], sp[2])
	if data.has("start_pos_b"):
		var sp = data["start_pos_b"]
		_start_pos_b = Vector3(sp[0], sp[1], sp[2])
	if data.has("start_scale_a"):
		var ss = data["start_scale_a"]
		_start_scale_a = Vector3(ss[0], ss[1], ss[2])
	if data.has("start_scale_b"):
		var ss = data["start_scale_b"]
		_start_scale_b = Vector3(ss[0], ss[1], ss[2])

	.restore_snapshot(data)

# --- EDITOR PREVIEW ---

func _process(_delta):
	if Engine.editor_hint:
		if not _initialized:
			# Cache meshes
			if mesh_a_path:
				_mesh_a = get_node_or_null(mesh_a_path)
			if mesh_b_path:
				_mesh_b = get_node_or_null(mesh_b_path)

			if _mesh_a:
				_start_pos_a = _mesh_a.translation
				_start_scale_a = _mesh_a.scale
			if _mesh_b:
				_start_pos_b = _mesh_b.translation
				_start_scale_b = _mesh_b.scale
			_initialized = true
