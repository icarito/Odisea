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
# always appears flat (theta_relative = 0). Camera stays upright.
# Physics: PhysicalTerrace for the player floor, chunk collisions for detail.

export(float) var base_radius := 190.0 setget set_base_radius
export(NodePath) var stream_path := NodePath("ScaffoldStreamController")
export(NodePath) var physical_terrace_path := NodePath("../PhysicalTerrace")
export(NodePath) var player_path := NodePath("../Pilot")
export(float) var support_probe_height := 8.0
export(float) var support_probe_depth := 24.0

var _stream: ScaffoldStreamController = null
var _physical_terrace: StaticBody = null
var _player: Spatial = null
var _stream_connected := false
var _last_player_local_x := NAN
# While the player is inside an airlock chamber (entering it, or appearing there
# after a seamless scene swap) the cylinder must NOT chase the player's radial
# position: the player is still being repositioned by AirlockManager, so a frame
# computed against a stale/baked-in position would snap the whole scaffold and
# the camera. We mirror the player's "airlock_tracking_suspended" meta — the same
# flag AirlockZoneV2 toggles and WorldRotator honours in the exterior. Tracking
# stays frozen until the player physically leaves the destination chamber.
var _airlock_suspended := false
# Set true once a valid (non-suspended) player position has been applied. While
# false, the first valid frame snaps directly instead of being treated as motion,
# so there is no visible chunk/terrace jump on scene arrival.
var _settled := false


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
		_reposition_all_chunks()

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

func _physics_process(_delta: float) -> void:
	if _stream == null:
		_stream = _resolve_path(stream_path) as ScaffoldStreamController
	if _stream != null:
		_ensure_stream_connected()
	# Re-resolve if the cached player was freed (e.g. the baked-in Pilot is
	# replaced by the reparented player after a seamless airlock transition).
	if not is_instance_valid(_player) or _is_baked_player_replaced():
		_player = _get_player()
	if not is_instance_valid(_player):
		return

	# Airlock gate: while the player is inside a chamber, AirlockManager is still
	# repositioning it. Repositioning chunks/terrace now would chase a stale
	# position and snap the world. Freeze until the chamber is exited. On the
	# transition back to non-suspended, force the next frame to snap (not lerp)
	# by clearing _settled so the first valid frame is treated as a teleport.
	var suspended := _is_player_airlock_suspended()
	if suspended != _airlock_suspended:
		_airlock_suspended = suspended
		if not suspended:
			# Player just left the chamber — drop the settled flag so the first
			# real position applies as a snap and _reposition_all_chunks() runs
			# unconditionally below.
			_settled = false
	if suspended:
		# Keep the scaffold camera upright even while frozen so the arrival frame
		# never inherits a tilted prefix from the source scene's rotator.
		if "camera_basis_prefix" in _player:
			_player.camera_basis_prefix = Basis.IDENTITY
		return

	if _physical_terrace == null:
		_physical_terrace = _resolve_path(physical_terrace_path) as StaticBody
	if _physical_terrace != null and is_instance_valid(_physical_terrace):
		_physical_terrace.global_transform = Transform(
			Basis.IDENTITY,
			Vector3(_player.global_translation.x, 0.0, _player.global_translation.z)
		)

	# Reposition chunks so the arc under the player stays flat.
	# Skip when player hasn't moved (majority of frames) — the chunk arc only
	# depends on player_local_x. The first settled frame always applies so the
	# scaffold snaps into place once around the just-arrived player.
	var player_local_x: float = _get_player_local_x()
	if not _settled or is_nan(_last_player_local_x) or abs(player_local_x - _last_player_local_x) >= 0.1:
		_last_player_local_x = player_local_x
		_settled = true
		if _stream != null and is_instance_valid(_stream):
			for child in _stream.get_children():
				if child.name.begins_with("Chunk_") and child is Spatial:
					_apply_chunk_transform(child as Spatial, player_local_x)

	if "camera_basis_prefix" in _player:
		_player.camera_basis_prefix = Basis.IDENTITY

# True while the player node is flagged as inside an airlock chamber. Mirrors the
# meta AirlockZoneV2 sets and WorldRotator honours, so the scaffold cylinder and
# the exterior dome pause tracking on the same condition.
func _is_player_airlock_suspended() -> bool:
	if not is_instance_valid(_player):
		return false
	return _player.has_meta("airlock_tracking_suspended") \
		and bool(_player.get_meta("airlock_tracking_suspended"))

# After a seamless airlock swap the baked-in Pilot is freed and the held player
# is reparented in. If our cached _player is the (now stale) baked-in node while a
# different live player exists in the group, force a re-resolve so we don't track
# a corpse for a frame.
func _is_baked_player_replaced() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _player.is_in_group("player"):
		return false
	var tree = get_tree()
	if tree == null:
		return false
	for p in tree.get_nodes_in_group("player"):
		if is_instance_valid(p) and p != _player:
			return true
	return false

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
