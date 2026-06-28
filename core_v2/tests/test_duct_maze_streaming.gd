extends GdUnitTestSuite

const DuctMazeStreamerScript = preload("res://core_v2/systems/DuctMazeStreamer.gd")

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
	spawner.rings = 3
	spawner.wall_radius = 28.0
	
	# Test at gx=0, gy=0, height=0
	var t0 = spawner._grid_to_world(0, 0, 0.0, "DuctRadial")
	# radius = wall_radius, y = gy * ring_step within the current chunk
	assert_vector3(t0.origin).is_equal_approx(Vector3(28.0, 0.0, 0.0), Vector3(0.001, 0.001, 0.001))
	
	# tangent = (-sin(0), 0, cos(0)) = (0, 0, 1) -> Basis.x
	assert_vector3(t0.basis.x).is_equal_approx(Vector3(0, 0, 1), Vector3(0.001, 0.001, 0.001))
	# straight duct local Z follows the cylinder axis
	assert_vector3(t0.basis.z).is_equal_approx(Vector3.UP, Vector3(0.001, 0.001, 0.001))
	# straight duct local Y points radially out from the cylinder
	assert_vector3(t0.basis.y).is_equal_approx(Vector3(1, 0, 0), Vector3(0.001, 0.001, 0.001))
	
	# Test at gx=3 (90 degrees), gy=0, height=0
	var t1 = spawner._grid_to_world(3, 0, 0.0, "DuctRadial")
	# angle = 90 -> world_x = 0.0, world_z = wall_radius
	assert_vector3(t1.origin).is_equal_approx(Vector3(0.0, 0.0, 28.0), Vector3(0.001, 0.001, 0.001))

	var t2 = spawner._grid_to_world(0, 2, 0.0, "DuctRadial")
	assert_vector3(t2.origin).is_equal_approx(Vector3(28.0, 8.0, 0.0), Vector3(0.001, 0.001, 0.001))

	var arc = spawner._grid_to_world(0, 0, 0.0, "DuctArc")
	assert_vector3(arc.basis.x).is_equal_approx(Vector3(1, 0, 0), Vector3(0.001, 0.001, 0.001))
	assert_vector3(arc.basis.z).is_equal_approx(Vector3(0, 0, 1), Vector3(0.001, 0.001, 0.001))
	
	spawner.free()

func test_arc_collision_has_no_solid_round_blockers() -> void:
	var spawner = DuctMazeStreamerScript.new()
	spawner.wall_radius = 28.0
	spawner.sectors = 12
	var arc = spawner.make_duct_arc(0, 0)
	var counts := _count_collision_shapes(arc)

	assert_int(counts.get("ConcavePolygonShape", 0)).is_equal(0)
	assert_int(counts.get("CylinderShape", 0)).is_equal(0)
	assert_int(counts.get("SphereShape", 0)).is_equal(0)
	assert_int(counts.get("BoxShape", 0)).is_equal(32)

	arc.free()
	spawner.free()

func test_capsule_room_ports_are_not_sealed_by_center_trimesh() -> void:
	var spawner = DuctMazeStreamerScript.new()
	var room = spawner.make_capsule([true, true, false, false], 0)
	var counts := _count_collision_shapes(room)

	assert_int(counts.get("ConcavePolygonShape", 0)).is_equal(0)
	assert_int(counts.get("BoxShape", 0)).is_greater(0)

	room.free()
	spawner.free()

func test_junctions_have_visible_hub_without_solid_center_blocker() -> void:
	var spawner = DuctMazeStreamerScript.new()
	spawner.ring_step = 8.0
	spawner.duct_radius = 3.75
	spawner.junction_hub_reach = 0.8
	var junction = spawner.make_junction("T", [true, true, true, false])
	var counts := _count_collision_shapes(junction)

	assert_object(junction.get_node_or_null("JunctionHub")).is_not_null()
	assert_int(_count_direct_arm_children(junction)).is_equal(3)
	assert_int(counts.get("ConcavePolygonShape", 0)).is_equal(0)
	assert_int(counts.get("SphereShape", 0)).is_equal(0)
	assert_int(counts.get("CylinderShape", 0)).is_equal(0)
	assert_int(counts.get("BoxShape", 0)).is_greater(0)

	junction.free()
	spawner.free()

func test_generated_airlock_has_interaction_proxy_and_no_shell_blocker() -> void:
	var spawner = DuctMazeStreamerScript.new()
	add_child(spawner)
	var cell = {
		"variant": {
			"id": "W",
			"connections": [false, true, false, false]
		}
	}

	spawner._add_room_airlock(cell, 0, 0, 1)
	var airlock = spawner.get_node_or_null("RoomAirlock")
	assert_object(airlock).is_not_null()

	var shell = airlock.get_node_or_null("CylindricalShell")
	assert_int(shell.collision_layer).is_equal(0)
	var shell_shape = shell.get_node_or_null("CollisionShape")
	assert_bool(shell_shape.disabled).is_true()

	var outer_proxy = airlock.get_node_or_null("OuterDoor/InteractionProxy")
	assert_object(outer_proxy).is_not_null()
	assert_int(outer_proxy.collision_layer).is_equal(4)
	assert_bool(outer_proxy.has_meta("airlock_controller_owned")).is_true()

	spawner.queue_free()

func test_streaming_mode_creates_axis_chunks() -> void:
	var spawner = DuctMazeStreamerScript.new()
	spawner.streaming_enabled = true
	spawner.stream_chunk_rings = 3
	spawner.stream_active_chunks_each_side = 1
	spawner.sectors = 8
	spawner.rings = 3
	spawner.seed_value = 42
	add_child(spawner)

	spawner.generate()

	assert_object(spawner.get_node_or_null("DuctChunk_-1")).is_not_null()
	assert_object(spawner.get_node_or_null("DuctChunk_0")).is_not_null()
	assert_object(spawner.get_node_or_null("DuctChunk_1")).is_not_null()
	assert_float(spawner.get_node("DuctChunk_1").translation.y).is_equal_approx(12.0, 0.001)

	spawner.queue_free()

func test_collapse_triggers_are_disabled_by_default() -> void:
	var spawner = DuctMazeStreamerScript.new()
	spawner.sectors = 8
	spawner.rings = 3
	spawner.seed_value = 42
	add_child(spawner)

	spawner.generate()

	assert_int(_count_nodes_named(spawner, "CollapseTrigger")).is_equal(0)
	assert_int(_count_nodes_named(spawner, "CollapseBlocker")).is_equal(0)

	spawner.queue_free()

func _count_collision_shapes(node: Node) -> Dictionary:
	var counts := {}
	if node is CollisionShape and node.shape != null:
		var shape_class: String = node.shape.get_class()
		counts[shape_class] = int(counts.get(shape_class, 0)) + 1
	for child in node.get_children():
		var child_counts := _count_collision_shapes(child)
		for key in child_counts:
			counts[key] = int(counts.get(key, 0)) + int(child_counts[key])
	return counts

func _count_nodes_named(node: Node, target_name: String) -> int:
	var count := 0
	if node.name == target_name:
		count += 1
	for child in node.get_children():
		count += _count_nodes_named(child, target_name)
	return count

func _count_direct_arm_children(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is Spatial and child.name != "JunctionHub":
			count += 1
	return count
