extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# test_ddc_pursuit.gd
# Unit tests for the DDC Containment kinetic pursuit drone.

const DDCContainment = preload("res://core_v2/actors/DDCContainmentV1.gd")

var _player_contained_signal_emitted := false

func _on_player_contained_signal() -> void:
	_player_contained_signal_emitted = true

func _create_mock_player_with_velocity() -> KinematicBody:
	var player = KinematicBody.new()
	var script = GDScript.new()
	script.source_code = "extends KinematicBody\nvar velocity := Vector3.ZERO"
	script.reload()
	player.set_script(script)
	return player

func test_initial_state_and_speed_scaling() -> void:
	var drone = DDCContainment.new()
	add_child(drone)
	
	# Verify initial state is CHARGING (which corresponds to ContainmentState.CHARGING = 0)
	assert_int(drone.state).is_equal(0)
	assert_float(drone.state_timer).is_equal(0.0)
	
	# Create a mock player
	var player = _create_mock_player_with_velocity()
	player.add_to_group("player")
	add_child(player)
	player.translation = Vector3(10, 0, 0)
	
	# Hook player reference
	drone._player_ref = player
	
	# Check wish velocity calculation at t = 0
	# (starts at speed 0, ramping up to charging_speed)
	var v_initial = drone._calculate_wish_velocity(0.1)
	assert_float(v_initial.length()).is_between(-0.1, 0.1)
	
	# Advance state_timer manually and check speed halfway through CHARGING phase
	drone.state_timer = drone.charging_duration * 0.5
	var v_mid = drone._calculate_wish_velocity(0.1)
	var half_speed = drone.charging_speed * 0.5
	assert_float(v_mid.length()).is_between(half_speed - 0.2, half_speed + 0.2)
	
	# Advance past charging_duration in step() -> should transition to INTERCEPT (1)
	drone.step(drone.charging_duration + 0.1)
	assert_int(drone.state).is_equal(1) # INTERCEPT
	
	# Under INTERCEPT speed should be intercept_speed
	var v_intercept = drone._calculate_wish_velocity(0.1)
	assert_float(v_intercept.length()).is_between(drone.intercept_speed - 0.1, drone.intercept_speed + 0.1)
	
	# Cleanup
	drone.free()
	player.free()

func test_trajectory_prediction_intercept() -> void:
	var drone = DDCContainment.new()
	add_child(drone)
	
	var player = _create_mock_player_with_velocity()
	player.add_to_group("player")
	add_child(player)
	
	# Player is straight ahead of drone (-Z)
	player.translation = Vector3(0, drone.flight_height, -10.0)
	
	# Set player velocity moving right (+X)
	player.set("velocity", Vector3(10, 0, 0))
	
	drone._player_ref = player
	drone.set_containment_state(1) # Force INTERCEPT
	
	# Target position in INTERCEPT should be predicted player position (which is offset to the right +X)
	var _v_pred = drone._calculate_wish_velocity(0.1)
	
	# Check that the drone turned to the right (+X) because of the prediction!
	var forward = -drone.global_transform.basis.z
	assert_float(forward.x).is_greater(0.0) # Turned towards predicted right side
	
	drone.free()
	player.free()

func test_turn_rate_limit() -> void:
	var drone = DDCContainment.new()
	add_child(drone)
	
	var player = _create_mock_player_with_velocity()
	player.add_to_group("player")
	add_child(player)
	# Player is directly behind the drone (+Z)
	player.translation = Vector3(0, drone.flight_height, 10.0)
	
	drone._player_ref = player
	drone.turn_rate = 1.0 # 1.0 rad/s
	drone.set_containment_state(1) # Force INTERCEPT
	
	# Step with dt = 0.5s -> should turn exactly turn_rate * dt = 0.5 rad
	var _v = drone._calculate_wish_velocity(0.5)
	
	var forward = -drone.global_transform.basis.z
	var angle_turned = Vector3.FORWARD.angle_to(forward)
	assert_float(angle_turned).is_between(0.5 - 0.05, 0.5 + 0.05)
	
	drone.free()
	player.free()

func test_stun_and_recovery() -> void:
	var drone = DDCContainment.new()
	add_child(drone)
	
	var player = _create_mock_player_with_velocity()
	player.add_to_group("player")
	add_child(player)
	player.translation = Vector3(5, 0, 0)
	drone._player_ref = player
	
	# Stun drone for 2.0s
	drone.stun(2.0)
	assert_int(drone.state).is_equal(2) # STUNNED
	
	# Verify wish velocity is zero under STUNNED state
	var v_stun = drone._calculate_wish_velocity(0.1)
	assert_vector3(v_stun).is_equal(Vector3.ZERO)
	
	# Step by 1.0s -> should still be STUNNED
	drone.step(1.0)
	assert_int(drone.state).is_equal(2) # STUNNED
	
	# Step by another 1.1s -> exceeds stun_duration -> recovery back to CHARGING (0)
	drone.step(1.1)
	assert_int(drone.state).is_equal(0) # CHARGING
	
	drone.free()
	player.free()

func test_player_contained_signal_and_containment() -> void:
	var drone = DDCContainment.new()
	add_child(drone)
	
	var player = _create_mock_player_with_velocity()
	player.add_to_group("player")
	add_child(player)
	
	drone._player_ref = player
	
	# Monitor signal emission
	_player_contained_signal_emitted = false
	drone.connect("player_contained", self, "_on_player_contained_signal")
	
	# Place player within capture distance (e.g. 0.5m)
	player.translation = Vector3(0.5, 0, 0)
	drone.translation = Vector3.ZERO
	drone.player_capture_distance = 1.0
	
	# Trigger step -> contact made -> transition to CONTAINING (3)
	drone.step(0.1)
	assert_int(drone.state).is_equal(3) # CONTAINING
	
	# Verify signal is emitted
	assert_bool(_player_contained_signal_emitted).is_true()
	
	drone.free()
	player.free()

func test_deterministic_snapshots() -> void:
	var drone = DDCContainment.new()
	add_child(drone)
	
	drone.state = 1 # INTERCEPT
	drone.state_timer = 2.34
	drone.stun_duration = 4.5
	drone.translation = Vector3(12, 34, 56)
	
	var snapshot = drone.get_snapshot()
	
	# Reset drone values
	drone.state = 0
	drone.state_timer = 0.0
	drone.stun_duration = 0.0
	drone.translation = Vector3.ZERO
	
	# Restore snapshot
	drone.restore_snapshot(snapshot)
	
	# Verify restored values
	assert_int(drone.state).is_equal(1)
	assert_float(drone.state_timer).is_between(2.34 - 0.001, 2.34 + 0.001)
	assert_float(drone.stun_duration).is_between(4.5 - 0.001, 4.5 + 0.001)
	assert_vector3(drone.global_transform.origin).is_equal(Vector3(12, 34, 56))
	
	drone.free()
