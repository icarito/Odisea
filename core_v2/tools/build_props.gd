tool
extends SceneTree

func _init():
	print("Building LaserTripwire...")
	var laser = make_laser_tripwire()
	save_scene(laser, "res://core_v2/props/LaserTripwire.tscn")

	print("Building IndustrialFan...")
	var fan = make_industrial_fan()
	save_scene(fan, "res://core_v2/props/IndustrialFan.tscn")

	print("Done.")
	quit()

func save_scene(node: Node, path: String):
	var packed = PackedScene.new()
	var res = packed.pack(node)
	if res == OK:
		var save_res = ResourceSaver.save(path, packed)
		if save_res == OK:
			print("Saved ", path)
		else:
			print("Error saving ", path, ": ", save_res)
	else:
		print("Error packing ", node.name, ": ", res)

func make_laser_tripwire() -> Spatial:
	var root = Spatial.new()
	root.name = "LaserTripwire"
	root.set_script(load("res://core_v2/props/LaserTripwire.gd"))

	# Emitter 1
	var emitter1 = MeshInstance.new()
	emitter1.name = "Emitter1"
	emitter1.mesh = CubeMesh.new()
	emitter1.mesh.size = Vector3(0.2, 0.5, 0.2)
	emitter1.translation = Vector3(-2, 0, 0)
	root.add_child(emitter1)
	emitter1.owner = root

	# Emitter 2
	var emitter2 = MeshInstance.new()
	emitter2.name = "Emitter2"
	emitter2.mesh = CubeMesh.new()
	emitter2.mesh.size = Vector3(0.2, 0.5, 0.2)
	emitter2.translation = Vector3(2, 0, 0)
	root.add_child(emitter2)
	emitter2.owner = root

	# Beam Mesh
	var beam = MeshInstance.new()
	beam.name = "BeamMesh"
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = 4.0
	beam.mesh = cyl
	# Cylinder aligns Y by default. Rotate Z 90 deg -> X axis.
	beam.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(beam)
	beam.owner = root

	# RayCast
	var ray = RayCast.new()
	ray.name = "RayCast"
	ray.cast_to = Vector3(4, 0, 0) # Local X, length 4
	# Start at -2, aim +4 -> end at +2
	ray.translation = Vector3(-2, 0, 0)
	ray.enabled = true
	ray.collision_mask = 1 # Default layer
	root.add_child(ray)
	ray.owner = root

	return root

func make_industrial_fan() -> Spatial:
	var root = Spatial.new()
	root.name = "IndustrialFan"
	root.set_script(load("res://core_v2/props/IndustrialFan.gd"))

	# Housing
	var housing = MeshInstance.new()
	housing.name = "Housing"
	var cyl = CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 0.5
	housing.mesh = cyl
	# Cylinder is Y-up. Rotate X 90 deg -> Z axis (face forward/back)
	housing.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(housing)
	housing.owner = root

	# Blade (Child of Housing for simple hierarchy, but IndustrialFan.gd expects "Housing/Blade")
	# If I make it child of Housing, I need to be careful with owner.

	var blade = MeshInstance.new()
	blade.name = "Blade"
	var prism = PrismMesh.new()
	prism.size = Vector3(1.8, 0.1, 0.4) # Wide blade
	blade.mesh = prism
	housing.add_child(blade)
	# IMPORTANT: blade.owner must be root for it to be saved in the PackedScene!
	blade.owner = root

	# Wind Area
	var area = Area.new()
	area.name = "WindArea"

	var col = CollisionShape.new()
	col.name = "CollisionShape"
	col.shape = BoxShape.new()
	col.shape.extents = Vector3(1, 1, 2.5) # Total length 5
	col.translation = Vector3(0, 0, -2.5) # Center offset
	area.add_child(col)

	root.add_child(area)
	area.owner = root
	col.owner = root

	return root
