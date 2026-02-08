extends GdUnitTestSuite

func test_props_load_and_instantiate():
	var runner = scene_runner("res://core_v2/tests/TestScene_SciFiLights.tscn")
	yield(runner.simulate_frames(10), "completed")

	var floating_light = runner.scene().get_node("SciFiFloatingLightV2")
	var static_light = runner.scene().get_node("SciFiStaticLightV2")
	var floor_panel = runner.scene().get_node("SciFiFloorPanelV2")

	assert_object(floating_light).is_not_null()
	assert_object(static_light).is_not_null()
	assert_object(floor_panel).is_not_null()

	# Verify floating light moves
	var pos1 = floating_light.translation
	yield(runner.simulate_frames(20), "completed")
	var pos2 = floating_light.translation

	# Check if it moved
	if pos1.distance_to(pos2) <= 0.0001:
		fail("Floating light did not move. Pos1: %s, Pos2: %s" % [pos1, pos2])
