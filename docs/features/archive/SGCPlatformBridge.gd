extends Spatial
class_name SGCPlatformBridge

# FD-052: SGC Platform Bridge
# OdiseaExterior-style support selection:
# - player physics stays standard
# - camera roll stays zero
# - WorldRotator aligns the currently supported chunk to global up

export(bool) var enabled := false
export(NodePath) var rotator_path := NodePath("..")
export(NodePath) var player_path := NodePath("../../Pilot")
export(float) var ray_length := 4.0

var _rotator: Spatial = null
var _player: Spatial = null
var _active_support: Spatial = null
var _was_grounded := false

func _ready() -> void:
	call_deferred("_init_connections")

func _init_connections() -> void:
	if not enabled:
		return
	_rotator = get_node_or_null(rotator_path) as Spatial
	_player = get_node_or_null(player_path) as Spatial
	if _player == null:
		_player = _get_player()
	if _rotator == null:
		push_error("SGCPlatformBridge: rotator not found at %s" % rotator_path)
	if _player == null:
		push_error("SGCPlatformBridge: player not found at %s" % player_path)

func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	if _rotator == null or _player == null:
		return
	var grounded: bool = _is_grounded()
	var support_now: Spatial = _find_current_support()
	if support_now == null:
		_was_grounded = grounded
		return
	var snap_immediately: bool = grounded and (not _was_grounded or support_now != _active_support)
	if support_now != _active_support or snap_immediately:
		_active_support = support_now
		_rotator.call("set_active_platform", support_now, snap_immediately)
	_was_grounded = grounded

func _find_current_support() -> Spatial:
	var from_floor: Spatial = _find_support_from_floor_contacts()
	if from_floor != null:
		return from_floor
	return _find_support_from_origin(_player.global_transform.origin, 0.2, ray_length)

func _find_support_from_floor_contacts() -> Spatial:
	if not _player.has_method("is_on_floor") or not _player.has_method("get_slide_count") or not _player.has_method("get_slide_collision"):
		return null
	if not _player.is_on_floor():
		return null
	for i in range(_player.get_slide_count()):
		var collision: KinematicCollision = _player.get_slide_collision(i)
		if collision == null:
			continue
		var support: Spatial = _resolve_support_root(collision.collider)
		if support != null:
			return support
	return null

func _find_support_from_origin(origin: Vector3, up_offset: float, down_length: float) -> Spatial:
	var space_state = _player.get_world().direct_space_state
	var from: Vector3 = origin + Vector3.UP * up_offset
	var to: Vector3 = from + Vector3.DOWN * down_length
	var hit: Dictionary = space_state.intersect_ray(from, to, [_player], _player.collision_mask)
	if hit.empty():
		return null
	return _resolve_support_root(hit.get("collider", null))

func _is_grounded() -> bool:
	if _player.has_method("is_effectively_grounded"):
		return _player.is_effectively_grounded()
	if _player.has_method("is_on_floor"):
		return _player.is_on_floor()
	return false

func _resolve_support_root(collider: Object) -> Spatial:
	if not collider is Node:
		return null
	var node: Node = collider as Node
	while node != null:
		if node is Spatial and (node.name.begins_with("Chunk_") or node.name == "StarterScaffold"):
			return node as Spatial
		node = node.get_parent()
	return null

func _get_player() -> Spatial:
	for p in get_tree().get_nodes_in_group("player"):
		if p is Spatial:
			return p as Spatial
	return null
