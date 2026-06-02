extends GdUnitTestSuite

const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")

func test_zero_g_logic_6dof() -> void:
	var added_roll_left := false
	var added_roll_right := false
	var added_rotate_left := false
	var added_rotate_right := false
	if not InputMap.has_action("rotate_left"):
		InputMap.add_action("rotate_left")
		added_rotate_left = true
	if not InputMap.has_action("rotate_right"):
		InputMap.add_action("rotate_right")
		added_rotate_right = true
	if not InputMap.has_action("zero_g_roll_left"):
		InputMap.add_action("zero_g_roll_left")
		added_roll_left = true
	if not InputMap.has_action("zero_g_roll_right"):
		InputMap.add_action("zero_g_roll_right")
		added_roll_right = true

	var scene = scene_runner("res://core_v2/tests/TestZeroGravity.tscn")
	var pilot = scene.find_node("Pilot")
	var zgc = pilot.get_node("ZeroGravityController")
	var cm = pilot.get_node("ControllerManager")

	# Force controller if initialization race occurred
	cm.zero_gravity_controller = zgc

	# Disable auto-switching to avoid being forced back to 1G
	cm.auto_switch_from_gravity_world = false
	cm.camera_transition_duration = 0.0

	var standard_basis := Basis(Vector3.UP, PI / 3.0) * Basis(Vector3.RIGHT, 0.25)
	pilot.yaw = PI / 3.0
	pilot.pitch = 0.25
	pilot.get_node("CameraRig").transform.basis = standard_basis

	# Force switch to Zero Gravity
	cm.switch_to(cm.Mode.ZERO_GRAVITY)

	# Wait for switch to settle
	yield(scene.simulate_frames(5), "completed")
	var zero_basis = pilot.get_node("ZeroGCameraRig").transform.basis
	assert_float(zero_basis.x.normalized().dot(standard_basis.x.normalized())).is_greater(0.999)
	assert_float(zero_basis.y.normalized().dot(standard_basis.y.normalized())).is_greater(0.999)
	assert_float(zero_basis.z.normalized().dot(standard_basis.z.normalized())).is_greater(0.999)

	# Test Roll
	var input = InputDataV2.new()
	input.roll_right = true

	var initial_roll = zgc.roll_angle
	zgc.step_zero_g(1.0/60.0, input)

	print("Roll angle after direct step (roll_right=true): ", zgc.roll_angle)
	assert_float(abs(zgc.roll_angle - initial_roll)).is_greater(0.001)
	assert_bool(pilot.get_node("ZeroGCameraRig").visible).is_true()
	assert_bool(pilot.get_node("CameraRig").visible).is_false()
	assert_bool(pilot.get_node("ZeroGCameraRig/SpringArm/Camera").current).is_true()
	assert_bool(pilot.get_node("CameraRig/Yaw/Pitch/OTS_Offset/SpringArm/Camera").current).is_false()
	assert_vector3(pilot.get_node("ZeroGCameraRig").transform.origin).is_equal_approx(
		pilot.get_node("CameraRig").transform.origin,
		Vector3.ONE * 0.001
	)
	assert_float(abs(pilot.get_node("ZeroGCameraRig").transform.basis.x.y)).is_greater(0.001)
	assert_float(abs(pilot.get_node("Visual/Pivot").transform.basis.x.y)).is_less(0.01)

	var zero_g_rig = pilot.get_node("ZeroGCameraRig")
	var lag_anchor = zero_g_rig.transform.origin
	pilot.velocity = Vector3.ZERO
	input = InputDataV2.new()
	input.move_vec = Vector2(0.0, -1.0)
	zgc.step_zero_g(1.0 / 60.0, input)
	var lag_target = pilot.global_transform.xform(lag_anchor)
	assert_float(zero_g_rig.global_transform.origin.distance_to(lag_target)).is_greater(0.001)

	# Test Movement direction
	pilot.global_transform.origin = Vector3(0.0, 0.5, 0.0)
	pilot.yaw = PI / 2.0
	pilot.pitch = 0.0
	pilot.velocity = Vector3.ZERO

	input = InputDataV2.new()
	input.move_vec = Vector2(0, -1.0) # Forward
	zgc.step_zero_g(0.0, input)
	var movement_basis = pilot.get_node("ZeroGCameraRig").global_transform.basis
	var expected_forward = (-movement_basis.z).normalized()
	var expected_right = movement_basis.x.normalized()

	var pos_before = pilot.global_transform.origin

	for i in range(30):
		zgc.step_zero_g(1.0/60.0, input)

	var pos_after = pilot.global_transform.origin
	var delta = pos_after - pos_before
	var move_dir = delta.normalized()

	print("Pos Before: ", pos_before)
	print("Pos After: ", pos_after)
	print("Move Dir: ", move_dir)
	print("Expected Camera Forward: ", expected_forward)

	assert_float(move_dir.dot(expected_forward)).is_greater(0.8)
	var expected_mesh_forward = Vector3(expected_forward.x, 0.0, expected_forward.z).normalized()
	var mesh_basis = pilot.get_node("Visual/Pivot").transform.basis
	assert_float(mesh_basis.z.normalized().dot(expected_mesh_forward)).is_greater(0.8)
	assert_float(abs(mesh_basis.x.y)).is_less(0.01)
	assert_float(abs(mesh_basis.z.y)).is_less(0.01)

	var mesh_basis_after_forward = mesh_basis
	pilot.global_transform.origin = Vector3(0.0, 10.0, 0.0)
	pilot.velocity = Vector3.ZERO
	input = InputDataV2.new()
	input.move_vec = Vector2(1.0, 0.0) # Strafe right should not rotate the mesh.
	for i in range(10):
		zgc.step_zero_g(1.0/60.0, input)
	assert_vector3(pilot.get_node("Visual/Pivot").transform.basis.x).is_equal_approx(mesh_basis_after_forward.x, Vector3.ONE * 0.01)
	assert_vector3(pilot.get_node("Visual/Pivot").transform.basis.y).is_equal_approx(mesh_basis_after_forward.y, Vector3.ONE * 0.01)
	assert_vector3(pilot.get_node("Visual/Pivot").transform.basis.z).is_equal_approx(mesh_basis_after_forward.z, Vector3.ONE * 0.01)

	pilot.global_transform.origin = Vector3(0.0, 10.0, 0.0)
	pilot.velocity = Vector3.ZERO
	input = InputDataV2.new()
	input.move_vec = Vector2(0.0, 1.0) # Back
	pos_before = pilot.global_transform.origin
	for i in range(30):
		zgc.step_zero_g(1.0/60.0, input)
	move_dir = (pilot.global_transform.origin - pos_before).normalized()
	assert_float(move_dir.dot(-expected_forward)).is_greater(0.8)

	pilot.global_transform.origin = Vector3(0.0, 10.0, 0.0)
	pilot.velocity = Vector3.ZERO
	input = InputDataV2.new()
	input.move_vec = Vector2(1.0, 0.0) # Strafe right
	pos_before = pilot.global_transform.origin
	for i in range(30):
		zgc.step_zero_g(1.0/60.0, input)
	move_dir = (pilot.global_transform.origin - pos_before).normalized()
	assert_float(move_dir.dot(expected_right)).is_greater(0.8)

	pilot.global_transform.origin = Vector3(0.0, 10.0, 0.0)
	pilot.velocity = Vector3.ZERO
	input = InputDataV2.new()
	input.move_vec = Vector2(-1.0, 0.0) # Strafe left
	pos_before = pilot.global_transform.origin
	for i in range(30):
		zgc.step_zero_g(1.0/60.0, input)
	move_dir = (pilot.global_transform.origin - pos_before).normalized()
	assert_float(move_dir.dot(-expected_right)).is_greater(0.8)

	# Zero-G keeps full 6DOF orientation; camera local up stays locked to the rig.
	input = InputDataV2.new()
	input.mouse_delta = Vector2(0.0, -100.0)
	pilot.yaw = 0.0
	pilot.pitch = deg2rad(89.0)
	zgc.roll_angle = 0.0
	zgc.step_zero_g(1.0/60.0, input)
	var rig = pilot.get_node("ZeroGCameraRig")
	var cam = rig.find_node("Camera", true, false)
	assert_float(cam.global_transform.basis.y.normalized().dot(rig.global_transform.basis.y.normalized())).is_greater(0.999)
	assert_float(abs(cam.global_transform.basis.y.normalized().dot(Vector3.UP))).is_less(0.99)

	pilot.global_transform.origin = Vector3(0.0, 10.0, 0.0)
	pilot.velocity = Vector3.ZERO
	input = InputDataV2.new()
	input.move_vec = Vector2(0.0, -1.0)
	zgc.step_zero_g(0.0, input)
	expected_forward = (-pilot.get_node("ZeroGCameraRig").global_transform.basis.z).normalized()
	pos_before = pilot.global_transform.origin
	for i in range(30):
		zgc.step_zero_g(1.0/60.0, input)
	move_dir = (pilot.global_transform.origin - pos_before).normalized()
	assert_float(move_dir.dot(expected_forward)).is_greater(0.8)

	# Jump/Crouch thrust follows camera-local up/down, not global Y.
	pilot.global_transform.origin = Vector3(0.0, 10.0, 0.0)
	pilot.yaw = 0.0
	pilot.pitch = deg2rad(90.0)
	zgc.roll_angle = 0.0
	pilot.velocity = Vector3.ZERO
	input = InputDataV2.new()
	zgc.step_zero_g(0.0, input)
	var expected_up = pilot.get_node("ZeroGCameraRig").global_transform.basis.y.normalized()
	input.jump = true
	zgc.step_zero_g(1.0/60.0, input)
	assert_float(pilot.velocity.normalized().dot(expected_up)).is_greater(0.8)

	# Digital diagonal input should not accelerate faster than cardinal input.
	pilot.global_transform.origin = Vector3(0.0, 10.0, 0.0)
	pilot.yaw = 0.0
	pilot.pitch = 0.0
	pilot.velocity = Vector3.ZERO
	input = InputDataV2.new()
	input.move_vec = Vector2(0.0, -1.0)
	zgc.step_zero_g(1.0/60.0, input)
	var forward_speed = pilot.velocity.length()

	pilot.global_transform.origin = Vector3(0.0, 10.0, 0.0)
	pilot.velocity = Vector3.ZERO
	input = InputDataV2.new()
	input.move_vec = Vector2(1.0, -1.0)
	zgc.step_zero_g(1.0/60.0, input)
	var diagonal_speed = pilot.velocity.length()
	assert_float(diagonal_speed).is_equal_approx(forward_speed, 0.001)

	cm.switch_to(cm.Mode.STANDARD_1G)
	assert_bool(pilot.get_node("CameraRig").visible).is_true()
	assert_bool(pilot.get_node("ZeroGCameraRig").visible).is_false()
	assert_object(pilot.camera_rig).is_same(pilot.get_node("CameraRig"))
	assert_float(abs(pilot.get_node("CameraRig").transform.basis.x.y)).is_less(0.01)
	assert_vector3(pilot.get_node("Visual/Pivot").transform.origin).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.01)
	assert_vector3(pilot.get_node("Visual/Pivot").transform.basis.x).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 0.01)
	assert_vector3(pilot.get_node("Visual/Pivot").transform.basis.y).is_equal_approx(Vector3.UP, Vector3.ONE * 0.01)
	assert_vector3(pilot.get_node("Visual/Pivot").transform.basis.z).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.01)

	scene.free()
	if added_roll_left:
		InputMap.erase_action("zero_g_roll_left")
	if added_roll_right:
		InputMap.erase_action("zero_g_roll_right")
	if added_rotate_left:
		InputMap.erase_action("rotate_left")
	if added_rotate_right:
		InputMap.erase_action("rotate_right")
