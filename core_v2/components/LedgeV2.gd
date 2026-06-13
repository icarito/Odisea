tool
extends StaticBody

# LedgeV2.gd - Hanging surface for Odisea
const TRAVERSAL_COLLISION_LAYER_BIT := 2

export(float) var ledge_width := 2.0 setget set_ledge_width
var interaction_text := "Grab Ledge"
var is_interactable := true

func _ready():
	_refresh_preview()

func set_ledge_width(value: float) -> void:
	ledge_width = max(0.5, value)
	_refresh_preview()

func _refresh_preview() -> void:
	add_to_group("ledge")
	add_to_group("interactable")

	# Keep traversal props collidable for gameplay, but off the camera terrain mask.
	collision_layer &= ~(1 << 0)
	collision_layer |= (1 << TRAVERSAL_COLLISION_LAYER_BIT)
	_ensure_body_collision()
	_build_visual()

func set_highlighted(_active: bool, _color: Color = Color.cyan):
	pass

func get_hang_half_width() -> float:
	return max(0.2, (ledge_width * 0.5) - 0.15)

func _ensure_body_collision() -> void:
	var col_shape = get_node_or_null("CollisionShape")
	if col_shape == null:
		col_shape = CollisionShape.new()
		col_shape.name = "CollisionShape"
		add_child(col_shape)

	var box = BoxShape.new()
	box.extents = Vector3(ledge_width * 0.5, 0.12, 0.12)
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

	var ledge_material = SpatialMaterial.new()
	ledge_material.albedo_color = Color(0.72, 0.76, 0.82, 1.0)
	ledge_material.roughness = 0.9
	ledge_material.metallic = 0.15

	_add_box_mesh(visual, "Lip", Vector3(0, 0, 0), Vector3(ledge_width, 0.08, 0.18), ledge_material)
	_add_box_mesh(visual, "BracketLeft", Vector3(-ledge_width * 0.28, -0.12, 0.02), Vector3(0.12, 0.18, 0.12), ledge_material)
	_add_box_mesh(visual, "BracketRight", Vector3(ledge_width * 0.28, -0.12, 0.02), Vector3(0.12, 0.18, 0.12), ledge_material)

func _add_box_mesh(parent: Spatial, node_name: String, local_pos: Vector3, size: Vector3, material: Material) -> void:
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = node_name
	var cube_mesh = CubeMesh.new()
	cube_mesh.size = size
	mesh_instance.mesh = cube_mesh
	mesh_instance.translation = local_pos
	mesh_instance.material_override = material
	parent.add_child(mesh_instance)
