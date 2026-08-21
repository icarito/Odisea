extends GdUnitTestSuite

const RadiatorScene := preload("res://core_v2/props/machinery/RadiatorProp.tscn")

func _scene_host() -> Node:
	return get_tree().current_scene if get_tree().current_scene else self

func test_radiator_scene_instantiation() -> void:
	var host = _scene_host()
	var radiator = RadiatorScene.instance()
	assert_object(radiator).is_not_null()
	host.add_child(radiator)
	yield(get_tree(), "idle_frame")

	assert_bool(radiator.is_in_group("replay_sync")).is_true()
	assert_object(radiator.get_node_or_null("FrameMesh")).is_not_null()
	assert_object(radiator.get_node_or_null("ElementsMesh")).is_not_null()
	assert_object(radiator.get_node_or_null("FinsMesh")).is_not_null()
	assert_object(radiator.get_node_or_null("OmniLight")).is_not_null()

	radiator.queue_free()
	yield(get_tree(), "idle_frame")

func test_interaction_drives_heat_level() -> void:
	var host = _scene_host()
	var radiator = RadiatorScene.instance()
	host.add_child(radiator)
	yield(get_tree(), "idle_frame")

	assert_float(radiator.heat_level).is_equal(0.0)
	assert_bool(radiator.is_active).is_false()

	var state := [false, -1.0]
	radiator.connect("heat_level_changed", self, "_on_heat_level_changed", [state])

	# Interact -> set_active(true)
	radiator.interact()
	assert_bool(radiator.is_active).is_true()

	# Step physics to advance anim_progress and heat_level
	radiator.step(0.5)
	assert_float(radiator.heat_level).is_equal(0.5)
	assert_bool(state[0]).is_true()
	assert_float(state[1]).is_equal(0.5)

	radiator.step(0.6)
	assert_float(radiator.heat_level).is_equal(1.0)
	assert_float(radiator.anim_progress).is_equal(1.0)

	# Interact again -> set_active(false)
	radiator.interact()
	assert_bool(radiator.is_active).is_false()

	radiator.step(0.5)
	assert_float(radiator.heat_level).is_equal(0.5)

	radiator.step(0.6)
	assert_float(radiator.heat_level).is_equal(0.0)

	radiator.queue_free()
	yield(get_tree(), "idle_frame")

func test_heat_level_clamping_and_signal() -> void:
	var host = _scene_host()
	var radiator = RadiatorScene.instance()
	host.add_child(radiator)
	yield(get_tree(), "idle_frame")

	var state := [false, -1.0]
	radiator.connect("heat_level_changed", self, "_on_heat_level_changed", [state])

	# Test set to 0.5
	radiator.set_heat_level(0.5)
	assert_float(radiator.heat_level).is_equal(0.5)
	assert_float(radiator.anim_progress).is_equal(0.5)
	assert_bool(state[0]).is_true()
	assert_float(state[1]).is_equal(0.5)

	# Test clamping above 1.0
	state[0] = false
	radiator.set_heat_level(1.8)
	assert_float(radiator.heat_level).is_equal(1.0)
	assert_float(radiator.anim_progress).is_equal(1.0)
	assert_bool(state[0]).is_true()
	assert_float(state[1]).is_equal(1.0)

	# Test clamping below 0.0
	state[0] = false
	radiator.set_heat_level(-0.4)
	assert_float(radiator.heat_level).is_equal(0.0)
	assert_float(radiator.anim_progress).is_equal(0.0)
	assert_bool(state[0]).is_true()
	assert_float(state[1]).is_equal(0.0)

	radiator.queue_free()
	yield(get_tree(), "idle_frame")

func test_heat_level_visual_interpolation_smoothness() -> void:
	var host = _scene_host()
	var radiator = RadiatorScene.instance()
	host.add_child(radiator)
	yield(get_tree(), "idle_frame")

	var color_0: Color = radiator.get_heat_color(0.0)
	var color_03: Color = radiator.get_heat_color(0.3)
	var color_07: Color = radiator.get_heat_color(0.7)
	var color_1: Color = radiator.get_heat_color(1.0)

	# Cold should be dark/black
	assert_float(color_0.r).is_equal(0.0)
	assert_float(color_0.g).is_equal(0.0)
	assert_float(color_0.b).is_equal(0.0)

	# Red should increase
	assert_bool(color_03.r > color_0.r).is_true()
	assert_bool(color_07.r >= color_03.r).is_true()
	assert_bool(color_1.r >= color_07.r).is_true()

	# Green/White component increases at highest heat
	assert_bool(color_1.g > color_03.g).is_true()

	var prev_r: float = 0.0
	var steps: int = 20
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		radiator.set_heat_level(t)
		var col: Color = radiator.get_heat_color(t)

		assert_bool(is_nan(col.r) or is_nan(col.g) or is_nan(col.b)).is_false()
		assert_bool(col.r >= prev_r - 0.0001).is_true()
		prev_r = col.r

	radiator.queue_free()
	yield(get_tree(), "idle_frame")

func test_determinism_and_snapshot() -> void:
	var host = _scene_host()
	var radiator1 = RadiatorScene.instance()
	host.add_child(radiator1)
	yield(get_tree(), "idle_frame")

	radiator1.set_heat_level(0.82)
	var snapshot: Dictionary = radiator1.get_snapshot()

	assert_bool(snapshot.has("heat_level")).is_true()
	assert_float(snapshot["heat_level"]).is_equal(0.82)

	var radiator2 = RadiatorScene.instance()
	host.add_child(radiator2)
	yield(get_tree(), "idle_frame")

	radiator2.restore_snapshot(snapshot)
	assert_float(radiator2.heat_level).is_equal(0.82)
	assert_float(radiator2.anim_progress).is_equal(0.82)

	var col1: Color = radiator1.get_heat_color(radiator1.heat_level)
	var col2: Color = radiator2.get_heat_color(radiator2.heat_level)
	assert_float(col1.r).is_equal(col2.r)
	assert_float(col1.g).is_equal(col2.g)
	assert_float(col1.b).is_equal(col2.b)

	radiator1.queue_free()
	radiator2.queue_free()
	yield(get_tree(), "idle_frame")

func _on_heat_level_changed(new_val: float, state: Array) -> void:
	state[0] = true
	state[1] = new_val
