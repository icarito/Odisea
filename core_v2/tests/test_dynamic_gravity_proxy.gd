extends GdUnitTestSuite

const GravityModes = preload("res://core_v2/systems/GravityModes.gd")
const DynamicGravityProxyScript = preload("res://core_v2/systems/DynamicGravityProxy.gd")

func test_radial_gravity_points_outward_from_axis() -> void:
	var proxy = auto_free(DynamicGravityProxyScript.new())
	add_child(proxy)
	proxy.axis_origin = Vector3.ZERO
	proxy.axis_direction = Vector3.UP
	proxy.gravity_strength = 4.0

	var accel: Vector3 = proxy.calculate_acceleration_at(
			Vector3(10.0, 3.0, 0.0),
			Vector3.ZERO,
			GravityModes.Mode.SPIN_DYNAMIC)

	assert_float(accel.normalized().dot(Vector3.RIGHT)).is_greater_equal(0.999)
	assert_float(accel.length()).is_equal_approx(4.0, 0.001)

func test_proxy_does_not_affect_standard_1g_when_spin_only() -> void:
	var proxy = auto_free(DynamicGravityProxyScript.new())
	add_child(proxy)
	proxy.affect_only_spin_modes = true

	var accel: Vector3 = proxy.calculate_acceleration_at(
			Vector3(10.0, 0.0, 0.0),
			Vector3.ZERO,
			GravityModes.Mode.STANDARD_1G)

	assert_float(accel.length()).is_equal_approx(0.0, 0.001)

func test_coriolis_is_optional_and_clamped() -> void:
	var proxy = auto_free(DynamicGravityProxyScript.new())
	add_child(proxy)
	proxy.use_radial = false
	proxy.gravity_strength = 0.0
	proxy.use_coriolis = true
	proxy.angular_velocity_rad_s = 2.0
	proxy.coriolis_scale = 1.0
	proxy.coriolis_max_accel = 3.0

	var accel: Vector3 = proxy.calculate_acceleration_at(
			Vector3(10.0, 0.0, 0.0),
			Vector3.RIGHT * 10.0,
			GravityModes.Mode.SPIN_DYNAMIC)

	assert_float(accel.length()).is_equal_approx(3.0, 0.001)

func test_sleep_when_far_disables_effect() -> void:
	var root: Spatial = auto_free(Spatial.new())
	add_child(root)

	var body := Spatial.new()
	body.name = "Body"
	body.translation = Vector3(100.0, 0.0, 0.0)
	root.add_child(body)

	var reference := Spatial.new()
	reference.name = "Reference"
	reference.translation = Vector3.ZERO
	root.add_child(reference)

	var proxy = DynamicGravityProxyScript.new()
	proxy.max_effect_distance = 5.0
	body.add_child(proxy)
	proxy.reference_body_path = proxy.get_path_to(reference)

	assert_bool(proxy.is_effect_active()).is_false()
