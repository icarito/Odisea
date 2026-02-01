extends Node

var player_node: Spatial
var camera_node: Camera
var is_occlusion_active: bool = false
var hole_radius: float = 1.5
var registered_materials: Array = []

func _process(_delta):
	if registered_materials.empty():
		return
	
	## Disabled: Too noisy
	# if is_occlusion_active and Engine.get_frames_drawn() % 60 == 0:
	#	print("[WallOcclusionManager] Active. Materials: ", registered_materials.size(), " Player nodes: ", get_tree().get_nodes_in_group("player").size())

		
	if not is_instance_valid(player_node):
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]
			
	# Always update to current active camera
	camera_node = get_viewport().get_camera()
		
	if is_instance_valid(player_node) and is_instance_valid(camera_node):
		var p_pos = player_node.global_transform.origin + Vector3(0, 1.2, 0) # Head/torso focus
		var c_pos = camera_node.global_transform.origin
		var active_val = 1.0 if is_occlusion_active else 0.0
		
		# Clean up dead materials while iterating
		var living_materials = []
		for mat in registered_materials:
			if is_instance_valid(mat):
				mat.set_shader_param("player_pos", p_pos)
				mat.set_shader_param("camera_pos", c_pos)
				mat.set_shader_param("is_active", active_val)
				mat.set_shader_param("hole_radius", hole_radius)
				living_materials.append(mat)
		registered_materials = living_materials

func register_material(mat: ShaderMaterial):
	if mat and not registered_materials.has(mat):
		registered_materials.append(mat)
		print("[WallOcclusionManager] Registered material: ", mat.resource_path if mat.resource_path else "Unsaved shader material")
		# Immediate apply
		mat.set_shader_param("hole_radius", hole_radius)


func set_occlusion_params(active: bool, radius: float):
	is_occlusion_active = active
	hole_radius = radius
