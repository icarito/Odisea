extends GdUnitTestSuite

const ColdRuptureEventScript = preload("res://core_v2/systems/cryo/ColdRuptureEvent.gd")
const CoolantLeakScript = preload("res://core_v2/systems/cryo/CoolantLeak.gd")


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
