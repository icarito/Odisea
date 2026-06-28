extends GdUnitTestSuite

# Tests for CargolDroneV2 determinism fixes (issues #200 and #201).
# Updated for AgentBase refactor.

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

		# Pickup zeroes residual momentum and switches the body to kinematic mode.
		assert_int(cargo.mode).is_equal(RigidBody.MODE_KINEMATIC)
		assert_bool(cargo.linear_velocity == Vector3.ZERO).is_true()

		yield(runner.simulate_frames(2), "completed")

		# Release with zero impulse; only _canonical_velocity contributes.
		drone.release(Vector3.ZERO)
		yield(runner.simulate_frames(2), "completed")

		var speed = cargo.linear_velocity.length()
		# Magnitude should be consistent with 3 m/s, not 99 m/s.
		assert_bool(speed < 50.0).is_true()

func test_snapshot_restore_determinism() -> void:
	var runner := scene_runner("res://core_v2/tests/TestScene_Cargol.tscn")
	yield(runner.simulate_frames(3), "completed")

	var drone = runner.scene().find_node("CargolDrone", true, false)
	
	drone.velocity = Vector3(1, 2, 3)
	drone.current_state = 2 # State.FOLLOW_TARGET
	
	var snapshot = drone.get_snapshot()
	
	drone.velocity = Vector3.ZERO
	drone.current_state = 0 # State.IDLE
	
	drone.restore_snapshot(snapshot)
	
	assert_int(drone.current_state).is_equal(2)
	assert_bool(drone.velocity.is_equal_approx(Vector3(1, 2, 3))).is_true()
