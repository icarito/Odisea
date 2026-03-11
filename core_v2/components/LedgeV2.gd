extends StaticBody

# LedgeV2.gd - Hanging surface for Odisea

func _ready():
	add_to_group("ledge")
	add_to_group("interactable")

	collision_layer |= (1 << 0)

	var col_shape = CollisionShape.new()
	var box = BoxShape.new()
	box.extents = Vector3(1.0, 0.1, 0.1) # Wide ledge
	col_shape.shape = box
	add_child(col_shape)

	# Visual representation for validation
	var mesh_instance = MeshInstance.new()
	var cube_mesh = CubeMesh.new()
	cube_mesh.size = Vector3(2.0, 0.2, 0.2)
	mesh_instance.mesh = cube_mesh
	add_child(mesh_instance)

var interaction_text := "Grab Ledge"
var is_interactable := true

func set_highlighted(active: bool, color: Color = Color.cyan):
	pass
