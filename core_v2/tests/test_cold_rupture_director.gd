extends GdUnitTestSuite

# test_cold_rupture_director.gd - Unit & integration tests for ColdRuptureDirector and OYS integration.

const ColdRuptureDirectorScript = preload("res://core_v2/systems/cryo/ColdRuptureDirector.gd")
const OYSTriggerScript = preload("res://core_v2/components/OYSTrigger.gd")
const RandomLeakSeederScript = preload("res://core_v2/systems/cryo/RandomLeakSeeder.gd")


func test_director_registers_and_handles_oys_calls() -> void:
	var root = Spatial.new()
	add_child(root)

	var director = ColdRuptureDirectorScript.new()
	director.name = "ColdRuptureDirector"
	root.add_child(director)

	var focus = Spatial.new()
	focus.name = "RuptureFocus"
	root.add_child(focus)

	var seeder = RandomLeakSeederScript.new()
	seeder.name = "RandomLeakSeeder"
	root.add_child(seeder)

	var sm = director.get_node_or_null("/root/SessionManager")
	if sm != null:
		assert_bool(sm.get_oys_actor("ColdRupture") == director).is_true()

	var expl_pos = director.spawn_explosion()
	assert_bool(director.consumed).is_true()
	assert_bool(director.last_explosion_pos == expl_pos).is_true()

	var snapshot = director.get_snapshot()
	assert_bool(snapshot["consumed"]).is_true()

	var director2 = ColdRuptureDirectorScript.new()
	director2.name = "ColdRuptureDirector2"
	root.add_child(director2)
	director2.restore_snapshot(snapshot)
	assert_bool(director2.consumed).is_true()
	assert_bool(director2.last_explosion_pos == expl_pos).is_true()
	root.queue_free()


func test_oys_trigger_script_clears_file_on_trigger() -> void:
	var trigger = OYSTriggerScript.new()
	trigger.script_file = ""
	trigger.trigger_once = true
	add_child(trigger)
	yield(get_tree(), "idle_frame")

	trigger.script_file = "res://core_v2/levels/interiors/cold_rupture.oys"
	assert_bool(trigger.script_file != "").is_true()
	trigger.trigger_from_script(trigger)
	assert_bool(trigger.script_file == "").is_true()
