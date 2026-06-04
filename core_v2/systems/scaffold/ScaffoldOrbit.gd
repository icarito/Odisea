extends Spatial
class_name ScaffoldOrbit

# FD-052: Cylindrical layout for scaffold chunks.
#
# Scaffold uses a single canonical convention:
# - Cylinder axis: Z
# - Arc axis: X  (theta = flat_x / base_radius)
# - Radial offset: Y
#
# Chunk name encodes its grid key: "Chunk_CX_CZ"
# We derive flat_origin from the chunk name + stream params so we never
# depend on translation timing (stream sets translation AFTER add_child).

export(float) var base_radius := 190.0 setget set_base_radius

var _stream: ScaffoldStreamController = null
var _initialized := false

func _ready() -> void:
	for child in get_children():
		if child is ScaffoldStreamController:
			_setup_stream(child as ScaffoldStreamController)
			break

	connect("child_entered_tree", self, "_on_child_entered")
	_initialized = true

func _on_child_entered(child: Node) -> void:
	if child is ScaffoldStreamController and _stream == null:
		_setup_stream(child as ScaffoldStreamController)

func _setup_stream(s: ScaffoldStreamController) -> void:
	_stream = s
	_stream.connect("child_entered_tree", self, "_on_stream_child_entered")
	# Reposition chunks already present
	call_deferred("_reposition_all")

func _on_stream_child_entered(child: Node) -> void:
	if child.name.begins_with("Chunk_"):
		call_deferred("_reposition_chunk", child)

func _reposition_chunk(chunk: Spatial) -> void:
	if not is_instance_valid(chunk):
		return
	var flat: Vector3 = _flat_origin_from_chunk(chunk)
	chunk.set_meta("flat_origin", flat)
	chunk.transform = _cylindrical_transform(flat, _chunk_local_center())

func _flat_origin_from_chunk(chunk: Spatial) -> Vector3:
	# Parse "Chunk_CX_CZ" and call the stream's own method to get the canonical
	# local origin — same formula the stream uses, no timing issues.
	var parts: Array = chunk.name.split("_")
	if parts.size() >= 3:
		var key := Vector2(float(parts[1]), float(parts[2]))
		return _stream._chunk_to_local_origin(key)
	return chunk.translation

func _cylindrical_transform(flat: Vector3, local_pivot: Vector3) -> Transform:
	var flat_pivot: Vector3 = flat + local_pivot
	var theta: float = flat_pivot.x / base_radius
	var r: float     = base_radius - flat_pivot.y
	var pos := Vector3(
		r * sin(theta),
		base_radius - r * cos(theta),
		flat_pivot.z
	)
	var basis := Basis(Vector3(0.0, 0.0, 1.0), theta)
	return Transform(basis, pos - basis.xform(local_pivot))

func _chunk_local_center() -> Vector3:
	if _stream == null:
		return Vector3.ZERO
	return Vector3(
		float(_stream.chunk_height - 1) * _stream.cell_size * 0.5,
		0.0,
		float(_stream.chunk_length - 1) * _stream.cell_size * 0.5
	)

# ── Setters ────────────────────────────────────────────────────────────────

func set_base_radius(v: float) -> void:
	base_radius = v
	if _initialized:
		_reposition_all()

func _reposition_all() -> void:
	if _stream == null:
		return
	for child in _stream.get_children():
		if child.name.begins_with("Chunk_"):
			_reposition_chunk(child as Spatial)
