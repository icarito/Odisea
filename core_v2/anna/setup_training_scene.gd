tool
extends SceneTree

func _init():
	print("Generating Anna Training Arena (Programmatic Pilot)...")
	var root = Spatial.new()
	root.name = "AnnaTrainingArena"

	# 1. Floor
	var floor_body = StaticBody.new()
	floor_body.name = "Floor"
	root.add_child(floor_body)
	floor_body.owner = root

	var floor_mesh = MeshInstance.new()
	floor_mesh.name = "FloorMesh"
	var plane = PlaneMesh.new()
	plane.size = Vector2(50, 50)
	floor_mesh.mesh = plane
	floor_body.add_child(floor_mesh)
	floor_mesh.owner = root

	var floor_shape = CollisionShape.new()
	floor_shape.name = "FloorShape"
	var box = BoxShape.new()
	box.extents = Vector3(25, 1, 25)
	floor_shape.shape = box
	floor_shape.transform.origin = Vector3(0, -1, 0)
	floor_body.add_child(floor_shape)
	floor_shape.owner = root

	# 2. Walls
	var wall_positions = [
		[Vector3(0, 2.5, -25), Vector3(25, 2.5, 1)], # Front
		[Vector3(0, 2.5, 25), Vector3(25, 2.5, 1)],  # Back
		[Vector3(-25, 2.5, 0), Vector3(1, 2.5, 25)], # Left
		[Vector3(25, 2.5, 0), Vector3(1, 2.5, 25)]   # Right
	]

	for i in range(wall_positions.size()):
		var pos = wall_positions[i][0]
		var ext = wall_positions[i][1]

		var wall = StaticBody.new()
		wall.name = "Wall_%d" % i
		wall.transform.origin = pos
		root.add_child(wall)
		wall.owner = root

		var w_mesh = MeshInstance.new()
		var w_cube = CubeMesh.new()
		w_cube.size = ext * 2.0
		w_mesh.mesh = w_cube
		wall.add_child(w_mesh)
		w_mesh.owner = root

		var w_shape = CollisionShape.new()
		var w_box = BoxShape.new()
		w_box.extents = ext
		w_shape.shape = w_box
		wall.add_child(w_shape)
		w_shape.owner = root

	# 3. Target
	var target = Area.new()
	target.name = "Target"
	target.add_to_group("anna_target", true)
	target.transform.origin = Vector3(0, 1, -10)
	root.add_child(target)
	target.owner = root

	var t_mesh = MeshInstance.new()
	var t_sphere = SphereMesh.new()
	t_sphere.radius = 1.0
	t_sphere.height = 2.0
	t_mesh.mesh = t_sphere
	target.add_child(t_mesh)
	t_mesh.owner = root

	var t_shape = CollisionShape.new()
	var t_col_sphere = SphereShape.new()
	t_col_sphere.radius = 1.0
	t_shape.shape = t_col_sphere
	target.add_child(t_shape)
	t_shape.owner = root

	# 4. Programmatic Pilot
	var pilot = KinematicBody.new()
	pilot.name = "Pilot"
	pilot.collision_layer = 2
	pilot.collision_mask = 255
	pilot.set_script(load("res://core_v2/player/PlayerControllerV2.gd"))
	pilot.transform.origin = Vector3(0, 2, 0)
	root.add_child(pilot)
	pilot.owner = root

	# Pilot Logic
	var logic = Node.new()
	logic.name = "Logic"
	pilot.add_child(logic)
	logic.owner = root

	var jump = Node.new()
	jump.name = "Jump"
	jump.set_script(load("res://core_v2/player/PlayerJumpV2.gd"))
	logic.add_child(jump)
	jump.owner = root

	var movement = Node.new()
	movement.name = "Movement"
	movement.set_script(load("res://core_v2/player/PlayerMovementV2.gd"))
	logic.add_child(movement)
	movement.owner = root

	# Pilot Visual
	var visual = Spatial.new()
	visual.name = "Visual"
	pilot.add_child(visual)
	visual.owner = root

	var pivot = Spatial.new()
	pivot.name = "Pivot"
	pivot.set_script(load("res://core_v2/actors/PilotAnimatorV2.gd"))
	visual.add_child(pivot)
	pivot.owner = root

	# Pilot Mesh (Capsule for visual debugging)
	var p_mesh = MeshInstance.new()
	var p_cap = CapsuleMesh.new()
	p_cap.radius = 0.5
	p_cap.mid_height = 1.0
	p_mesh.mesh = p_cap
	p_mesh.transform.origin = Vector3(0, 1, 0)
	p_mesh.rotation_degrees.x = 90
	pivot.add_child(p_mesh)
	p_mesh.owner = root

	# CameraRig
	var rig = Spatial.new()
	rig.name = "CameraRig"
	rig.transform.origin = Vector3(0, 1.5, 0)
	pilot.add_child(rig)
	rig.owner = root

	var cam = Camera.new()
	cam.name = "Camera"
	cam.current = true
	# Look down slightly
	cam.rotation_degrees.x = -15
	rig.add_child(cam)
	cam.owner = root

	# Collision Shape
	var shape = CollisionShape.new()
	shape.name = "CollisionShape"
	var cap = CapsuleShape.new()
	cap.radius = 0.5
	cap.height = 1.0
	shape.shape = cap
	shape.transform.origin = Vector3(0, 0.96, 0) # Matching Pilot_v2.tscn
	shape.rotation_degrees.x = -90 # Vertical capsule needs 90 deg rotation if using default CapsuleShape? No, Godot CapsuleShape is Z-up? No, usually Y-up.
	# Wait, Pilot_v2.tscn has transform (-1, 0, 0, 0, 0, -1, 0, -1, 0, ...)
	# Standard CapsuleShape is height along Z in Godot 3?
	# Memory says: "CircuitCable hurtbox is... CapsuleShape is oriented along the Z-axis"
	# So yes, CapsuleShape is Z-aligned. KinematicBody usually wants Y-aligned.
	# So we rotate -90 on X to make Z point up (Y).
	shape.rotation_degrees.x = -90
	pilot.add_child(shape)
	shape.owner = root

	# 5. Light
	var light = DirectionalLight.new()
	light.name = "Sun"
	light.transform.origin = Vector3(0, 10, 0)
	light.rotation_degrees.x = -45
	root.add_child(light)
	light.owner = root

	# Save
	var packed_scene = PackedScene.new()
	var result = packed_scene.pack(root)
	if result == OK:
		var err = ResourceSaver.save("res://core_v2/anna/AnnaTrainingArena.tscn", packed_scene)
		if err == OK:
			print("Scene saved successfully to res://core_v2/anna/AnnaTrainingArena.tscn")
		else:
			print("Error saving scene: ", err)
			quit(1)
	else:
		print("Error packing scene: ", result)
		quit(1)

	quit(0)
