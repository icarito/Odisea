extends Spatial

# core_v2/tests/DuctPieceTestScene.gd
# Test scene for manual verification of FD-052 duct pieces.

func _ready():
	# Simple floor for the player
	var floor_node = StaticBody.new()
	var mesh_instance = MeshInstance.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(100, 100)
	mesh_instance.mesh = plane_mesh
	var mat = SpatialMaterial.new()
	mat.albedo_color = Color(0.2, 0.2, 0.2)
	mesh_instance.material_override = mat
	floor_node.add_child(mesh_instance)
	var shape = CollisionShape.new()
	var box = BoxShape.new()
	box.extents = Vector3(50, 0.1, 50)
	shape.shape = box
	floor_node.add_child(shape)
	add_child(floor_node)
	floor_node.translation.y = -5.0

	var streamer = DuctMazeStreamer.new()
	# We don't add streamer as child yet to avoid it generating its own maze
	# unless we want to use its methods.
	
	var piece_configs = [
		["RADIAL", streamer.make_duct_radial(0)],
		["ARC", streamer.make_duct_arc(0, 0)],
		["INCLINE", streamer.make_incline([0.0, 0.0, 2.0, 0.0])], # North to South incline
		["ENDCAP", streamer.make_endcap()],
		["JUNCTION_C", streamer.make_junction("C", [true, true, false, false])],
		["JUNCTION_T", streamer.make_junction("T", [true, true, true, false])],
		["JUNCTION_X", streamer.make_junction("X", [true, true, true, true])],
		["CAPSULE", streamer.make_capsule([true, true, true, true], 0)]
	]
	
	for i in range(piece_configs.size()):
		var p_name = piece_configs[i][0]
		var node = piece_configs[i][1]
		node.translation.x = i * 10.0
		add_child(node)
		
		# Add Label
		var label_scene = load("res://core_v2/props/signage/SignagePanel.tscn")
		if label_scene:
			var label = label_scene.instance()
			label.translation = node.translation + Vector3(0, 6, 0)
			label.set("text", p_name + " OK")
			label.set("color_preset", "terminal")
			add_child(label)

	# Add Player
	var player_scene = load("res://core_v2/actors/Pilot_v2.tscn")
	if player_scene:
		var player = player_scene.instance()
		player.translation = Vector3(0, 2, 5)
		add_child(player)
		# Ensure camera is current
		player.call_deferred("force_camera_current")

	# Add some lights
	var sun = DirectionalLight.new()
	sun.rotation_degrees = Vector3(-45, 45, 0)
	sun.light_energy = 0.5
	add_child(sun)
	
	print("DuctPieceTestScene ready. 8 pieces instantiated.")
