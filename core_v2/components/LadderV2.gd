extends StaticBody

# LadderV2.gd - Climbing surface for Odisea

func _ready():
	add_to_group("ladder")
	add_to_group("interactable")

	# Ensure correct collision layer for player interaction
	collision_layer |= (1 << 0) # Layer 1 (Environment)

	# Add collision shape for detection
	var col_shape = CollisionShape.new()
	var box = BoxShape.new()
	box.extents = Vector3(0.5, 2.0, 0.1)
	col_shape.shape = box
	add_child(col_shape)

	# Visual representation for validation
	var mesh_instance = MeshInstance.new()
	var cube_mesh = CubeMesh.new()
	cube_mesh.size = Vector3(1.0, 4.0, 0.2)
	mesh_instance.mesh = cube_mesh
	add_child(mesh_instance)

func interact():
	# Standard interaction can also trigger climbing if needed
	pass

export(bool) var is_1d_ladder := true
var interaction_text := "Climb Ladder"
var is_interactable := true

func set_highlighted(active: bool, color: Color = Color.cyan):
	# Visual feedback for interaction range
	pass
