extends GdUnitTestSuite

const GravityModes = preload("res://core_v2/systems/GravityModes.gd")
const GravityWorldScript = preload("res://core_v2/systems/GravityWorld.gd")
const ControllerManagerScript = preload("res://core_v2/player/ControllerManager.gd")

class DummyZone extends Spatial:
	var mode := 2
	var gravity_priority := 10
	var radius := 5.0
	var allow_coriolis := true
	var affect_props := true

	func contains_global_point(global_position: Vector3) -> bool:
		return global_transform.origin.distance_to(global_position) <= radius

	func get_gravity_mode() -> int:
		return mode

	func get_gravity_priority() -> int:
		return gravity_priority

	func get_volume() -> float:
		return radius * radius * radius

func test_gravity_mode_values_are_stable() -> void:
	assert_int(GravityModes.Mode.STANDARD_1G).is_equal(0)
	assert_int(GravityModes.Mode.SPIN_WALKABLE).is_equal(1)
	assert_int(GravityModes.Mode.ZERO_G).is_equal(2)
	assert_int(GravityModes.Mode.SPIN_DYNAMIC).is_equal(3)
	assert_str(GravityModes.mode_name(GravityModes.Mode.ZERO_G)).is_equal("ZERO_G")
	assert_bool(GravityModes.is_walkable(GravityModes.Mode.SPIN_WALKABLE)).is_true()
	assert_bool(GravityModes.is_spin(GravityModes.Mode.SPIN_DYNAMIC)).is_true()

func test_gravity_world_resolves_zone_mode_over_default() -> void:
	var manager = auto_free(GravityWorldScript.new())
	add_child(manager)

	var zone = DummyZone.new()
	zone.mode = GravityModes.Mode.ZERO_G
	manager.add_child(zone)
	manager.register_zone(zone)

	assert_int(manager.get_gravity_mode_at(Vector3.ZERO)).is_equal(GravityModes.Mode.ZERO_G)
	assert_bool(manager.should_use_zero_g_controller(Vector3.ZERO)).is_true()
	assert_int(manager.get_gravity_mode_at(Vector3(20.0, 0.0, 0.0))).is_equal(GravityModes.Mode.STANDARD_1G)

func test_gravity_world_blend_keeps_fd036_radial_gravity() -> void:
	var manager = auto_free(GravityWorldScript.new())
	add_child(manager)
	manager.one_g_strength = 9.81
	manager.set_ship_axis(Vector3.ZERO, Vector3.UP)
	manager.set_centrifugal_reference_radius(10.0)
	manager.set_ship_angular_velocity(0.0)
	manager.set_gravity_blend(1.0)

	var gravity: Vector3 = manager.get_canonical_gravity(Vector3(10.0, 2.0, 0.0))
	assert_int(manager.get_current_gravity_mode()).is_equal(GravityModes.Mode.SPIN_WALKABLE)
	assert_float(gravity.normalized().dot(Vector3.RIGHT)).is_greater_equal(0.999)
	assert_float(gravity.length()).is_equal_approx(9.81, 0.001)

func test_dynamic_gravity_payload_reports_zone_flags() -> void:
	var manager = auto_free(GravityWorldScript.new())
	add_child(manager)

	var zone = DummyZone.new()
	zone.mode = GravityModes.Mode.SPIN_DYNAMIC
	manager.add_child(zone)
	manager.register_zone(zone)

	var body = Spatial.new()
	body.translation = Vector3(2.0, 0.0, 0.0)
	manager.add_child(body)

	var payload: Dictionary = manager.get_dynamic_gravity_for_body(body)
	assert_int(payload["mode"]).is_equal(GravityModes.Mode.SPIN_DYNAMIC)
	assert_str(payload["mode_name"]).is_equal("SPIN_DYNAMIC")
	assert_bool(payload["allow_coriolis"]).is_true()
	assert_bool(payload["affect_props"]).is_true()
	assert_bool(payload.has("gravity")).is_true()
	assert_float((payload["gravity"] as Vector3).normalized().dot(Vector3.RIGHT)).is_greater_equal(0.999)

func test_controller_manager_maps_gravity_modes_to_controller_modes() -> void:
	var manager = auto_free(ControllerManagerScript.new())

	assert_int(manager.get_controller_mode_for_gravity_mode(GravityModes.Mode.ZERO_G)).is_equal(manager.Mode.ZERO_GRAVITY)
	assert_int(manager.get_controller_mode_for_gravity_mode(GravityModes.Mode.STANDARD_1G)).is_equal(manager.Mode.STANDARD_1G)
	assert_int(manager.get_controller_mode_for_gravity_mode(GravityModes.Mode.SPIN_WALKABLE)).is_equal(manager.Mode.STANDARD_1G)
	assert_int(manager.get_controller_mode_for_gravity_mode(GravityModes.Mode.SPIN_DYNAMIC)).is_equal(manager.Mode.STANDARD_1G)
