extends GdUnitTestSuite

const GHOST_SCENE_PATH := "res://core_v2/levels/TestSceneGhost.tscn"

func test_ghost_scene_has_minimal_wired_triggers() -> void:
	var runner = scene_runner(GHOST_SCENE_PATH)
	yield (runner.simulate_frames(2), "completed")

	var scene = runner.scene()
	assert_object(scene).is_not_null()
	assert_object(scene.get_node_or_null("Pilot")).is_not_null()
	assert_object(scene.get_node_or_null("Floor")).is_not_null()

	var record = scene.get_node_or_null("GhostRecordTrigger")
	var loop_trigger = scene.get_node_or_null("GhostLoopTrigger")
	assert_object(record).is_not_null()
	assert_object(loop_trigger).is_not_null()

	assert_bool(bool(record.get("debug_render"))).is_true()
	assert_bool(bool(loop_trigger.get("debug_render"))).is_true()
	assert_bool(bool(record.get("trigger_once"))).is_false()
	assert_bool(bool(loop_trigger.get("trigger_once"))).is_false()

	assert_str(String(record.get("script_file"))).is_equal("res://core_v2/scripts/ghost_record_start.oys")
	assert_str(String(loop_trigger.get("script_file"))).is_equal("res://core_v2/scripts/ghost_stop_and_loop.oys")

	assert_object(scene.get_node_or_null("HeavyBlastDoor")).is_null()
	assert_object(scene.get_node_or_null("VentilationTurbine")).is_null()
