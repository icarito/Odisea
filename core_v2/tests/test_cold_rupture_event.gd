extends GdUnitTestSuite

const ColdRuptureEventScript = preload("res://core_v2/systems/cryo/ColdRuptureEvent.gd")
const CoolantLeakScript = preload("res://core_v2/systems/cryo/CoolantLeak.gd")
const RandomLeakSeederScript = preload("res://core_v2/systems/cryo/RandomLeakSeeder.gd")


func test_trigger_is_one_shot_and_snapshot_restores_the_same_leaks() -> void:
	var root: Spatial = auto_free(Spatial.new())
	add_child(root)
	var leak: Spatial = auto_free(CoolantLeakScript.new())
	leak.name = "Leak"
	root.add_child(leak)
	var rupture: Spatial = auto_free(ColdRuptureEventScript.new())
	rupture.name = "Rupture"
	rupture.candidate_leak_paths = [NodePath("../Leak")]
	root.add_child(rupture)

	rupture.trigger()
	assert_bool(rupture.consumed).is_true()
	assert_int(leak.get_state()).is_equal(CoolantLeak.State.WARNING)
	var snapshot: Dictionary = rupture.get_snapshot()
	assert_bool(snapshot.has("aftershock_remaining")).is_true()
	assert_bool(snapshot.has("aftershock_fired")).is_true()

	leak.reset()
	rupture.restore_snapshot(snapshot)
	assert_bool(rupture.consumed).is_true()
	assert_int(leak.get_state()).is_equal(CoolantLeak.State.WARNING)


func test_aftershock_is_advanced_by_physics_not_wall_time() -> void:
	var rupture: Spatial = auto_free(ColdRuptureEventScript.new())
	add_child(rupture)
	rupture.aftershock_delay = 0.1
	rupture.trigger()
	rupture._physics_process(0.05)
	assert_bool(rupture._aftershock_fired).is_false()
	rupture._physics_process(0.05)
	assert_bool(rupture._aftershock_fired).is_true()


func test_trigger_uses_seeded_leak_selection_when_present() -> void:
	var root: Spatial = auto_free(Spatial.new())
	add_child(root)
	for node_name in ["LeakA", "LeakB", "LeakC"]:
		var leak: Spatial = auto_free(CoolantLeakScript.new())
		leak.name = node_name
		root.add_child(leak)
	var seeder: Node = auto_free(RandomLeakSeederScript.new())
	seeder.name = "Seeder"
	seeder.seed_value = 99
	seeder.leak_count = 2
	seeder.candidate_leak_paths = [NodePath("../LeakA"), NodePath("../LeakB"), NodePath("../LeakC")]
	root.add_child(seeder)
	var rupture: Spatial = auto_free(ColdRuptureEventScript.new())
	rupture.leak_seeder_path = NodePath("../Seeder")
	root.add_child(rupture)

	rupture.trigger()
	var paths: Array = rupture.get_snapshot()["activated_leak_paths"]
	assert_int(paths.size()).is_equal(2)
	for path_value in paths:
		var leak: Node = rupture._get_target_node(NodePath(path_value))
		assert_int(leak.get_state()).is_equal(CoolantLeak.State.WARNING)
