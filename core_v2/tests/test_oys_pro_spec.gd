# core_v2/tests/test_oys_pro_spec.gd
extends GdUnitTestSuite

const OYSComponent = preload("res://core_v2/components/OYSComponent.gd")

func test_oys_pro_execution() -> void:
	var runner := scene_runner("res://core_v2/scenes/TestScene_PushableBox.tscn")

	var player = runner.scene().find_node("Pilot", true, false)
	assert_object(player).is_not_null()

	var comp = OYSComponent.new()
	comp.name = "OYSComponent"
	player.add_child(comp)

	comp.load_and_start("res://core_v2/tests/test_pro.oys")

	# Wait for completion (the script has WAIT 0.1, so it should finish quickly)
	var timeout = 200 # frames
	while comp.interpreter.is_running and timeout > 0:
		yield (runner.simulate_frames(1), "completed")
		timeout -= 1

	assert_bool(comp.interpreter.is_running).is_false()
	assert_float(comp.interpreter.variables.get("$test_var", 0)).is_equal(10.0)
	assert_int(comp.interpreter.variables.get("$player_count", 0)).is_equal(1)

	print("[TEST] OYS Pro execution successful")
