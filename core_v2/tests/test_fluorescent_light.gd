extends GdUnitTestSuite

func test_flickering_light_stops_flickering_after_timeout_and_settles_to_final_state():
	var host: Spatial = auto_free(Spatial.new())
	add_child(host)

	var packed: PackedScene = load("res://core_v2/props/scifi_lights/FluorescentLightFlickering.tscn")
	assert_object(packed).is_not_null()

	var light = auto_free(packed.instance())
	light.flicker_timeout_seconds = 0.1
	light.flicker_timeout_random_offset = 0.0
	light.flicker_settle_on_probability = 0.0
	host.add_child(light)
	yield(get_tree(), "idle_frame")

	var omni: OmniLight = light.get_node("OmniLight")
	assert_object(omni).is_not_null()
	assert_float(omni.light_energy).is_greater(0.0)

	var settled := false
	for _i in range(30):
		yield(get_tree(), "physics_frame")
		if light._flicker_has_settled:
			settled = true
			break

	assert_bool(settled).is_true()
	assert_bool(light._flicker_has_settled).is_true()
	assert_bool(light._flicker_settled_on).is_false()
	assert_float(omni.light_energy).is_less_equal(0.001)
