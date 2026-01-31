extends Spatial

func _ready():
	# Brute force register ALL meshes in the scene for the test
	_register_recursive(self)

func _register_recursive(node: Node):
	# Force apply material if needed for the test to work on generic CSG/Meshes
	var forced_mat = load("res://materials/WallOcclusionTest.tres")
	
	if node is MeshInstance:
		var mat = node.get_active_material(0)
		if not (mat is ShaderMaterial):
			node.material_override = forced_mat
			mat = forced_mat
			print("TestOcclusionScene: Forced material on MeshInstance: ", node.name)
		
		if mat is ShaderMaterial:
			WallOcclusionManager.register_material(mat)
			print("TestOcclusionScene: Registered MeshInstance material: ", node.name)

	elif node is CSGShape:
		var mat = node.material
		if not (mat is ShaderMaterial):
			node.material = forced_mat
			mat = forced_mat
			print("TestOcclusionScene: Forced material on CSGShape: ", node.name)
			
		if mat is ShaderMaterial:
			WallOcclusionManager.register_material(mat)
			print("TestOcclusionScene: Registered CSGShape material: ", node.name)
			
	for child in node.get_children():
		_register_recursive(child)
