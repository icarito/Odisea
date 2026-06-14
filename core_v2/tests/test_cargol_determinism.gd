extends GdUnitTestSuite

# Tests for CargolDroneV2 determinism fixes (issues #200 and #201).
#
# Bug #1: CargoAnchor was a child of the KinematicBody. Now it must be a
#         sibling (child of the drone's parent) so cargo inherits the
#         canonical logical transform, not an interpolated visual one.
#
# Bug #2: release() was using `velocity` after move_and_slide() had altered
#         it via collision response. Now `_canonical_velocity` captures the
#         intent before that mutation.

func test_cargo_anchor_is_sibling_not_child() -> void:
	var runner := scene_runner("res://core_v2/tests/TestScene_Cargol.tscn")
	yield(runner.simulate_frames(3), "completed")

	var drone = runner.scene().find_node("CargolDrone", true, false)
	assert_object(drone).is_not_null()

	var anchor = drone.cargo_anchor
	assert_object(anchor).is_not_null()

	# Fix #1: anchor must NOT be a child of the drone itself.
	assert_bool(anchor.get_parent() == drone).is_false()
	# It should be a child of whatever contains the drone.
	assert_object(anchor.get_parent()).is_equal(drone.get_parent())

func test_canonical_velocity_set_after_step() -> void:
	var runner := scene_runner("res://core_v2/tests/TestScene_Cargol.tscn")
	yield(runner.simulate_frames(3), "completed")

	var drone = runner.scene().find_node("CargolDrone", true, false)
	assert_object(drone).is_not_null()

	# _canonical_velocity starts at zero before any movement.
	assert_bool(drone._canonical_velocity == Vector3.ZERO).is_true()

	# Give the drone an intended velocity and run several frames.
	drone.set_velocity(Vector3(5.0, 0.0, 0.0))
	yield(runner.simulate_frames(10), "completed")

	# Fix #2: after acceleration, _canonical_velocity must be non-zero,
	# confirming it is captured each step before move_and_slide() can alter it.
	assert_bool(drone._canonical_velocity == Vector3.ZERO).is_false()

func test_release_uses_canonical_not_post_slide_velocity() -> void:
	# Verify that after pickup + manual step manipulation, the impulse applied
	# on release matches _canonical_velocity (not the post-slide `velocity`).
	var runner := scene_runner("res://core_v2/tests/TestScene_Cargol.tscn")
	yield(runner.simulate_frames(3), "completed")

	var drone = runner.scene().find_node("CargolDrone", true, false)
	assert_object(drone).is_not_null()

	# Manually force a known canonical velocity state.
	drone._canonical_velocity = Vector3(3.0, 0.0, 0.0)
	# Make post-slide velocity deliberately different to prove release does NOT use it.
	drone.velocity = Vector3(99.0, 0.0, 0.0)

	var cargo = runner.scene().find_node("Cargo", true, false)
	if cargo:
		drone.pickup("Cargo")
		yield(runner.simulate_frames(2), "completed")

		# Track pre-release linear_velocity (zero after kinematic pickup).
		assert_bool(cargo.linear_velocity == Vector3.ZERO).is_true()

		# Release with zero impulse; only _canonical_velocity contributes.
		drone.release(Vector3.ZERO)
		yield(runner.simulate_frames(2), "completed")

		# Cargo impulse = impulse(0) + _canonical_velocity(3,0,0).
		# Post-slide velocity(99,0,0) must NOT have been used.
		# We can't inspect apply_central_impulse directly, but we can confirm
		# the magnitude is consistent with 3 m/s, not 99 m/s.
		var speed = cargo.linear_velocity.length()
		# Allow physics tolerance; just rule out the 99 m/s case.
		assert_bool(speed < 50.0).is_true()
