extends Spatial
class_name CylinderRotator

# Cylindrical scaffold visualizer.
#
# Canonical convention:
# - Cylinder axis: Z
# - Arc axis: X  (theta = x / base_radius)
# - Radial offset: Y
#
# Each frame, all loaded chunks are repositioned so the arc under the player
# always appears flat (theta_relative = 0). Camera roll matches this offset.
# Physics is handled by PhysicalTerrace only — chunks have no collision.

export(float) var base_radius := 190.0 setget set_base_radius
export(NodePath) var stream_path := NodePath("ScaffoldStreamController")
export(NodePath) var physical_terrace_path := NodePath("../PhysicalTerrace")
export(NodePath) var player_path := NodePath("../Pilot")
export(bool) var enable_camera_tracking := true
export(float) var camera_lerp_speed := 10.0
export(float) var support_probe_height := 8.0
export(float) var support_probe_depth := 24.0

var _stream: ScaffoldStreamController = null
var _physical_terrace: StaticBody = null
var _player: Spatial = null
var _stream_connected := false
var _current_roll := 0.0


func _ready() -> void:
	call_deferred("_init")

func _init() -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	_stream = _resolve_path(stream_path) as ScaffoldStreamController
	_physical_terrace = _resolve_path(physical_terrace_path) as StaticBody
	_player = _resolve_path(player_path) as Spatial
	if _player == null:
		_player = _get_player()
	if _stream == null:
		return
	_sync_radius()
	_ensure_stream_connected()

func set_base_radius(v: float) -> void:
	base_radius = v
	if is_inside_tree():
		_sync_radius()

func _sync_radius() -> void:
	if _stream != null and is_instance_valid(_stream):
		_stream.cylinder_radius = base_radius
	for child in get_children():
		if child.get_script() != null and child.get_script().resource_path.get_file() == "ScaffoldOrbit.gd":
			child.set("base_radius", base_radius)

func _on_stream_child(child: Node) -> void:
	if child.name.begins_with("Chunk_"):
		call_deferred("_reposition_all_chunks")

func _reposition_all_chunks() -> void:
	if _stream == null or not is_instance_valid(_stream):
		return
	var player_local_x: float = _get_player_local_x()
	for child in _stream.get_children():
		if child.name.begins_with("Chunk_") and child is Spatial:
			_apply_chunk_transform(child as Spatial, player_local_x)

func _apply_chunk_transform(chunk: Spatial, player_local_x: float) -> void:
	if not is_instance_valid(chunk):
		return
	var flat_origin: Vector3 = _flat_origin_from_chunk_name(chunk.name)
	var local_pivot: Vector3 = _chunk_local_center()
	chunk.transform = _cylindrical_transform_at(flat_origin, local_pivot, player_local_x)

func _flat_origin_from_chunk_name(chunk_name: String) -> Vector3:
	var parts: Array = chunk_name.split("_")
	if parts.size() < 3:
		return Vector3.ZERO
	var key := Vector2(float(parts[1]), float(parts[2]))
	return _stream._chunk_to_local_origin(key)

func _chunk_local_center() -> Vector3:
	return Vector3(
		float(_stream.chunk_height - 1) * _stream.cell_size * 0.5,
		0.0,
		float(_stream.chunk_length - 1) * _stream.cell_size * 0.5
	)

func _get_player_local_x() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	var stream_origin_x: float = _stream.global_translation.x if _stream.is_inside_tree() else 0.0
	return _player.global_translation.x - stream_origin_x

# Places a chunk so the arc position corresponding to player_local_x is flat.
# flat.x is in stream-local space. The result is also in stream-local space.
func _cylindrical_transform_at(flat: Vector3, local_pivot: Vector3, player_local_x: float) -> Transform:
	var flat_pivot: Vector3 = flat + local_pivot
	# Angle relative to player: chunk at player_local_x gets theta=0 (flat).
	var theta: float = (flat_pivot.x - player_local_x) / base_radius
	var radius: float = base_radius - flat_pivot.y
	# Position: at theta=0 the chunk sits at (player_local_x, 0). Adjacent chunks curve up.
	var pos := Vector3(
		player_local_x + radius * sin(theta),
		base_radius - radius * cos(theta),
		flat_pivot.z
	)
	var basis := Basis(Vector3(0.0, 0.0, 1.0), theta)
	return Transform(basis, pos - basis.xform(local_pivot))

func _physics_process(delta: float) -> void:
	if _stream == null:
		_stream = _resolve_path(stream_path) as ScaffoldStreamController
	if _stream != null:
		_ensure_stream_connected()
	if _player == null:
		_player = _get_player()
	if _player == null:
		return
	if _physical_terrace == null:
		_physical_terrace = _resolve_path(physical_terrace_path) as StaticBody
	if _physical_terrace != null and is_instance_valid(_physical_terrace):
		_physical_terrace.global_transform = Transform(
			Basis.IDENTITY,
			Vector3(_player.global_translation.x, 0.0, _player.global_translation.z)
		)

	# Reposition all chunks every frame so the arc under the player stays flat.
	var player_local_x: float = _get_player_local_x()
	if _stream != null and is_instance_valid(_stream):
		for child in _stream.get_children():
			if child.name.begins_with("Chunk_") and child is Spatial:
				_apply_chunk_transform(child as Spatial, player_local_x)

	# Camera roll matches player_local_x / base_radius — same reference as chunk placement.
	var player_theta: float = player_local_x / max(0.001, base_radius)
	var lerp_t: float = min(1.0, camera_lerp_speed * delta)
	_current_roll = lerp_angle(_current_roll, player_theta, lerp_t)
	if enable_camera_tracking and "camera_basis_prefix" in _player:
		_player.camera_basis_prefix = Basis(Vector3.FORWARD, _current_roll)
	elif "camera_basis_prefix" in _player:
		_player.camera_basis_prefix = Basis.IDENTITY

func get_expected_up_at_global(global_pos: Vector3) -> Vector3:
	var theta: float = global_pos.x / max(0.001, base_radius)
	return Vector3(-sin(theta), cos(theta), 0.0).normalized()

func _get_player() -> Spatial:
	var tree = get_tree()
	if tree == null:
		return null
	var configured := _resolve_path(player_path)
	if configured is Spatial:
		return configured as Spatial
	for p in get_tree().get_nodes_in_group("player"):
		if p is Spatial:
			return p as Spatial
	return null

func _resolve_path(path: NodePath) -> Node:
	if path.is_empty():
		return null
	var node := get_node_or_null(path)
	if node != null:
		return node
	if get_parent() != null:
		node = get_parent().get_node_or_null(path)
	return node

func _find_chunk_root(node: Node) -> Spatial:
	var current := node
	while current != null:
		if current is Spatial and current.name.begins_with("Chunk_"):
			return current as Spatial
		current = current.get_parent()
	return null

func _ensure_stream_connected() -> void:
	if _stream == null or not is_instance_valid(_stream):
		return
	if _stream_connected:
		return
	if not _stream.is_connected("child_entered_tree", self, "_on_stream_child"):
		_stream.connect("child_entered_tree", self, "_on_stream_child")
	_stream_connected = true

func _world_to_chunk_safe(global_pos: Vector3) -> Vector2:
	if _stream == null or not is_instance_valid(_stream):
		return Vector2.ZERO
	return Vector2(
		floor(global_pos.x / _stream._chunk_step_x()),
		floor(global_pos.z / _stream._chunk_step_z())
	)
