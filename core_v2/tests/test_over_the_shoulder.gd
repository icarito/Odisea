extends GdUnitTestSuite

const OverTheShoulderScript = preload("res://core_v2/player/OverTheShoulder.gd")


class DummyPlayer:
	extends KinematicBody

	var velocity := Vector3.ZERO
	var current_spring_length := 5.0
	var _on_floor := false

	func is_on_floor() -> bool:
		return _on_floor


class DummyArm:
	extends Spatial

	var current_length := 5.0
	var target_length := 5.0
	var spring_length := 5.0
	var zoom_out_blocked := false
	var camera_local_offset := Vector3.ZERO

	func set_camera_local_offset(offset: Vector3) -> void:
		camera_local_offset = offset

	func has_active_collision() -> bool:
		return zoom_out_blocked or current_length < target_length - 0.02

	func is_zoom_out_blocked() -> bool:
		return zoom_out_blocked


func _setup_root() -> Node:
	var root := Node.new()
	root.name = "OverTheShoulderTestRoot"
	get_tree().root.add_child(root)
	return root


func _teardown_root(root: Node) -> void:
	if root and is_instance_valid(root):
		root.queue_free()
	yield(get_tree(), "idle_frame")


func _build_rig(root: Node) -> Dictionary:
	var player := DummyPlayer.new()
	player.name = "Pilot"
	root.add_child(player)

	var logic := Node.new()
	logic.name = "Logic"
	player.add_child(logic)

	var camera_rig := Spatial.new()
	camera_rig.name = "CameraRig"
	player.add_child(camera_rig)

	var yaw := Spatial.new()
	yaw.name = "Yaw"
	camera_rig.add_child(yaw)

	var pitch := Spatial.new()
	pitch.name = "Pitch"
	yaw.add_child(pitch)

	var spring_arm := DummyArm.new()
	spring_arm.name = "SpringArm"
	pitch.add_child(spring_arm)

	var camera := Camera.new()
	camera.name = "Camera"
	spring_arm.add_child(camera)

	var ots := OverTheShoulderScript.new()
	ots.name = "OverTheShoulder"
	logic.add_child(ots)

	yield(get_tree(), "idle_frame")

	return {
		"player": player,
		"arm": spring_arm,
		"ots": ots,
	}


func test_shortened_zoom_uses_same_shoulder_curve_without_extra_vertical_drop() -> void:
	var root := _setup_root()
	var rig: Dictionary = yield(_build_rig(root), "completed")
	var player: DummyPlayer = rig["player"]
	var arm: DummyArm = rig["arm"]
	var ots = rig["ots"]

	ots.max_side_offset = 2.0
	ots.max_height_offset = -2.5
	ots.max_pivot_z_offset = 0.2
	ots.ots_blend_min_distance = 0.0
	ots.ots_blend_max_distance = 4.5
	ots.right_side = false
	ots.lerp_speed = 100.0
	ots.distance_blend_speed = 100.0
	ots.centering_in_speed = 100.0
	ots.proximity_clamp_in_speed = 100.0
	ots.jump_compensation_speed = 100.0

	player.velocity = Vector3.ZERO
	player._on_floor = false
	arm.current_length = 1.0
	arm.target_length = 5.0
	arm.spring_length = 5.0
	arm.zoom_out_blocked = true

	ots._physics_process(1.0)

	var expected_distance_weight := pow(1.0 - (1.0 / 4.5), ots.curve_power)
	var expected_proximity_scale: float = ots.proximity_clamp_floor

	assert_float(abs(arm.camera_local_offset.x)).is_less(0.001)
	assert_float(arm.camera_local_offset.y).is_less(0.0)
	assert_float(arm.camera_local_offset.y).is_greater(-2.5)
	assert_float(arm.camera_local_offset.z).is_equal_approx(0.2 * expected_distance_weight * expected_proximity_scale, 0.0001)

	yield(_teardown_root(root), "completed")


func test_open_space_preserves_regular_negative_shoulder_drop() -> void:
	var root := _setup_root()
	var rig: Dictionary = yield(_build_rig(root), "completed")
	var arm: DummyArm = rig["arm"]
	var ots = rig["ots"]

	ots.max_side_offset = 1.2
	ots.max_height_offset = -0.5
	ots.max_pivot_z_offset = 0.3
	ots.ots_blend_min_distance = 0.0
	ots.ots_blend_max_distance = 4.0
	ots.right_side = true
	ots.lerp_speed = 100.0
	ots.distance_blend_speed = 100.0

	arm.current_length = 0.0
	arm.target_length = 0.0
	arm.spring_length = 0.0
	arm.zoom_out_blocked = false

	ots._physics_process(1.0)

	assert_float(arm.camera_local_offset.x).is_equal_approx(1.2, 0.0001)
	assert_float(arm.camera_local_offset.y).is_equal_approx(-0.5, 0.0001)
	assert_float(arm.camera_local_offset.z).is_equal_approx(0.3, 0.0001)

	yield(_teardown_root(root), "completed")


func test_manual_zoom_range_reaches_full_shoulder_offset() -> void:
	var root := _setup_root()
	var rig: Dictionary = yield(_build_rig(root), "completed")
	var arm: DummyArm = rig["arm"]
	var ots = rig["ots"]

	ots.max_side_offset = 0.55
	ots.max_height_offset = -0.35
	ots.max_pivot_z_offset = 0.2
	ots.ots_blend_min_distance = 1.0
	ots.ots_blend_max_distance = 3.2
	ots.right_side = true
	ots.lerp_speed = 100.0
	ots.distance_blend_speed = 100.0

	arm.current_length = 1.0
	arm.target_length = 1.0
	arm.spring_length = 1.0
	arm.zoom_out_blocked = false

	ots._physics_process(1.0)

	assert_float(arm.camera_local_offset.x).is_equal_approx(0.55, 0.0001)
	assert_float(arm.camera_local_offset.y).is_equal_approx(-0.35, 0.0001)
	assert_float(arm.camera_local_offset.z).is_equal_approx(0.2, 0.0001)

	yield(_teardown_root(root), "completed")
