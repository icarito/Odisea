extends Spatial

export(Material) var base_material setget set_base_material
export(Color) var lever_color = Color(1, 0.5, 0.1) setget set_lever_color


onready var base = $LeverBase
onready var lever = $LeverBase/RotatingLever

func set_base_material(mat):
	base_material = mat
	if base and base_material:
		base.material = base_material

func set_lever_color(c):
	       lever_color = c
	       if lever:
		       var mesh_instance = _find_mesh_instance(lever)
		       if mesh_instance:
			       var mat = mesh_instance.get_surface_material(0)
			       if not mat:
				       mat = SpatialMaterial.new()
				       mesh_instance.set_surface_material(0, mat)
			       # SpatialMaterial always has 'albedo_color', so set it directly
			       mat.albedo_color = lever_color

# Recursively find the first MeshInstance in the node tree

func _find_mesh_instance(node):
       if node is MeshInstance:
	       return node
       for child in node.get_children():
	       var found = _find_mesh_instance(child)
	       if found:
		       return found
       return null

func _ready():
       set_base_material(base_material)
       set_lever_color(lever_color)
