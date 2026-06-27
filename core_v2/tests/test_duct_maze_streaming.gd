extends GdUnitTestSuite

const DuctMazeStreamerScript = preload("res://core_v2/systems/DuctMazeSpawner.gd")

func test_smoke_generation() -> void:
	var root := Spatial.new()
	add_child(root)

	var spawner = DuctMazeStreamerScript.new()
	spawner.name = "DuctMazeStreamer"
	spawner.inner_radius = 2.0
	spawner.ring_step = 4.0
	spawner.sectors = 12
	spawner.rings = 3
	spawner.height_steps = 6
	spawner.room_count = 4
	spawner.extra_cycles = 2
	spawner.seed_value = 52
	root.add_child(spawner)
	
	spawner.generate()
	
	assert_int(spawner.get_child_count()).is_greater(0)
	
	var radial_count = 0
	var arc_count = 0
	var capsule_count = 0
	var junction_count = 0
	
	for child in spawner.get_children():
		if "DuctRadial" in child.name:
			radial_count += 1
		elif "DuctArc" in child.name:
			arc_count += 1
		elif "CapsuleRoom" in child.name:
			capsule_count += 1
		elif "Junction" in child.name:
			junction_count += 1

	assert_int(radial_count + arc_count + capsule_count + junction_count).is_greater(0)
	
	root.queue_free()

func test_grid_to_world_polar_projection() -> void:
	var spawner = DuctMazeStreamerScript.new()
	spawner.inner_radius = 2.0
	spawner.ring_step = 4.0
	spawner.sectors = 12
	
	# Test at gx=0, gy=0, height=0
	var t0 = spawner._grid_to_world(0, 0, 0.0)
	# radius = 2.0 + 0.5 * 4.0 = 4.0
	# angle = 0 -> world_x = 4.0 * cos(0) = 4.0, world_z = 4.0 * sin(0) = 0.0
	assert_vector3(t0.origin).is_equal_approx(Vector3(4.0, 0.0, 0.0), Vector3(0.001, 0.001, 0.001))
	
	# tangent = (-sin(0), 0, cos(0)) = (0, 0, 1) -> Basis.x
	assert_vector3(t0.basis.x).is_equal_approx(Vector3(0, 0, 1), Vector3(0.001, 0.001, 0.001))
	# radial = (cos(0), 0, sin(0)) = (1, 0, 0) -> Basis.z
	assert_vector3(t0.basis.z).is_equal_approx(Vector3(1, 0, 0), Vector3(0.001, 0.001, 0.001))
	
	# Test at gx=3 (90 degrees), gy=0, height=0
	var t1 = spawner._grid_to_world(3, 0, 0.0)
	# angle = 90 -> world_x = 4.0 * cos(90) = 0.0, world_z = 4.0 * sin(90) = 4.0
	assert_vector3(t1.origin).is_equal_approx(Vector3(0.0, 0.0, 4.0), Vector3(0.001, 0.001, 0.001))
	
	spawner.free()
