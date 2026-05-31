extends GdUnitTestSuite

const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")

func test_zero_g_logic_6dof() -> void:
	var scene = scene_runner("res://core_v2/tests/TestZeroGravity.tscn")
	var pilot = scene.find_node("Pilot")
	var zgc = pilot.get_node("ZeroGravityController")
	var cm = pilot.get_node("ControllerManager")

	# Force controller if initialization race occurred
	cm.zero_gravity_controller = zgc

	# Disable auto-switching to avoid being forced back to 1G
	cm.auto_switch_from_gravity_world = false

	# Force switch to Zero Gravity
	cm.switch_to(cm.Mode.ZERO_GRAVITY)

	# Wait for switch to settle
	yield(scene.simulate_frames(5), "completed")

	# Test Roll
	var input = InputDataV2.new()
	input.roll_right = true # Clockwise looking forward -> Positive roll_angle

	var initial_roll = zgc.roll_angle
	zgc.step_zero_g(1.0/60.0, input)

	print("Roll angle after direct step (roll_right=true): ", zgc.roll_angle)
	assert_float(zgc.roll_angle).is_greater(initial_roll)

	# Test Movement direction
	pilot.yaw = PI / 2.0
	pilot.pitch = 0.0
	pilot.velocity = Vector3.ZERO

	input = InputDataV2.new()
	input.move_vec = Vector2(0, -1.0) # Forward

	var pos_before = pilot.global_transform.origin

	for i in range(30):
		zgc.step_zero_g(1.0/60.0, input)

	var pos_after = pilot.global_transform.origin
	var delta = pos_after - pos_before
	var move_dir = delta.normalized()

	print("Pos Before: ", pos_before)
	print("Pos After: ", pos_after)
	print("Move Dir: ", move_dir)

	# 90 deg yaw -> Forward is -X
	assert_float(move_dir.x).is_less(-0.8)
	assert_float(abs(move_dir.z)).is_less(0.2)

	scene.free()
