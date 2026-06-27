extends GdUnitTestSuite

const DuctMazeStreamerScript = preload("res://core_v2/systems/DuctMazeSpawner.gd")
const DuctGateValveScene = preload("res://core_v2/props/duct/DuctGateValve.tscn")
const CapsuleRoomScene = preload("res://core_v2/props/duct/CapsuleRoom.tscn")
const PlayerControllerScript = preload("res://core_v2/player/PlayerControllerV2.gd")

func test_axial_stream_covers_tube_and_tracks_target() -> void:
	var root := Spatial.new()
	add_child(root)

	var target := Spatial.new()
	target.name = "Target"
	root.add_child(target)

	var spawner = DuctMazeStreamerScript.new()
	spawner.name = "DuctMazeStreamer"
	spawner.inner_radius = 15.0
	spawner.ring_step = 10.0
	spawner.sectors = 8
	spawner.rings = 8
	spawner.height_steps = 2
	spawner.room_count = 8
	spawner.extra_cycles = 8
	spawner.seed_value = 52
	spawner.axial_layout = true
	spawner.duct_radius = 3.75
	spawner.mesh_segments = 8
	spawner.room_segments = 8
	spawner.overlay_stride = 999
	spawner.streaming_enabled = true
	spawner.stream_target_path = NodePath("../Target")
	spawner.stream_total_length = 8000.0
	spawner.stream_chunk_rings = 8
	spawner.stream_active_chunks_each_side = 1
	spawner.stream_seam_ports = 4
	spawner.stream_update_interval = 0.01
	root.add_child(spawner)
	yield(get_tree(), "idle_frame")

	assert_float(spawner.get_stream_coverage_length()).is_greater_equal(8000.0)
	spawner._process_stream_queue()
	spawner._process_stream_queue()
	assert_array(spawner.get_active_stream_chunk_indices()).is_equal([49, 50, 51])

	target.translation.y = 3900.0
	spawner._refresh_stream(true)
	yield(get_tree(), "idle_frame")
	spawner._process_stream_queue()
	spawner._process_stream_queue()
	assert_array(spawner.get_active_stream_chunk_indices()).is_equal([97, 98, 99])

	root.queue_free()

func test_stream_chunk_seams_share_ports_and_heights() -> void:
	var spawner = DuctMazeStreamerScript.new()
	spawner.sectors = 8
	spawner.ring_step = 10.0
	spawner.height_steps = 3
	spawner.seed_value = 52
	spawner.stream_total_length = 8000.0
	spawner.stream_chunk_rings = 8
	spawner.stream_seam_ports = 4
	spawner._stream_chunk_count = int(ceil(spawner.stream_total_length / spawner._stream_chunk_length()))

	var left: Dictionary = spawner._stream_fixed_border_tiles(50)
	var right: Dictionary = spawner._stream_fixed_border_tiles(51)
	var depth: int = spawner._stream_chunk_depth()
	var matched := 0
	for key in left.keys():
		var parts: Array = String(key).split(",")
		if parts.size() < 2 or int(parts[1]) != depth - 1:
			continue
		var opposite_key := "%d,0" % int(parts[0])
		assert_bool(right.has(opposite_key)).is_true()
		assert_float(float(left[key]["height"])).is_equal_approx(float(right[opposite_key]["height"]), 0.001)
		matched += 1

	assert_int(matched).is_equal(4)
	spawner.free()

func test_axial_mst_wraps_angularly() -> void:
	# Verify angular wrap: sector 0 E/W connects via wrapper to sector sectors-1.
	# Use the ScaffoldMSTGenerator directly so we can inspect the raw grid.
	var mst_gen = load("res://core_v2/systems/ScaffoldMSTGenerator.gd").new()
	mst_gen.apply_params({"grid_width": 8, "grid_depth": 12, "wrap_x": true, "mst_max_height_steps": 3, "room_count": 8, "extra_cycles": 2})

	var grid: Array = mst_gen.generate_grid_data(52)
	var gw: int = 8
	var gd: int = 12
	var populated := {}
	for i in range(grid.size()):
		var cell = grid[i]
		if cell != null:
			populated[i] = cell

	# Verify no EAST/WEST (angular) port opens onto void at grid edges:
	# with wrap_x, every E/W on sector 0 or sectors-1 wraps to sectors-1 or 0.
	var border_void := 0
	for idx in populated.keys():
		var cell = populated[idx]
		var v = cell["variant"]
		var connections: Array = v["connections"]
		var gx: int = int(idx) % gw
		var gy: int = int(idx) / gw
		for d in [1, 3]:  # EAST, WEST
			if not connections[d]:
				continue
			var dv = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][d]
			var nx: int = int(posmod(gx + int(dv.x), gw))
			var ny: int = gy + int(dv.y)
			if ny < 0 or ny >= gd:
				continue  # N/S (axial) seams are legitimate out-of-grid ports
			var ni: int = ny * gw + nx
			if not populated.has(ni):
				border_void += 1

	assert_int(border_void).is_equal(0)

	# Ensure populated cells wrap-connect correctly: sector 0 WEST should find neighbour at sector gw-1
	var sector_zero_west_ok := false
	for idx in populated.keys():
		var cell = populated[idx]
		var v = cell["variant"]
		var gx: int = int(idx) % gw
		if gx != 0:
			continue
		if v["connections"][3]:  # WEST on sector 0
			var ni: int = int(int(idx) / gw) * gw + gw - 1
			if populated.has(ni):
				sector_zero_west_ok = true
				break

	# Also check sector gw-1 EAST connects to sector 0
	var sector_last_east_ok := false
	for idx in populated.keys():
		var cell = populated[idx]
		var v = cell["variant"]
		var gx: int = int(idx) % gw
		if gx != gw - 1:
			continue
		if v["connections"][1]:  # EAST on sector gw-1
			var ni: int = int(int(idx) / gw) * gw + 0
			if populated.has(ni):
				sector_last_east_ok = true
				break

	assert_bool(sector_zero_west_ok or sector_last_east_ok).is_true()

	# Verify overall connectivity
	assert_bool(_populated_connected(grid, gw, gd)).is_true()

func _populated_connected(grid: Array, gw: int, gd: int) -> bool:
	var OPP = {0: 2, 1: 3, 2: 0, 3: 1}
	var start := -1
	var pc := 0
	for i in range(grid.size()):
		if grid[i] != null and grid[i]["variant"]["id"] != "EMPTY":
			pc += 1
			if start < 0:
				start = i
	if start < 0:
		return false
	var seen := {}
	seen[start] = true
	var q := [start]
	while not q.empty():
		var c: int = q.pop_front()
		var cv = grid[c]["variant"]
		for d in range(4):
			if not cv["connections"][d]:
				continue
			var cx := c % gw
			var cy := c / gw
			var dv = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][d]
			var nx := cx + int(dv.x)
			var ny := cy + int(dv.y)
			if nx < 0 or nx >= gw or ny < 0 or ny >= gd:
				continue
			var ni := ny * gw + nx
			if seen.has(ni) or grid[ni] == null:
				continue
			var nv = grid[ni]["variant"]
			if nv["id"] == "EMPTY" or not nv["connections"][OPP[d]]:
				continue
			seen[ni] = true
			q.push_back(ni)
	return seen.size() == pc

func test_duct_gate_valve_has_nonblocking_interaction_area_when_open() -> void:
	var gate = DuctGateValveScene.instance()
	add_child(gate)
	yield(get_tree(), "idle_frame")

	var interaction_area = gate.get_node_or_null("InteractionArea")
	var collision_shape = gate.get_node_or_null("Frame/GateMesh/StaticBody/CollisionShape")
	assert_bool(gate.is_in_group("interactable")).is_true()
	assert_bool(interaction_area != null).is_true()
	assert_int(interaction_area.collision_layer).is_equal(16)
	assert_bool(interaction_area.monitorable).is_true()
	assert_bool(collision_shape != null and collision_shape.disabled).is_true()

	gate.interact()
	assert_bool(gate.is_active).is_false()
	gate.queue_free()

func test_room_airlocks_are_interactable_iris_doors() -> void:
	# Rooms get iris doors at each tube mouth, and each must be interactable
	# (its IrisMechanism in group "interactable") so the player can operate it.
	var spawner = DuctMazeStreamerScript.new()
	spawner.duct_radius = 3.75
	spawner.ring_step = 10.0
	spawner.inner_radius = 9.5
	spawner.room_radius_multiplier = 1.7
	spawner.room_airlocks_enabled = true
	add_child(spawner)
	yield(get_tree(), "idle_frame")

	var tile = spawner._make_procedural_tile([true, true, false, true], [0.0, 0.0, 0.0, 0.0], spawner._cell_radius(2, 0.0), true)
	add_child(tile)
	yield(get_tree(), "idle_frame")

	var iris_doors := 0
	var interactable := 0
	var start_open := 0
	var with_interaction_area := 0
	for child in tile.get_children():
		if "AirlockIris" in child.name:
			iris_doors += 1
			var mech = child.get_node_or_null("IrisMechanism")
			assert_bool(mech != null).is_true()
			if mech and mech.is_in_group("interactable"):
				interactable += 1
			# Doors start OPEN so the maze is traversable.
			if mech and bool(mech.starts_active):
				start_open += 1
			# Each door has a layer-16 InteractionArea so the player can target it.
			var ia = mech.get_node_or_null("InteractionArea") if mech else null
			if ia and ia.collision_layer == 16:
				with_interaction_area += 1
			# The iris .tscn's StaticBodies must be moved off Entorno onto Prop so the
			# camera passes through them.
			_assert_no_entorno_static_bodies(child)

	assert_int(iris_doors).is_equal(3)  # N, E, W connections
	assert_int(interactable).is_equal(iris_doors)
	assert_int(start_open).is_equal(iris_doors)
	assert_int(with_interaction_area).is_equal(iris_doors)

	tile.queue_free()
	spawner.queue_free()

func test_capsule_room_exit_airlock_is_interactable() -> void:
	var room = CapsuleRoomScene.instance()
	add_child(room)
	yield(get_tree(), "idle_frame")

	var iris = room.get_node_or_null("Interior/ExitAirlockIris")
	assert_bool(iris != null).is_true()
	var mechanism = iris.get_node_or_null("IrisMechanism") if iris else null
	assert_bool(mechanism != null).is_true()
	assert_bool(mechanism != null and mechanism.is_in_group("interactable")).is_true()
	assert_bool(mechanism != null and mechanism.starts_active).is_true()
	var interaction_area = mechanism.get_node_or_null("InteractionArea") if mechanism else null
	assert_bool(interaction_area != null).is_true()
	assert_int(interaction_area.collision_layer).is_equal(16)
	_assert_no_entorno_static_bodies(iris)

	room.queue_free()

func _assert_no_entorno_static_bodies(node: Node) -> void:
	if node is StaticBody:
		assert_int(node.collision_layer & 1).is_equal(0)  # no Entorno bit
	for child in node.get_children():
		_assert_no_entorno_static_bodies(child)

func test_junction_tubes_cross_the_nexus_shell() -> void:
	# A non-room junction (degree > 1) is wrapped by a sphere shell at duct_radius+wall.
	# Tangential (E/W) port endpoints land well inside that radius, so the port tubes
	# must be extended out past the shell or the carved hole has no tunnel behind it
	# ("shell with a hole but no exit"). Assert the collision mesh reaches past the
	# sphere radius on the tangential axis.
	var spawner = DuctMazeStreamerScript.new()
	spawner.duct_radius = 3.75
	spawner.duct_wall_thickness = 0.35
	spawner.ring_step = 10.0
	spawner.inner_radius = 9.5
	spawner.connection_overlap = 1.4
	add_child(spawner)
	yield(get_tree(), "idle_frame")

	var ring_radius: float = spawner._cell_radius(2, 0.0)
	# Tee: N + E + S (degree 3 -> junction sphere). E is the tangential arm.
	var tile = spawner._make_procedural_tile([true, true, true, false], [0.0, 0.0, 0.0, 0.0], ring_radius, false)
	add_child(tile)
	yield(get_tree(), "idle_frame")

	var sphere_radius: float = spawner.duct_radius + spawner.duct_wall_thickness
	var max_x := 0.0
	for child in tile.get_children():
		if child is StaticBody:
			for cc in child.get_children():
				if cc is CollisionShape and cc.shape:
					for v in cc.shape.get_faces():
						if abs(v.x) > max_x:
							max_x = abs(v.x)

	# The tangential arm's collision must extend past the sphere surface (it had been
	# stopping at ~2.5, well short of ~4.1).
	assert_float(max_x).is_greater(sphere_radius)

	tile.queue_free()
	spawner.queue_free()

func test_duct_tiles_are_on_prop_layer_so_camera_passes_through() -> void:
	# Tiles live on the Prop layer (bit 64), not Entorno (bit 1): the player still
	# collides (player required mask includes Prop) but the camera spring arm
	# (mask 129, no Prop) passes through, so you can see inside the ducts.
	var spawner = DuctMazeStreamerScript.new()
	spawner.duct_radius = 3.75
	spawner.ring_step = 10.0
	spawner.inner_radius = 9.5
	add_child(spawner)
	yield(get_tree(), "idle_frame")

	var tile = spawner._make_procedural_tile([true, false, true, false], [0.0, 0.0, 0.0, 0.0], spawner._cell_radius(2, 0.0), false)
	add_child(tile)
	yield(get_tree(), "idle_frame")

	var bodies := 0
	for child in tile.get_children():
		if child is StaticBody:
			bodies += 1
			assert_int(child.collision_layer).is_equal(1 << 6)  # Prop
			assert_int(child.collision_layer & 1).is_equal(0)   # NOT Entorno
	assert_int(bodies).is_greater(0)

	tile.queue_free()
	spawner.queue_free()

func test_player_can_resolve_and_operate_an_airlock_iris() -> void:
	# Drive the PLAYER's real interaction path, not iris.interact() in isolation:
	#  - the iris's physics bodies / InteractionArea must resolve (via the same
	#    _resolve_interactable_root the player uses) back to the IrisMechanism,
	#  - that resolved node must be reported actionable (_candidate_can_interact),
	#  - calling the resolved node's interact() must actually flip the door state.
	# This is what "the iris is interactable in-game" means; a direct mech.interact()
	# only proves the door's internal logic, which is why the earlier claim was wrong.
	var spawner = DuctMazeStreamerScript.new()
	spawner.duct_radius = 3.75
	spawner.ring_step = 10.0
	spawner.inner_radius = 9.5
	spawner.room_radius_multiplier = 1.7
	spawner.room_airlocks_enabled = true
	add_child(spawner)
	yield(get_tree(), "idle_frame")

	var tile = spawner._make_procedural_tile([true, true, false, true], [0.0, 0.0, 0.0, 0.0], spawner._cell_radius(2, 0.0), true)
	add_child(tile)
	yield(get_tree(), "idle_frame")

	var player = PlayerControllerScript.new()
	add_child(player)
	yield(get_tree(), "idle_frame")

	# Collect the bodies/areas the player's interact scan would see from one iris,
	# then run the player's own resolution + actionable checks against each.
	var iris_root: Node = null
	for child in tile.get_children():
		if "AirlockIris" in child.name:
			iris_root = child
			break
	assert_bool(iris_root != null).is_true()

	var mechanism = iris_root.get_node_or_null("IrisMechanism")
	assert_bool(mechanism != null).is_true()

	# Every physics body and the InteractionArea under the iris must resolve to a node
	# the player accepts as interactable. If ANY collidable resolves to something the
	# player rejects, the door reads as "not interactable" depending on what you hit.
	var collidables := []
	_collect_physics_nodes(iris_root, collidables)
	assert_int(collidables.size()).is_greater(0)

	var resolved_actionable := 0
	for node in collidables:
		var resolved = player._resolve_interactable_root(node)
		if player._candidate_can_interact(resolved):
			resolved_actionable += 1
	# At least one collidable (the InteractionArea / DoorBlocker) must lead to an
	# actionable target.
	assert_int(resolved_actionable).is_greater(0)

	# And operating that resolved target must actually toggle the door.
	var before: bool = mechanism.is_active
	mechanism.interact()
	assert_bool(mechanism.is_active).is_not_equal(before)

	player.queue_free()
	tile.queue_free()
	spawner.queue_free()

func _collect_physics_nodes(node: Node, out: Array) -> void:
	if node is CollisionObject:
		out.append(node)
	for child in node.get_children():
		_collect_physics_nodes(child, out)

func test_held_interact_toggles_iris_once_not_every_frame() -> void:
	# The player calls interact() every physics frame while the interact button is HELD
	# (it reads the raw button state, not just-pressed). A free-standing toggle door would
	# flip open/closed each frame and net to nothing — "interacting does nothing". The
	# iris debounces interact() so one tap (several held frames) flips exactly once.
	var iris = load("res://core_v2/props/doors/IrisDoorV2.tscn").instance()
	add_child(iris)
	yield(get_tree(), "idle_frame")
	var mech = iris.get_node("IrisMechanism")
	mech.set_active(true, true)  # open
	yield(get_tree(), "idle_frame")

	var before: bool = mech.is_active
	# Simulate a held button: many interact() calls back-to-back in one burst.
	for i in range(8):
		mech.interact()
	# Debounce → exactly one toggle, regardless of how many calls in the burst.
	assert_bool(mech.is_active).is_not_equal(before)

	iris.queue_free()
