extends Spatial
class_name ScaffoldOrbit

# FD-XXX: Cylindrical layout for scaffold chunks
# Translates flat (x, z, y) coordinates to cylindrical (r, theta, z).

export(float) var base_radius := 330.0 setget set_base_radius
export(float) var angular_scale := 0.003 setget set_angular_scale
export(bool) var follow_player_flat := true

var _stream_controller: ScaffoldStreamController = null
var _player_proxy: Spatial = null
var _original_player_path: NodePath
var _initialized := false

func _ready() -> void:
	_player_proxy = Spatial.new()
	_player_proxy.name = "FlatPlayerProxy"
	# Temporarily add as child to avoid orphan, _set_stream_controller will move it.
	add_child(_player_proxy)

	_find_stream_controller()
	connect("child_entered_tree", self, "_on_my_child_entered")
	_initialized = true

func _find_stream_controller() -> void:
	for child in get_children():
		if child is ScaffoldStreamController:
			_set_stream_controller(child)
			return

func _on_my_child_entered(child: Node) -> void:
	if child is ScaffoldStreamController:
		_set_stream_controller(child)

func _set_stream_controller(controller: ScaffoldStreamController) -> void:
	if _stream_controller == controller:
		return

	if _stream_controller:
		if _stream_controller.is_connected("child_entered_tree", self, "_on_chunk_entered"):
			_stream_controller.disconnect("child_entered_tree", self, "_on_chunk_entered")

	_stream_controller = controller
	if _stream_controller:
		if not _stream_controller.is_connected("child_entered_tree", self, "_on_chunk_entered"):
			_stream_controller.connect("child_entered_tree", self, "_on_chunk_entered")

		_original_player_path = _stream_controller.player_path
		if follow_player_flat:
			call_deferred("_apply_player_proxy")

		_reposition_all_chunks()

func _apply_player_proxy() -> void:
	if _stream_controller and _player_proxy:
		if _player_proxy.get_parent():
			_player_proxy.get_parent().remove_child(_player_proxy)
		_stream_controller.add_child(_player_proxy)
		_stream_controller.player_path = _stream_controller.get_path_to(_player_proxy)

func _on_chunk_entered(node: Node) -> void:
	if not node is Spatial or not node.name.begins_with("Chunk_"):
		return
	_reposition_chunk(node)

func set_base_radius(v: float) -> void:
	base_radius = v
	if _initialized:
		_reposition_all_chunks()

func set_angular_scale(v: float) -> void:
	angular_scale = v
	if _initialized:
		_reposition_all_chunks()

func _reposition_all_chunks() -> void:
	if not _stream_controller:
		return
	for child in _stream_controller.get_children():
		if child.name.begins_with("Chunk_"):
			_reposition_chunk(child)

func _reposition_chunk(chunk: Spatial) -> void:
	var flat_pos: Vector3
	if chunk.has_meta("original_flat_pos"):
		flat_pos = chunk.get_meta("original_flat_pos")
	else:
		flat_pos = chunk.translation
		chunk.set_meta("original_flat_pos", flat_pos)

	# flat_pos is relative to _stream_controller
	# world_flat_pos is position relative to ScaffoldOrbit
	var world_flat_pos = _stream_controller.translation + flat_pos

	var mapped_xf = _map_flat_to_cylindrical(world_flat_pos)

	# chunk.transform is relative to _stream_controller
	chunk.transform = _stream_controller.transform.affine_inverse() * mapped_xf

func _map_flat_to_cylindrical(flat_pos: Vector3) -> Transform:
	var r = base_radius - flat_pos.y
	var theta = flat_pos.x * angular_scale

	var x = r * sin(theta)
	var y = base_radius - r * cos(theta)
	var z = flat_pos.z

	var pos = Vector3(x, y, z)
	var basis = Basis(Vector3(0, 0, 1), theta)

	return Transform(basis, pos)

func _process(_delta: float) -> void:
	if follow_player_flat:
		_update_player_proxy()

func _update_player_proxy() -> void:
	if not _stream_controller or abs(angular_scale) < 0.00001:
		return

	var player_node = _get_real_player_node()
	if not player_node:
		return

	var real_player_pos = player_node.global_translation

	# Map real world position back to flat space relative to ScaffoldOrbit
	var local_player_pos = global_transform.affine_inverse().xform(real_player_pos)

	var dy = base_radius - local_player_pos.y
	var theta = atan2(local_player_pos.x, dy)
	var r = sqrt(local_player_pos.x * local_player_pos.x + dy * dy)

	var z_flat = local_player_pos.z
	var y_flat = base_radius - r
	var x_flat = theta / angular_scale

	var flat_pos_rel_orbit = Vector3(x_flat, y_flat, z_flat)
	_player_proxy.translation = flat_pos_rel_orbit - _stream_controller.translation

func _get_real_player_node() -> Spatial:
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p is Spatial and p != _player_proxy:
			return p

	if not _original_player_path.is_empty():
		var node = get_node_or_null(_original_player_path)
		if node is Spatial and node != _player_proxy:
			return node

	return null
