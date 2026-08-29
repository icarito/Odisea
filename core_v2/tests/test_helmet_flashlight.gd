extends GdUnitTestSuite


func test_helmet_flashlight_instantiation_and_defaults():
	var packed: PackedScene = load("res://core_v2/props/lights/HelmetFlashlight.tscn")
	assert_object(packed).is_not_null()

	var flashlight = auto_free(packed.instance())
	add_child(flashlight)
	yield(get_tree(), "idle_frame")

	var spot: SpotLight = flashlight.get_node_or_null("SpotLight")
	var cone: MeshInstance = flashlight.get_node_or_null("VolumetricCone")

	assert_object(spot).is_not_null()
	assert_object(cone).is_not_null()

	# MobileLightBudget contract: range must be < 6.0m
	assert_float(spot.spot_range).is_less(6.0)
	assert_bool(spot.shadow_enabled).is_false()
	assert_bool(flashlight.enabled).is_true()
	assert_bool(spot.visible).is_true()
	assert_bool(cone.visible).is_true()


func test_helmet_flashlight_toggle_visibility():
	var packed: PackedScene = load("res://core_v2/props/lights/HelmetFlashlight.tscn")
	var flashlight = auto_free(packed.instance())
	add_child(flashlight)
	yield(get_tree(), "idle_frame")

	var spot: SpotLight = flashlight.get_node("SpotLight")
	var cone: MeshInstance = flashlight.get_node("VolumetricCone")

	flashlight.toggle()
	assert_bool(flashlight.enabled).is_false()
	assert_bool(spot.visible).is_false()
	assert_bool(cone.visible).is_false()

	flashlight.toggle()
	assert_bool(flashlight.enabled).is_true()
	assert_bool(spot.visible).is_true()
	assert_bool(cone.visible).is_true()


func test_helmet_flashlight_scan_mode_scroll():
	var packed: PackedScene = load("res://core_v2/props/lights/HelmetFlashlight.tscn")
	var flashlight = auto_free(packed.instance())
	flashlight.scan_mode = true
	flashlight.scan_speed = 3.0
	add_child(flashlight)
	yield(get_tree(), "idle_frame")

	var mat: ShaderMaterial = flashlight._material
	assert_object(mat).is_not_null()

	var initial_scroll: float = mat.get_shader_param("mask_scroll")
	flashlight._process(0.5)

	var updated_scroll: float = mat.get_shader_param("mask_scroll")
	assert_float(updated_scroll).is_equal_approx(initial_scroll + 1.5, 0.001)


func test_volumetric_cone_shader_backwards_compatibility():
	var shader: Shader = load("res://core_v2/visual/volumetric_cone.shader")
	assert_object(shader).is_not_null()

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_param("use_mask", false)

	assert_bool(mat.get_shader_param("use_mask")).is_false()
