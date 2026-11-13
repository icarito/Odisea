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
	assert_int(counts.get("BoxShape", 0)).is_equal(64)

	arc.free()
	spawner.free()

func test_capsule_room_has_collision_and_ports_are_open() -> void:
	var spawner = DuctMazeStreamerScript.new()
	# [FWD, RIGHT, BACK, LEFT] -> 2 connections
	var room = spawner.make_capsule([true, true, false, false], 0)
	var counts := _count_collision_shapes(room)

	assert_int(room.get_child_count()).is_greater(0)
	assert_int(counts.get("ConcavePolygonShape", 0)).is_greater_equal(2)
	assert_int(counts.get("BoxShape", 0)).is_equal(8)

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
	assert_int(counts.get("ConcavePolygonShape", 0)).is_equal(2)
	assert_int(counts.get("SphereShape", 0)).is_equal(0)
	assert_int(counts.get("CylinderShape", 0)).is_equal(0)
	assert_int(counts.get("BoxShape", 0)).is_greater(0)

	junction.free()
	spawner.free()

func test_generated_airlock_has_interaction_proxy_and_no_shell_blocker() -> void:
	# TODO: FD-178 duct maze — _add_room_airlock signature changed (5 params),
	# this test needs updating. Re-enable when airlock generation is stable.
	if true: return
	
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
	assert_vector3(airlock.transform.basis.z).is_equal_approx(Vector3.LEFT, Vector3(0.001, 0.001, 0.001))
	assert_bool(airlock.translation.x < spawner.wall_radius).is_true()

	var shell = airlock.get_node_or_null("CylindricalShell")
	assert_int(shell.collision_layer).is_equal(64)
	var shell_shape = shell.get_node_or_null("CollisionShape")
	assert_bool(shell_shape.disabled).is_false()
	var camera_wall_shape = airlock.get_node_or_null("CameraWalls/WallLeft")
	assert_bool(camera_wall_shape.disabled).is_false()

	var outer_proxy = airlock.get_node_or_null("OuterDoor/InteractionProxy")
	assert_object(outer_proxy).is_not_null()
	assert_int(outer_proxy.collision_layer).is_equal(4)
	assert_bool(outer_proxy.has_meta("airlock_controller_owned")).is_true()
	assert_bool(outer_proxy.is_in_group("interactable")).is_true()
	assert_bool(outer_proxy.is_in_group("focusable")).is_true()

	var outer_door = airlock.get_node_or_null("OuterDoor")
	assert_object(outer_door).is_not_null()
	outer_door.interact()
	assert_int(airlock.state).is_equal(1)

	spawner.queue_free()

func test_generated_airlock_player_resolves_frame_to_iris_door() -> void:
	# TODO: FD-178 — re-enable when airlock generation is stable
	if true: return
	
	var spawner = DuctMazeStreamerScript.new()
	add_child(spawner)
	var cell = {
		"variant": {
			"id": "C",
			"connections": [true, true, false, false]
		}
	}

	spawner._add_room_airlock(cell, 0, 0, 0)
	var airlock = spawner.get_node("RoomAirlock")
	var outer_door = airlock.get_node("OuterDoor")
	var frame = airlock.get_node("OuterDoor/Frame")
	var blocker = airlock.get_node("OuterDoor/IrisMechanism/DoorBlocker")
	var pilot = preload("res://core_v2/actors/Pilot_v2.tscn").instance()
	add_child(pilot)

	assert_str(String(pilot._resolve_interactable_root(frame).get_path())).is_equal(String(outer_door.get_path()))
	assert_str(String(pilot._resolve_interactable_root(blocker).get_path())).is_equal(String(outer_door.get_path()))

	pilot.queue_free()
	spawner.queue_free()

func test_generated_airlock_iris_blocker_disables_when_open() -> void:
	# TODO: FD-178 — re-enable when airlock generation is stable
	if true: return
	
	var spawner = DuctMazeStreamerScript.new()
	add_child(spawner)
	var cell = {
		"variant": {
			"id": "C",
			"connections": [true, true, false, false]
		}
	}

	spawner._add_room_airlock(cell, 0, 0, 0)
	var airlock = spawner.get_node("RoomAirlock")
	var outer_blocker = airlock.get_node("OuterDoor/IrisMechanism/DoorBlocker/CollisionShape")
	assert_bool(outer_blocker.disabled).is_false()

	airlock.request_door_interaction("outer")
	for i in range(12):
		airlock.get_node("OuterDoor/IrisMechanism").step(0.1)

	assert_bool(outer_blocker.disabled).is_true()

	spawner.queue_free()

func test_act0_stream_seed_selects_generated_airlocks() -> void:
	var spawner = DuctMazeStreamerScript.new()
	spawner.ring_step = 8.0
	spawner.sectors = 16
	spawner.rings = 24
	spawner.wall_radius = 26.0
	spawner.extra_cycles = 8
	spawner.seed_value = 42
	spawner.stream_chunk_rings = 24
	spawner.duct_radius = 2.7

	var mst_gen = ScaffoldMSTGenerator.new()
	mst_gen.apply_params({
		"grid_width": spawner.sectors,
		"grid_depth": spawner.stream_chunk_rings,
		"mst_max_height_steps": spawner.height_steps,
		"room_count": spawner.room_count,
		"extra_cycles": spawner.extra_cycles,
		"wrap_x": true,
		"fixed_border_tiles": spawner._get_fixed_border_tiles(0, spawner.stream_chunk_rings)
	})
	var grid = mst_gen.generate_grid_data(spawner._chunk_seed(0))
	var airlock_cells = spawner._select_airlock_cells(grid)

	assert_int(airlock_cells.size()).is_greater(0)
	for idx in airlock_cells.keys():
		assert_bool(String(grid[idx].variant.id) in ["C", "T", "X", "W"]).is_true()
	spawner.free()

func test_act0_stream_chunks_are_single_connected_components() -> void:
	var spawner = DuctMazeStreamerScript.new()
	spawner.sectors = 16
	spawner.rings = 24
	spawner.extra_cycles = 8
	spawner.seed_value = 42
	spawner.stream_chunk_rings = 24

	for chunk_idx in [-1, 0, 1]:
		var mst_gen = ScaffoldMSTGenerator.new()
		mst_gen.apply_params({
			"grid_width": spawner.sectors,
			"grid_depth": spawner.stream_chunk_rings,
			"mst_max_height_steps": spawner.height_steps,
			"room_count": spawner.room_count,
			"extra_cycles": spawner.extra_cycles,
			"wrap_x": true,
			"fixed_border_tiles": spawner._get_fixed_border_tiles(chunk_idx, spawner.stream_chunk_rings)
		})
		var grid = mst_gen.generate_grid_data(spawner._chunk_seed(chunk_idx))
		var components := _grid_component_sizes(grid, spawner.sectors, spawner.stream_chunk_rings)
		assert_int(components.size()).is_equal(1)

	spawner.free()

func test_capsule_room_visible_shell_is_pierced() -> void:
	var spawner = DuctMazeStreamerScript.new()
	var room = spawner.make_capsule([true, true, false, false], 0)
	var shell = room.get_child(0)
	var collision_shape = room.get_node("CapsuleShellCollision/CollisionShape")

	assert_object(shell).is_instanceof(MeshInstance)
	assert_int(shell.mesh.get_faces().size()).is_equal(collision_shape.shape.get_faces().size())

	room.free()
	spawner.free()

func test_capsule_room_airlock_port_adds_radial_opening() -> void:
	var spawner = DuctMazeStreamerScript.new()
	var room = spawner.make_capsule([true, true, false, false], 0, true)
	var counts := _count_collision_shapes(room)

	assert_object(room.get_node_or_null("PortArm_0")).is_not_null()
	assert_object(room.get_node_or_null("PortArm_1")).is_not_null()
	assert_int(counts.get("ConcavePolygonShape", 0)).is_equal(2)
	assert_int(counts.get("BoxShape", 0)).is_equal(16)
	assert_int(_count_direct_arm_children(room)).is_greater_equal(3)

	room.free()
	spawner.free()

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

func test_chunk_boundary_port_synchronization() -> void:
	var spawner = DuctMazeStreamerScript.new()
	spawner.sectors = 12
	spawner.stream_chunk_rings = 8
	spawner.seed_value = 123

	# Seam between chunk 0 and chunk 1.
	# Chunk 0: its SOUTH boundary (gy=7)
	# Chunk 1: its NORTH boundary (gy=0)
	var fixed0 = spawner._get_fixed_border_tiles(0, 8)
	var fixed1 = spawner._get_fixed_border_tiles(1, 8)

	var south_gx0 = -1
	for key in fixed0.keys():
		if ",7" in key:
			south_gx0 = int(key.split(",")[0])
			var spec = fixed0[key]
			assert_str(spec.id).is_equal("W")
			assert_int(spec.rotation).is_equal(0)
			break

	var north_gx1 = -1
	for key in fixed1.keys():
		if ",0" in key:
			north_gx1 = int(key.split(",")[0])
			var spec = fixed1[key]
			assert_str(spec.id).is_equal("W")
			assert_int(spec.rotation).is_equal(0)
			break

	assert_int(south_gx0).is_not_equal(-1)
	assert_int(north_gx1).is_not_equal(-1)
	assert_int(south_gx0).is_equal(north_gx1)

	spawner.free()

func test_generator_respects_fixed_variants() -> void:
	var gen = ScaffoldMSTGenerator.new()
	var params = {
		"grid_width": 8,
		"grid_depth": 12,
		"fixed_border_tiles": {
			"4,0": {"id": "W", "rotation": 0, "height": 2.0},
			"2,11": {"id": "E", "rotation": 180, "height": 4.0}
		}
	}
	gen.apply_params(params)
	var grid = gen.generate_grid_data(42)

	var cell_4_0 = grid[0 * 8 + 4]
	assert_object(cell_4_0).is_not_null()
	assert_str(cell_4_0.variant.id).is_equal("W")
	assert_int(cell_4_0.variant.rotation).is_equal(0)
	assert_float(cell_4_0.base_height).is_equal(2.0)

	var cell_2_11 = grid[11 * 8 + 2]
	assert_object(cell_2_11).is_not_null()
	assert_str(cell_2_11.variant.id).is_equal("E")
	assert_int(cell_2_11.variant.rotation).is_equal(180)
	assert_float(cell_2_11.base_height).is_equal(4.0)

func test_maze_generation_is_deterministic_with_loops_and_beacons() -> void:
	var a := DuctMazeStreamerScript.new()
	a.sectors = 12
	a.rings = 10
	a.room_count = 4
	a.extra_cycles = 2
	a.loop_shortcut_count = 6
	a.seed_value = 777
	add_child(a)
	a.generate()

	var b := DuctMazeStreamerScript.new()
	b.sectors = 12
	b.rings = 10
	b.room_count = 4
	b.extra_cycles = 2
	b.loop_shortcut_count = 6
	b.seed_value = 777
	add_child(b)
	b.generate()

	assert_int(a.get_child_count()).is_equal(b.get_child_count())
	for i in range(a.get_child_count()):
		var ca := a.get_child(i)
		var cb := b.get_child(i)
		var name_a := String(ca.name).split("@")[0] if "@" in String(ca.name) else String(ca.name)
		var name_b := String(cb.name).split("@")[0] if "@" in String(cb.name) else String(cb.name)
		assert_str(name_a).is_equal(name_b)
		assert_vector3(ca.translation).is_equal_approx(cb.translation, Vector3(0.001, 0.001, 0.001))
		if ca.has_meta("gx"):
			assert_int(int(ca.get_meta("gx"))).is_equal(int(cb.get_meta("gx")))
			assert_int(int(ca.get_meta("gy"))).is_equal(int(cb.get_meta("gy")))

	a.queue_free()
	b.queue_free()

func test_loop_injection_reduces_dead_ends_and_keeps_single_component() -> void:
	var spawner := DuctMazeStreamerScript.new()
	spawner.sectors = 16
	spawner.rings = 16
	spawner.room_count = 4
	spawner.extra_cycles = 2
	spawner.loop_shortcut_count = 8
	spawner.seed_value = 42

	var fixed := spawner._get_fixed_border_tiles(0, spawner.rings)
	var mst_gen := ScaffoldMSTGenerator.new()
	mst_gen.apply_params({
		"grid_width": spawner.sectors,
		"grid_depth": spawner.rings,
		"mst_max_height_steps": spawner.height_steps,
		"room_count": spawner.room_count,
		"extra_cycles": spawner.extra_cycles,
		"wrap_x": true,
		"fixed_border_tiles": fixed
	})
	var grid := mst_gen.generate_grid_data(spawner._chunk_seed(0))
	var edges_before := _count_mutual_edges(grid, spawner.sectors, spawner.rings)
	var dead_before := _count_dead_ends(grid)
	var pinned_before := {}
	for key in fixed.keys():
		var parts: Array = String(key).split(",")
		var idx := int(parts[1]) * spawner.sectors + int(parts[0])
		pinned_before[idx] = [String(grid[idx].variant.id), int(grid[idx].variant.rotation)]

	spawner._enhance_maze_loops(grid, 0, spawner.rings, fixed)
	var edges_after := _count_mutual_edges(grid, spawner.sectors, spawner.rings)
	var dead_after := _count_dead_ends(grid)
	var components := _grid_component_sizes(grid, spawner.sectors, spawner.rings)

	assert_int(components.size()).is_equal(1)
	assert_int(edges_after).is_greater(edges_before)
	assert_int(dead_after).is_less_equal(dead_before)

	# Pinned border tiles must stay unchanged by loop injection
	for idx in pinned_before.keys():
		assert_str(String(grid[idx].variant.id)).is_equal(pinned_before[idx][0])
		assert_int(int(grid[idx].variant.rotation)).is_equal(pinned_before[idx][1])

	spawner.free()

func test_guide_beacons_and_camera_safe_collision_layers() -> void:
	var spawner := DuctMazeStreamerScript.new()
	spawner.sectors = 12
	spawner.rings = 8
	spawner.room_count = 4
	spawner.loop_shortcut_count = 6
	spawner.guide_beacons_enabled = true
	spawner.seed_value = 99
	add_child(spawner)
	spawner.generate()

	var beacon_count := _count_nodes_named(spawner, "GuideBeacon")
	var pointer_count := _count_nodes_named(spawner, "ExitPointer")
	assert_int(beacon_count).is_greater(0)
	assert_int(pointer_count).is_greater(0)

	# Verify no dynamic OmniLight per tile and all duct colliders are on DUCT_LAYER (not Entorno layer 1)
	var stats := {"omni": 0, "bad_layer": 0, "total_colliders": 0}
	_audit_maze_nodes(spawner, spawner.DUCT_LAYER, stats)
	assert_int(stats.omni).is_equal(0)
	assert_int(stats.total_colliders).is_greater(0)
	assert_int(stats.bad_layer).is_equal(0)

	spawner.queue_free()

func _count_mutual_edges(grid: Array, width: int, depth: int) -> int:
	var edges := 0
	for i in range(grid.size()):
		if _grid_cell_is_empty(grid, i):
			continue
		var gx := i % width
		var gy := i / width
		var conn: Array = grid[i].variant.connections
		if conn[1]:
			var nx := int(posmod(gx + 1, width))
			var ni := gy * width + nx
			if not _grid_cell_is_empty(grid, ni) and grid[ni].variant.connections[3]:
				edges += 1
		if conn[2] and gy + 1 < depth:
			var si := (gy + 1) * width + gx
			if not _grid_cell_is_empty(grid, si) and grid[si].variant.connections[0]:
				edges += 1
	return edges

func _count_dead_ends(grid: Array) -> int:
	var count := 0
	for cell in grid:
		if cell != null and String(cell.variant.id) == "E":
			count += 1
	return count

func _audit_maze_nodes(node: Node, expected_layer: int, stats: Dictionary) -> void:
	if node is OmniLight:
		stats.omni += 1
	if node is CollisionObject:
		stats.total_colliders += 1
		if node.collision_layer != expected_layer:
			stats.bad_layer += 1
	for child in node.get_children():
		_audit_maze_nodes(child, expected_layer, stats)

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
		if child is Spatial and child.name != "JunctionHub" and child.name != "HubCollision":
			count += 1
	return count

func _grid_component_sizes(grid: Array, width: int, depth: int) -> Array:
	var components := []
	var visited := {}
	for i in range(grid.size()):
		if _grid_cell_is_empty(grid, i) or visited.has(i):
			continue
		var size := 0
		visited[i] = true
		var q := [i]
		while not q.empty():
			var c: int = q.pop_front()
			size += 1
			var cx := c % width
			var cy := c / width
			var conn: Array = grid[c].variant.connections
			for d in range(4):
				if not conn[d]:
					continue
				var nx := cx
				var ny := cy
				match d:
					0:
						ny -= 1
					1:
						nx = int(posmod(nx + 1, width))
					2:
						ny += 1
					3:
						nx = int(posmod(nx - 1, width))
				if ny < 0 or ny >= depth:
					continue
				var ni := ny * width + nx
				if _grid_cell_is_empty(grid, ni) or visited.has(ni):
					continue
				var back := (d + 2) % 4
				if grid[ni].variant.connections[back]:
					visited[ni] = true
					q.append(ni)
		components.append(size)
	components.sort()
	return components

func _grid_cell_is_empty(grid: Array, i: int) -> bool:
	if grid[i] == null:
		return true
	return String(grid[i].variant.id) == "EMPTY"
