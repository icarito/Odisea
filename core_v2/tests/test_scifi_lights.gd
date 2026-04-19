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


func test_emergency_beacon_trenchbroom_defaults_are_decorative_and_active():
	var host: Spatial = auto_free(Spatial.new())
	add_child(host)

	var packed: PackedScene = load("res://core_v2/props/EmergencyBeaconV2.tscn")
	assert_object(packed).is_not_null()

	var beacon: Node = auto_free(packed.instance())
	host.add_child(beacon)
	yield(get_tree(), "idle_frame")

	assert_bool(beacon.starts_active).is_true()
	assert_bool(beacon.is_active).is_true()
	assert_bool(beacon.is_interactable).is_false()
	assert_bool(beacon.is_in_group("interactable")).is_false()

	var omni: OmniLight = beacon.get_node("OmniLight")
	assert_object(omni).is_not_null()
	assert_float(omni.light_energy).is_greater(0.1)
	assert_float(omni.omni_range).is_equal(6.0)
	assert_bool(omni.shadow_enabled).is_true()

	beacon.is_interactable = true
	assert_bool(beacon.is_in_group("interactable")).is_true()
	beacon.is_interactable = false
	assert_bool(beacon.is_in_group("interactable")).is_false()


func test_emergency_beacon_point_class_exposes_standard_trenchbroom_controls():
	var point_class: Resource = load("res://core_v2/qodot_fgd/props/EmergencyBeaconV2_point_class.tres")
	assert_object(point_class).is_not_null()

	var props: Dictionary = point_class.get("class_properties")
	for key in [
		"_color",
		"angle",
		"angles",
		"starts_active",
		"is_interactable",
		"interaction_text",
		"light_color",
		"light_range",
		"light_energy_max",
		"pulse_speed",
		"rotation_speed",
		"sound_enabled"
	]:
		assert_bool(props.has(key)).is_true()

	assert_int(props["starts_active"]).is_equal(1)
	assert_int(props["is_interactable"]).is_equal(0)
	assert_int(props["enable_shadows"]).is_equal(1)
	assert_float(props["light_range"]).is_equal(6.0)


func test_emergency_beacon_fgd_uses_trenchbroom_native_angle_and_color_types():
	var file := File.new()
	var err := file.open("res://Qodot.fgd", File.READ)
	assert_int(err).is_equal(OK)
	var text := file.get_as_text()
	file.close()

	assert_bool(text.find("= light_emergency_beacon") >= 0).is_true()
	assert_bool(text.find("angle(angle) : \"Yaw rotation in degrees\"") >= 0).is_true()
	assert_bool(text.find("_color(color255) : \"Native TrenchBroom light color\"") >= 0).is_true()
