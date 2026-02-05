extends InteractableBaseV2
class_name DualSlidingObjectV2
tool

# DualSlidingObjectV2.gd - Deterministic Dual Sliding Door/Hatch
# Controls two separate spatial nodes moving in opposite (or defined) directions based on a single anim_progress.

# --- EXPORTED TUNING ---
export(NodePath) var node_a_path
export(NodePath) var node_b_path
export(Vector3) var slide_vector_a := Vector3(-1, 0, 0)
export(Vector3) var slide_vector_b := Vector3(1, 0, 0)
export(int, "Linear", "EaseInOut", "EaseIn", "EaseOut") var easing_type := 1

# --- INTERNAL STATE ---
var _start_pos_a := Vector3.ZERO
var _start_pos_b := Vector3.ZERO
var _initialized := false

var node_a: Spatial = null
var node_b: Spatial = null

func _ready():
	_setup_nodes()
	_initialized = true

	# Call parent ready
	._ready()

func _setup_nodes():
	if node_a_path:
		node_a = get_node_or_null(node_a_path)
	if node_b_path:
		node_b = get_node_or_null(node_b_path)

	if node_a:
		_start_pos_a = node_a.translation
	if node_b:
		_start_pos_b = node_b.translation

func _update_visuals() -> void:
	"""Interpolate both nodes based on animation progress."""
	if not _initialized:
		_setup_nodes()
		_initialized = true

	if not node_a or not node_b:
		return

	var eased = _apply_easing(anim_progress)
	node_a.translation = _start_pos_a.linear_interpolate(_start_pos_a + slide_vector_a, eased)
	node_b.translation = _start_pos_b.linear_interpolate(_start_pos_b + slide_vector_b, eased)

func _apply_easing(t: float) -> float:
	match easing_type:
		0: return t # Linear
		1: return _ease_in_out(t)
		2: return _ease_in(t)
		3: return _ease_out(t)
	return t

# --- SNAPSHOT OVERRIDE ---

func get_snapshot() -> Dictionary:
	var snap = .get_snapshot()
	snap["start_pos_a"] = [_start_pos_a.x, _start_pos_a.y, _start_pos_a.z]
	snap["start_pos_b"] = [_start_pos_b.x, _start_pos_b.y, _start_pos_b.z]
	return snap

func restore_snapshot(data: Dictionary) -> void:
	if data.has("start_pos_a"):
		var sp = data["start_pos_a"]
		_start_pos_a = Vector3(sp[0], sp[1], sp[2])
	if data.has("start_pos_b"):
		var sp = data["start_pos_b"]
		_start_pos_b = Vector3(sp[0], sp[1], sp[2])

	.restore_snapshot(data)

func _process(_delta):
	if Engine.editor_hint:
		if not _initialized:
			_setup_nodes()
			_initialized = true
