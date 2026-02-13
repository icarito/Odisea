# core/tests/test_oys_pro_spec.gd
extends GdUnitTestSuite

const OYSComponent = preload("res://core/components/OYSComponent.gd")

func test_oys_pro_execution() -> void:
	var runner := scene_runner("res://core/levels/TestScene_PushableBox.tscn")

	var player = runner.scene().find_node("Pilot", true, false)
	assert_object(player).is_not_null()

	var comp = OYSComponent.new()
	comp.name = "OYSComponent"
	player.add_child(comp)

	comp.load_and_start("res://core/tests/test_pro.oys")

	# Wait a few frames for deferred call to kick in
	yield (runner.simulate_frames(5), "completed")
	
	# Wait for the interpreter to start
	var start_timeout = 30
	while not comp.interpreter.is_running and start_timeout > 0:
		yield (runner.simulate_frames(1), "completed")
		start_timeout -= 1
	
	# Wait for completion (the script has WAIT 0.1, so it should finish quickly)
	var timeout = 200 # frames
	while comp.interpreter.is_running and timeout > 0:
		yield (runner.simulate_frames(1), "completed")
		timeout -= 1

	assert_bool(comp.interpreter.is_running).is_false()
	var test_var = comp.interpreter.variables.get("$test_var", 0.0)
	var player_count = comp.interpreter.variables.get("$player_count", 0)
	assert_float(float(test_var)).is_equal(10.0)
	assert_int(int(player_count)).is_equal(1)

	print("[TEST] OYS Pro execution successful")
