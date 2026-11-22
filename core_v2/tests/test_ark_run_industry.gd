extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# FD-324 F3 — industria procedural: determinismo por hash, colisión gruesa siempre
# presente y reacople/falla estática de conectores por modo de gravedad.

const Catalog = preload("res://core_v2/levels/ark_run/ArkRunIndustryChunk.gd")
const Generator = preload("res://core_v2/levels/ark_run/ArkRunIndustryGenerator.gd")
const StreamerScript = preload("res://core_v2/levels/ark_run/ArkRunIndustryStreamer.gd")

func test_clusters_are_load_order_independent() -> void:
	var forward := {}
	for sector in [0, 1, 2, 3]:
		forward[sector] = Generator.generate_cluster(Generator.SLICE_SEED, sector, 2)
	var reverse := {}
	for sector in [3, 1, 0, 2]:
		reverse[sector] = Generator.generate_cluster(Generator.SLICE_SEED, sector, 2)
	for sector in [0, 1, 2, 3]:
		var a: Dictionary = forward[sector]
		var b: Dictionary = reverse[sector]
		assert_int(int(a["hash"])).is_equal(int(b["hash"]))
		assert_vector3(a["anchor"]).is_equal(b["anchor"])
		assert_vector3(a["basis"].xform(Vector3(1, 0, 0))).is_equal(b["basis"].xform(Vector3(1, 0, 0)))
		assert_vector3(a["basis"].xform(Vector3(0, 1, 0))).is_equal(b["basis"].xform(Vector3(0, 1, 0)))
		assert_array(a["pieces"]).is_equal(b["pieces"])
		assert_array(a["connectors"]).is_equal(b["connectors"])
		assert_array(a["links"]).is_equal(b["links"])
		assert_dict(a["bounds"]).is_equal(b["bounds"])

func test_coarse_collision_exists_without_streaming() -> void:
	var streamer = auto_free(StreamerScript.new())
	streamer.seed_value = Generator.SLICE_SEED
	streamer.stream_radius = 1.0
	streamer.pool_size = 4
	add_child(streamer)
	var far = auto_free(Spatial.new())
	far.name = "FarStreamTarget"
	add_child(far)
	far.global_transform.origin = Vector3(10000.0, 0.0, 0.0)
	streamer.set_stream_target(far)
	streamer.refresh_streaming()
	assert_int(streamer.get_fine_pool_size()).is_equal(0)
	var expected: int = streamer.sector_count * streamer.ring_slots
	assert_int(streamer.get_coarse_body_count()).is_equal(expected)
	var coarse = streamer.get_node_or_null("CoarseCollision")
	assert_object(coarse).is_not_null()
	assert_int(coarse.get_child_count()).is_equal(expected)
	for body in coarse.get_children():
		var center: Vector3 = streamer.to_global(body.transform.origin)
		var radius := sqrt(center.x * center.x + center.y * center.y)
		assert_float(radius).is_greater_equal(260.0 - 0.01)
		assert_float(radius).is_less_equal(300.0 + 0.01)
		assert_float(abs(center.z)).is_less_equal(1000.0 + 0.01)
	var cost := _measure_cost(streamer)
	print("ARK_INDUSTRY_COST clusters=%d coarse=%d nodes=%d shapes=%d vertices=%d" % [
		streamer.get_coarse_body_count(), expected, cost["nodes"], cost["shapes"], cost["vertices"]
	])

func test_streaming_pool_is_bounded_and_deterministic() -> void:
	var streamer = auto_free(StreamerScript.new())
	streamer.seed_value = Generator.SLICE_SEED
	streamer.stream_radius = 500.0
	streamer.pool_size = 4
	add_child(streamer)
	var target = auto_free(Spatial.new())
	target.name = "NearStreamTarget"
	add_child(target)
	target.global_transform.origin = Vector3(280.0, 0.0, 0.0)
	streamer.set_stream_target(target)
	streamer.refresh_streaming()
	assert_int(streamer.get_fine_pool_size()).is_equal(4)
	var first_ids := _fine_ids(streamer)
	streamer.refresh_streaming()
	assert_array(_fine_ids(streamer)).is_equal(first_ids)
	var cost := _measure_cost(streamer)
	print("ARK_INDUSTRY_STREAM_COST clusters=%d pool=%d nodes=%d shapes=%d vertices=%d" % [
		streamer.get_coarse_body_count(), streamer.get_fine_pool_size(),
		cost["nodes"], cost["shapes"], cost["vertices"]
	])

func test_connection_relink_is_deterministic_per_gravity_mode() -> void:
	var connectors := [
		"industry_gantry:in", "industry_gantry:side", "industry_bridge:a",
		"industry_gantry:out", "industry_catwalk:in", "industry_tower:out",
		"industry_machine:in", "industry_machine:z_in", "industry_pump:both",
		"industry_pump:z", "industry_junction:z_out", "industry_junction:x_in",
	]
	for mode in [Catalog.GRAVITY_CENTRIFUGAL, Catalog.GRAVITY_AXIAL]:
		var relinked := 0
		var blocked := 0
		for i in range(connectors.size() * 4):
			var cluster_id := "cluster_s%02d_r%02d" % [i, int(i / connectors.size()) % 8]
			var connector_id := str(connectors[i % connectors.size()])
			var first: Dictionary = Generator.evaluate_connection_relink(
				Generator.SLICE_SEED, cluster_id, connector_id, mode
			)
			var second: Dictionary = Generator.evaluate_connection_relink(
				Generator.SLICE_SEED, cluster_id, connector_id, mode
			)
			assert_dict(first).is_equal(second)
			assert_bool(bool(first["relinked"]) != bool(first["blocked"])).is_true()
			if bool(first["relinked"]): relinked += 1
			else: blocked += 1
		assert_int(relinked).is_greater(0)
		assert_int(blocked).is_greater(0)
	var axial_side: Dictionary = Generator.evaluate_connection_relink(
		Generator.SLICE_SEED, "cluster_s00_r00", "industry_gantry:side", Catalog.GRAVITY_AXIAL
	)
	assert_bool(axial_side["gravity_supported"]).is_false()
	assert_bool(axial_side["blocked"]).is_true()

func test_streamer_recomputes_static_route_state() -> void:
	var streamer = auto_free(StreamerScript.new())
	streamer.seed_value = Generator.SLICE_SEED
	streamer.sector_count = 6
	streamer.ring_slots = 4
	add_child(streamer)
	streamer.apply_gravity_mode(Catalog.GRAVITY_CENTRIFUGAL)
	var centrifugal: Dictionary = streamer.get_route_state_summary()
	streamer.apply_gravity_mode(Catalog.GRAVITY_AXIAL)
	var axial: Dictionary = streamer.get_route_state_summary()
	streamer.apply_gravity_mode(Catalog.GRAVITY_CENTRIFUGAL)
	var again: Dictionary = streamer.get_route_state_summary()
	assert_dict(centrifugal).is_equal(again)
	assert_bool(int(centrifugal["hash"]) != int(axial["hash"])).is_true()
	assert_int(int(axial["blocked"])).is_greater(0)

func _fine_ids(streamer) -> Array:
	var ids: Array = streamer._fine_pool.keys()
	ids.sort()
	return ids

func _measure_cost(node: Node) -> Dictionary:
	var nodes := 0
	var shapes := 0
	var vertices := 0
	var stack := [node]
	while not stack.empty():
		var current = stack.pop_back()
		nodes += 1
		if current is CollisionShape:
			shapes += 1
		if current is MeshInstance and current.mesh != null:
			vertices += current.mesh.get_faces().size()
		for child in current.get_children():
			stack.append(child)
	return {"nodes": nodes, "shapes": shapes, "vertices": vertices}
