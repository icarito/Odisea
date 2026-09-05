extends GdUnitTestSuite

func test_android_prepares_detached_scene_without_mutating_shared_environment() -> void:
	var scene := Spatial.new()
	var world := WorldEnvironment.new()
	var original := Environment.new()
	original.glow_enabled = true
	original.adjustment_enabled = true
	original.dof_blur_far_enabled = true
	original.dof_blur_near_enabled = true
	original.fog_enabled = true
	original.ambient_light_energy = 0.23
	world.environment = original
	scene.add_child(world)
	var manager := get_node("/root/SceneManager")
	manager._prepare_android_environment(scene, "X11")
	assert_bool(world.environment == original).is_true()
	manager._prepare_android_environment(scene, "Android")
	assert_bool(scene.is_inside_tree()).is_false()
	assert_bool(world.environment == original).is_false()
	assert_bool(world.environment.glow_enabled).is_false()
	assert_bool(world.environment.adjustment_enabled).is_false()
	assert_bool(world.environment.dof_blur_far_enabled).is_false()
	assert_bool(world.environment.dof_blur_near_enabled).is_false()
	assert_bool(world.environment.fog_enabled).is_true()
	assert_float(world.environment.ambient_light_energy).is_equal_approx(0.23, 0.001)
	assert_bool(original.glow_enabled).is_true()
	assert_bool(original.adjustment_enabled).is_true()
	assert_bool(original.dof_blur_far_enabled).is_true()
	assert_bool(original.dof_blur_near_enabled).is_true()
	scene.free()

