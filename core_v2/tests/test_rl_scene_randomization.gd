extends GdUnitTestSuite

const AnnaInterface = preload("res://core_v2/anna/AnnaInterface.gd")

func _free_node(node: Node) -> void:
	if node and is_instance_valid(node):
		node.queue_free()
	yield (get_tree(), "idle_frame")

func _setup_scene_with_anna(scene_path: String) -> Dictionary:
	var runner = scene_runner(scene_path)
	yield (runner.simulate_frames(3), "completed")
	var scene = runner.scene()
	var pilot = scene.get_node_or_null("Pilot")
	assert_object(pilot).is_not_null()

	var sm = get_node_or_null("/root/SessionManager")
	assert_object(sm).is_not_null()
	var prev_player = sm.player
	var prev_recording = sm.is_recording
	var prev_override = sm._oys_input_override
	sm.player = pilot
	sm.is_recording = true
	sm._oys_input_override = {}

	var anna = AnnaInterface.new()
	scene.add_child(anna)
	yield (runner.simulate_frames(2), "completed")

	return {
		"runner": runner,
		"scene": scene,
		"pilot": pilot,
		"anna": anna,
		"sm": sm,
		"prev_player": prev_player,
		"prev_recording": prev_recording,
		"prev_override": prev_override,
	}

func _teardown_scene_with_anna(ctx: Dictionary) -> void:
	var sm = ctx.get("sm", null)
	if sm:
		sm.player = ctx.get("prev_player", null)
		sm.is_recording = ctx.get("prev_recording", false)
		sm._oys_input_override = ctx.get("prev_override", {})
	var anna = ctx.get("anna", null)
	if anna:
		yield (_free_node(anna), "completed")

func _horizontal_dist(a: Vector3, b: Vector3) -> float:
	var d = a - b
	d.y = 0.0
	return d.length()

func _has_valid_floor(scene: Spatial, p: Vector3) -> bool:
	if scene == null:
		return false
	var viewport = scene.get_viewport()
	if viewport == null or viewport.world == null:
		return false
	var from = p + Vector3.UP * 0.8
	var to = p - Vector3.UP * 3.2
	var hit = viewport.world.direct_space_state.intersect_ray(from, to, [], 0x7FFFFFFF, true, false)
	return typeof(hit) == TYPE_DICTIONARY and hit.has("position")

func test_rl_scenes_keep_spawn_target_on_valid_surface_and_distance() -> void:
	var scenes = [
		"res://core_v2/tests/TestScene_RL.tscn",
		"res://core_v2/tests/TestScene_RL_2.tscn",
		"res://core_v2/tests/TestScene_RL_3.tscn",
	]
	for scene_path in scenes:
		var ctx = yield (_setup_scene_with_anna(scene_path), "completed")
		var anna = ctx["anna"]
		var pilot = ctx["pilot"]
		for _i in range(10):
			anna.reset_simulation()
			var episode_flags = anna._rl_last_episode_override
			var has_spawn = episode_flags.has("spawn") and episode_flags["spawn"] is Vector3
			var has_target = episode_flags.has("target") and episode_flags["target"] is Vector3
			assert_bool(has_spawn).is_true()
			assert_bool(has_target).is_true()
			if not has_spawn or not has_target:
				continue
			var spawn_pos: Vector3 = episode_flags["spawn"]
			var target_pos: Vector3 = episode_flags["target"]
			var pilot_pos = pilot.global_transform.origin
			var spawn_ok = _has_valid_floor(ctx["scene"], spawn_pos)
			var target_ok = _has_valid_floor(ctx["scene"], target_pos)
			var dist_ok = _horizontal_dist(spawn_pos, target_pos) >= 7.0
			var pilot_spawn_ok = _horizontal_dist(pilot_pos, spawn_pos) <= 1.0
			assert_bool(spawn_ok).is_true()
			assert_bool(target_ok).is_true()
			assert_bool(dist_ok).is_true()
			assert_bool(pilot_spawn_ok).is_true()
		yield (_teardown_scene_with_anna(ctx), "completed")

func test_rl3_door_respects_80_20_bias() -> void:
	var ctx = yield (_setup_scene_with_anna("res://core_v2/tests/TestScene_RL_3_Door.tscn"), "completed")
	var anna = ctx["anna"]
	var far_count = 0
	var total = 60
	for _i in range(total):
		anna.reset_simulation()
		var episode_flags = anna._rl_last_episode_override
		if episode_flags.has("door_required") and episode_flags["door_required"] == true:
			far_count += 1
	var ratio = float(far_count) / float(total)
	assert_bool(ratio > 0.65).is_true()
	assert_bool(ratio < 0.95).is_true()
	yield (_teardown_scene_with_anna(ctx), "completed")

func test_rl4_target_stays_in_upper_room() -> void:
	var ctx = yield (_setup_scene_with_anna("res://core_v2/tests/TestScene_RL_4_TwoFloorRoom.tscn"), "completed")
	var anna = ctx["anna"]
	for _i in range(18):
		anna.reset_simulation()
		var episode_flags = anna._rl_last_episode_override
		var has_target = episode_flags.has("target") and episode_flags["target"] is Vector3
		assert_bool(has_target).is_true()
		if not has_target:
			continue
		var p: Vector3 = episode_flags["target"]
		assert_bool(p.y > 4.0).is_true()
		assert_bool(p.x > 2.2 and p.x < 10.8).is_true()
		assert_bool(p.z < -3.0 and p.z > -10.5).is_true()
	yield (_teardown_scene_with_anna(ctx), "completed")
