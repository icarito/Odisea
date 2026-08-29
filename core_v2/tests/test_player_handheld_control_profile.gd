extends GdUnitTestSuite

const PlayerControllerScript = preload("res://core_v2/player/PlayerControllerV2.gd")


class DummyPivot:
	extends Spatial

	func step_animator(_dt: float, _velocity: Vector3) -> void:
		pass

	func play_override_animation(_anim_name: String) -> void:
		pass


class DummySpringArm:
	extends SpringArm

	var zoom_out_blocked := false

	func is_zoom_out_blocked() -> bool:
		return zoom_out_blocked


func _free_node(node: Node) -> void:
	if node and is_instance_valid(node):
		node.queue_free()
	yield (get_tree(), "idle_frame")


func _build_player() -> KinematicBody:
	var player := KinematicBody.new()
	player.name = "Pilot"

	var camera_rig := Spatial.new()
	camera_rig.name = "CameraRig"
	player.add_child(camera_rig)

	var yaw := Spatial.new()
	yaw.name = "Yaw"
	camera_rig.add_child(yaw)

	var pitch := Spatial.new()
	pitch.name = "Pitch"
	yaw.add_child(pitch)

	var spring_arm := DummySpringArm.new()
	spring_arm.name = "SpringArm"
	pitch.add_child(spring_arm)

	var camera := Camera.new()
	camera.name = "Camera"
	spring_arm.add_child(camera)

	var visual := Spatial.new()
	visual.name = "Visual"
	player.add_child(visual)

	var pivot := DummyPivot.new()
	pivot.name = "Pivot"
	visual.add_child(pivot)

	var collision := CollisionShape.new()
	collision.name = "CollisionShape"
	var capsule := CapsuleShape.new()
	capsule.radius = 0.35
	capsule.height = 1.2
	collision.shape = capsule
	collision.transform.origin = Vector3(0, 1.0, 0)
	player.add_child(collision)

	player.set_script(PlayerControllerScript)
	return player


# With HardwareProfile removed, these methods always return false (safe defaults).

func test_auto_align_defaults_to_enabled() -> void:
	var root := Node.new()
	root.name = "PlayerHandheldControlProfileRoot"
	get_tree().root.add_child(root)

	var player = _build_player()
	root.add_child(player)
	yield (get_tree(), "idle_frame")

	assert_bool(player._should_disable_auto_align_for_profile()).is_false()
	assert_bool(player._should_throttle_animator_for_profile()).is_false()

	yield (_free_node(root), "completed")


func test_cinematic_zone_scan_stays_enabled() -> void:
	var root := Node.new()
	root.name = "PlayerHandheldCameraZoneRoot"
	get_tree().root.add_child(root)

	var player = _build_player()
	root.add_child(player)
	yield (get_tree(), "idle_frame")

	assert_bool(player._perf_disable_cinematic_zone_scan).is_false()

	yield (_free_node(root), "completed")


func test_step_up_stays_enabled() -> void:
	var root := Node.new()
	root.name = "PlayerHandheldStepUpRoot"
	get_tree().root.add_child(root)

	var player = _build_player()
	root.add_child(player)
	yield (get_tree(), "idle_frame")

	assert_bool(player.enable_step_up).is_true()

	yield (_free_node(root), "completed")


func test_step_support_collision_mask_keeps_structural_props() -> void:
	var root := Node.new()
	root.name = "PlayerHandheldStepMaskRoot"
	get_tree().root.add_child(root)

	var player = _build_player()
	root.add_child(player)
	yield (get_tree(), "idle_frame")

	player.collision_mask = 1048575
	assert_int(player._get_step_support_collision_mask()).is_equal(67)

	player.collision_mask = 64
	assert_int(player._get_step_support_collision_mask()).is_equal(64)

	player.collision_mask = 4
	assert_int(player._get_step_support_collision_mask()).is_equal(4)

	yield (_free_node(root), "completed")


func test_jump_vertical_camera_waits_before_rising() -> void:
	var root := Node.new()
	root.name = "PlayerHandheldLazyJumpRoot"
	get_tree().root.add_child(root)

	var player = _build_player()
	root.add_child(player)
	yield (get_tree(), "idle_frame")

	player.base_rig_y = 0.0
	player.camera_rig.transform.origin.y = 0.0
	player._camera_rig_y_smoothed_global = 0.0
	player._camera_rig_y_initialized = true
	player._camera_rig_airborne_anchor_global = 0.0
	player._camera_rig_airborne_rise_time = 0.0
	player._camera_rig_was_grounded = true
	player._cached_spring_arm = null
	player.current_spring_length = player.ots_blend_start_distance
	player._ots_camera_follow_weight = 0.0
	player._just_stepped = false
	player._step_grounded_timer = 0.0
	player.collision_mask = 0
	player.move_and_slide(Vector3.UP, Vector3.UP)
	player.velocity = Vector3(0.0, 8.0, 0.0)

	var tx: Transform = player.global_transform
	tx.origin.y = 0.2
	player.global_transform = tx

	player._update_camera_rig_vertical(1.0 / 60.0)

	assert_bool(abs(player._camera_rig_y_smoothed_global) < 0.0001) \
		.override_failure_message("smoothed=%s grounded=%s" % [player._camera_rig_y_smoothed_global, player.is_on_floor()]) \
		.is_true()
	assert_bool(abs(player.camera_rig.transform.origin.y + 0.2) < 0.0001) \
		.override_failure_message("rig_local_y=%s" % player.camera_rig.transform.origin.y) \
		.is_true()

	yield (_free_node(root), "completed")


func test_zoom_out_is_ignored_while_room_blocks_camera() -> void:
	var root := Node.new()
	root.name = "PlayerHandheldZoomClampRoot"
	get_tree().root.add_child(root)

	var player = _build_player()
	root.add_child(player)
	yield (get_tree(), "idle_frame")

	var spring_arm: DummySpringArm = player.get_node("CameraRig/Yaw/Pitch/SpringArm")
	player.base_spring_length_3d = 5.0
	spring_arm.zoom_out_blocked = true

	player._apply_orbit_zoom_delta(1.0)
	assert_float(player.base_spring_length_3d).is_equal(5.0)

	player._apply_orbit_zoom_delta(-1.0)
	assert_float(player.base_spring_length_3d).is_equal(4.0)

	yield (_free_node(root), "completed")
