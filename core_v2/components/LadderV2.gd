tool
extends StaticBody

# LadderV2.gd - Climbing surface for Odisea
const TRAVERSAL_COLLISION_LAYER_BIT := 2

export(bool) var is_1d_ladder := true setget set_is_1d_ladder
export(float) var climb_half_height := 1.5 setget set_climb_half_height
export(float) var attach_depth := 0.35
export(float) var rung_spacing := 0.42 setget set_rung_spacing
export(float) var hand_grip_half_width := 0.34
export(Color) var albedo_color := Color(0.78, 0.82, 0.88, 1.0) setget set_albedo_color
var interaction_text := "Climb Ladder"
var is_interactable := true

func _ready():
	_refresh_preview()

func set_is_1d_ladder(value: bool) -> void:
	is_1d_ladder = value
	_refresh_preview()

func set_climb_half_height(value: float) -> void:
	climb_half_height = max(0.5, value)
	_refresh_preview()

func set_rung_spacing(value: float) -> void:
	rung_spacing = max(0.18, value)
	_refresh_preview()

func set_albedo_color(value: Color) -> void:
	albedo_color = value
	_refresh_preview()

func _refresh_preview() -> void:
	add_to_group("ladder")
	add_to_group("interactable")

	# Keep traversal props collidable for gameplay, but off the camera terrain mask.
	collision_layer &= ~(1 << 0)
	collision_layer |= (1 << TRAVERSAL_COLLISION_LAYER_BIT)
	_ensure_body_collision()
	_build_visual()

func interact():
	# Standard interaction can also trigger climbing if needed
	pass

func set_highlighted(_active: bool, _color: Color = Color.cyan):
	# Visual feedback for interaction range
	pass

func get_climb_limits() -> Vector2:
	return Vector2(-climb_half_height, climb_half_height)

func get_climb_anchor() -> Vector3:
	var forward = -global_transform.basis.z
	return global_transform.origin - forward * attach_depth

func get_climb_hand_targets(world_y: float, progress: float, requested_half_width: float = 0.36) -> Dictionary:
	var _right_dir = global_transform.basis.x.normalized()
	var grip_half_width = min(max(0.12, requested_half_width), max(0.16, hand_grip_half_width))
	var hand_center_local_y = clamp(_world_y_to_local(world_y), -climb_half_height + 0.25, climb_half_height - 0.25)
	var cycle = fposmod(progress, 1.0)
	var hand_wave = sin(cycle * PI * 2.0)
	var hand_offset = hand_wave * min(0.22, rung_spacing * 0.42)
	var left_local = Vector3(-grip_half_width, hand_center_local_y + hand_offset, 0.0)
	var right_local = Vector3(grip_half_width, hand_center_local_y - hand_offset, 0.0)
	return {
		"left": global_transform.xform(left_local),
		"right": global_transform.xform(right_local),
	}

func get_climb_rung_positions() -> Array:
	var positions := []
	for y in _get_rung_local_ys():
		positions.append(global_transform.xform(Vector3(0.0, y, 0.0)))
	return positions

func _world_y_to_local(world_y: float) -> float:
	return world_y - global_transform.origin.y

func _find_nearest_rung_index(local_y: float, rung_ys: Array) -> int:
	var best_index := 0
	var best_dist := INF
	for i in range(rung_ys.size()):
		var dist = abs(float(rung_ys[i]) - local_y)
		if dist < best_dist:
			best_dist = dist
			best_index = i
	return best_index

func _get_rung_local_ys() -> Array:
	var values := []
	var total_height: float = climb_half_height * 2.0
	var usable_height: float = max(0.3, total_height - 0.5)
	var rung_count: int = max(2, int(floor(usable_height / max(0.18, rung_spacing))) + 1)
	var rung_bottom: float = -climb_half_height + 0.25
	var rung_top: float = climb_half_height - 0.25
	var actual_spacing: float = 0.0 if rung_count <= 1 else (rung_top - rung_bottom) / float(rung_count - 1)
	for i in range(rung_count):
		values.append(rung_bottom + actual_spacing * float(i))
	return values

func _ensure_body_collision() -> void:
	var col_shape = get_node_or_null("CollisionShape")
	if col_shape == null:
		col_shape = CollisionShape.new()
		col_shape.name = "CollisionShape"
		add_child(col_shape)

	var box = BoxShape.new()
	box.extents = Vector3(0.45, climb_half_height, 0.12)
	col_shape.shape = box

func _build_visual() -> void:
	var legacy_mesh = get_node_or_null("MeshInstance")
	if legacy_mesh:
		legacy_mesh.visible = false

	var existing_visual = get_node_or_null("Visual")
	if existing_visual:
		remove_child(existing_visual)
		existing_visual.free()

	var visual = Spatial.new()
	visual.name = "Visual"
	add_child(visual)

	var ladder_material = SpatialMaterial.new()
	ladder_material.albedo_color = albedo_color
	ladder_material.roughness = 0.85
	ladder_material.metallic = 0.2

	_add_box_mesh(visual, "RailLeft", Vector3(-0.28, 0, 0), Vector3(0.08, climb_half_height * 2.0, 0.08), ladder_material)
	_add_box_mesh(visual, "RailRight", Vector3(0.28, 0, 0), Vector3(0.08, climb_half_height * 2.0, 0.08), ladder_material)

	var rung_ys = _get_rung_local_ys()
	for i in range(rung_ys.size()):
		var y: float = rung_ys[i]
		_add_box_mesh(visual, "Rung%d" % i, Vector3(0, y, 0), Vector3(0.62, 0.05, 0.08), ladder_material)

func _add_box_mesh(parent: Spatial, node_name: String, local_pos: Vector3, size: Vector3, material: Material) -> void:
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = node_name
	var cube_mesh = CubeMesh.new()
	cube_mesh.size = size
	mesh_instance.mesh = cube_mesh
	mesh_instance.translation = local_pos
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
