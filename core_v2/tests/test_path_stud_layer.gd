extends GdUnitTestSuite

const PathStudLayerScript = preload("res://core_v2/components/PathStudLayer.gd")

func test_path_stud_layer_builds_from_positions():
	var layer = auto_free(PathStudLayerScript.new())
	add_child(layer)

	var positions := [
		Vector3(0, 0, 0),
		Vector3(2, 0, 0),
		Vector3(4, 0, 0),
		Vector3(6, 0, 0),
		Vector3(8, 0, 0)
	]
	layer.set_positions(positions)

	var mm_node: MultiMeshInstance = layer.get_node_or_null("StudMultiMesh")
	assert_object(mm_node).is_not_null()
	assert_object(mm_node.multimesh).is_not_null()
	assert_int(mm_node.multimesh.instance_count).is_equal(5)

func test_path_stud_layer_state_switches_emissive_pattern():
	var layer = auto_free(PathStudLayerScript.new())
	add_child(layer)

	var positions := [
		Vector3(0, 0, 0),
		Vector3(2, 0, 0),
		Vector3(4, 0, 0),
		Vector3(6, 0, 0),
		Vector3(8, 0, 0)
	]
	layer.set_positions(positions)
	layer.low_power_stride = 3

	var mm: MultiMesh = layer.get_node("StudMultiMesh").multimesh

	# FULL state
	layer.light_state = PathStudLayerScript.LightState.FULL
	assert_int(layer.light_state).is_equal(PathStudLayerScript.LightState.FULL)
	var col_full_0: Color = mm.get_instance_color(0)
	var col_full_1: Color = mm.get_instance_color(1)
	assert_float(col_full_0.r).is_equal_approx(layer.lit_color.r, 0.05)
	assert_float(col_full_1.r).is_equal_approx(layer.lit_color.r, 0.05)

	# DARK state
	layer.light_state = PathStudLayerScript.LightState.DARK
	assert_int(layer.light_state).is_equal(PathStudLayerScript.LightState.DARK)
	var col_dark_0: Color = mm.get_instance_color(0)
	assert_float(col_dark_0.r).is_equal_approx(layer.base_color.r, 0.05)

	# LOW_POWER state
	layer.light_state = PathStudLayerScript.LightState.LOW_POWER
	assert_int(layer.light_state).is_equal(PathStudLayerScript.LightState.LOW_POWER)
	var col_lp_0: Color = mm.get_instance_color(0) # index 0 is multiple of 3
	var col_lp_1: Color = mm.get_instance_color(1) # index 1 is not
	assert_float(col_lp_1.r).is_equal_approx(layer.base_color.r, 0.05)

func test_scifi_light_path_v2_integrates_stud_layer():
	var path_prop: SciFiLightPathV2 = auto_free(SciFiLightPathV2.new())
	path_prop.light_count = 6
	path_prop.enable_stud_layer = true
	add_child(path_prop)
	yield(get_tree(), "idle_frame")

	var stud_layer = path_prop.get_node_or_null("PathStudLayer")
	assert_object(stud_layer).is_not_null()

	var mm_node: MultiMeshInstance = stud_layer.get_node_or_null("StudMultiMesh")
	assert_object(mm_node).is_not_null()
	assert_int(mm_node.multimesh.instance_count).is_equal(6)

	path_prop.set_active(false, true) # anim_progress = 0.0, immediate
	assert_int(stud_layer.light_state).is_equal(PathStudLayerScript.LightState.DARK)

	path_prop.anim_progress = 0.5
	path_prop._update_visuals()
	assert_int(stud_layer.light_state).is_equal(PathStudLayerScript.LightState.LOW_POWER)

	path_prop.set_active(true, true) # anim_progress = 1.0, immediate
	assert_int(stud_layer.light_state).is_equal(PathStudLayerScript.LightState.FULL)

func test_light_path_v2_integrates_stud_layer():
	var path: LightPathV2 = auto_free(LightPathV2.new())
	path.spacing = 2.0
	path.enable_stud_layer = true
	add_child(path)

	var wp0 := Position3D.new()
	wp0.translation = Vector3(0, 0, 0)
	path.add_child(wp0)
	var wp1 := Position3D.new()
	wp1.translation = Vector3(8, 0, 0)
	path.add_child(wp1)

	path.build()
	yield(get_tree(), "idle_frame")

	var markers: MultiMeshInstance = path.get_node_or_null("Markers")
	assert_object(markers).is_not_null()

	var stud_layer = path.get_node_or_null("PathStudLayer")
	assert_object(stud_layer).is_not_null()

	var mm_node: MultiMeshInstance = stud_layer.get_node_or_null("StudMultiMesh")
	assert_object(mm_node).is_not_null()
	assert_int(mm_node.multimesh.instance_count).is_equal(markers.multimesh.instance_count)

	path.enable_stud_layer = false
	assert_bool(stud_layer.visible).is_false()
