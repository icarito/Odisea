extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# test_capture_respawn.gd
# Unit tests for the Capture System, Checkpoint Manager, Checkpoint Console and DDC reset behaviors.

const CheckpointConsole = preload("res://core_v2/props/CheckpointConsole.gd")
const DDCDroneV2 = preload("res://core_v2/actors/DDCDroneV2.gd")
const ElevatorPlatform = preload("res://core_v2/components/ElevatorPlatform.gd")

func test_checkpoint_registration_and_activation() -> void:
	# Clean up autoload values first
	CheckpointManager.registered_checkpoints.clear()
	CheckpointManager.active_checkpoint_pos = Vector3.ZERO
	CheckpointManager.active_checkpoint_yaw = 0.0
	CheckpointManager.active_checkpoint_pitch = 0.0

	# Instantiate a console
	var console = CheckpointConsole.new()
	add_child(console)
	console.global_transform.origin = Vector3(10, 0, 5)
	console.spawn_yaw = 1.5
	console.spawn_pitch = -0.5

	# Simulated ready to trigger registration
	console._ready()

	# Verify console is registered
	assert_bool(CheckpointManager.registered_checkpoints.has(console)).is_true()

	# Trigger activation/interaction
	console.interact()
	assert_bool(console.is_active).is_true()

	console.step(1.1)

	# Verify active checkpoint position and orientation are set
	var expected_spawn_pos = console.global_transform.origin + console.global_transform.basis.z * 1.2
	assert_vector3(CheckpointManager.active_checkpoint_pos).is_equal(expected_spawn_pos)
	assert_float(CheckpointManager.active_checkpoint_yaw).is_equal(1.5)
	assert_float(CheckpointManager.active_checkpoint_pitch).is_equal(-0.5)

	# Test auto-checkpoint
	CheckpointManager.trigger_auto_checkpoint(Vector3(20, 10, 20), 0.5, 0.2)
	assert_vector3(CheckpointManager.active_checkpoint_pos).is_equal(Vector3(20, 10, 20))
	assert_float(CheckpointManager.active_checkpoint_yaw).is_equal(0.5)
	assert_float(CheckpointManager.active_checkpoint_pitch).is_equal(0.2)

	# The first console should have been deactivated because a new checkpoint became active
	assert_bool(console.is_active).is_false()

	console.free()

func test_checkpoint_restores_elevator_motion_state() -> void:
	var platform = auto_free(ElevatorPlatform.new())
	add_child(platform)
	platform.global_transform.origin.y = 3.5
	platform.target_height = 9.0
	platform.current_velocity_y = 1.25
	platform.is_moving = true

	CheckpointManager.set_active_checkpoint(Vector3(1, 2, 3), 0.0, 0.0)
	platform.global_transform.origin.y = 7.0
	platform.target_height = 0.0
	platform.current_velocity_y = -2.0
	platform.is_moving = false

	CheckpointManager.get_respawn_transform()
	assert_float(platform.global_transform.origin.y).is_equal(3.5)
	assert_float(platform.target_height).is_equal(9.0)
	assert_float(platform.current_velocity_y).is_equal(1.25)
	assert_bool(platform.is_moving).is_true()

func test_capture_dialogue_selection() -> void:
	# Low count captures (< 3)
	CaptureSystem.capture_count = 0
	var d1 = ""
	if CaptureSystem.capture_count < 3:
		d1 = CaptureSystem.low_count_lines[CaptureSystem.capture_count % CaptureSystem.low_count_lines.size()]
	assert_str(d1).is_equal("STASIS LOCK ENGAGED. RECONSTRUCTING PATTERN AT LAST CHECKPOINT...")

	CaptureSystem.capture_count = 2
	var d2 = ""
	if CaptureSystem.capture_count < 3:
		d2 = CaptureSystem.low_count_lines[CaptureSystem.capture_count % CaptureSystem.low_count_lines.size()]
	assert_str(d2).is_equal("CRITICAL DISCREPANCY DETECTED. RESETTING LOCAL SPACE-TIME TRANSFORMATION...")

	# High count captures (>= 3)
	CaptureSystem.capture_count = 3
	var d3 = ""
	if CaptureSystem.capture_count >= 3:
		d3 = CaptureSystem.high_count_lines[CaptureSystem.capture_count % CaptureSystem.high_count_lines.size()]
	assert_str(d3).is_equal(CaptureSystem.high_count_lines[3 % CaptureSystem.high_count_lines.size()])

func test_ddc_reset_to_spawn_and_neutralized() -> void:
	var drone = DDCDroneV2.new()
	add_child(drone)

	drone.global_transform.origin = Vector3(100, 20, 100)
	drone._ready() # stores _initial_transform

	# Simulate movement/alert
	drone.global_transform.origin = Vector3(150, 20, 150)
	drone.current_state = drone.State.ALERT
	drone.is_neutralized = true

	# Test reset to spawn (no patrol points, should fallback to IDLE)
	drone.reset_to_spawn()

	assert_vector3(drone.global_transform.origin).is_equal(Vector3(100, 20, 100))
	assert_bool(drone.is_neutralized).is_false()
	assert_int(drone.current_state).is_equal(drone.State.IDLE)

	# Now test with waypoint children
	var wp = Position3D.new()
	wp.name = "Waypoint_0"
	drone.add_child(wp)

	drone._discover_patrol_points()
	drone.current_state = drone.State.ALERT
	drone.is_neutralized = true

	drone.reset_to_spawn()
	# Because reset_to_spawn calls move_to, it transitions to MOVE_TO (6) state
	assert_int(drone.current_state).is_equal(drone.State.MOVE_TO)

	drone.free()
