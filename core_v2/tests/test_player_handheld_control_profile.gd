extends GdUnitTestSuite

const PlayerControllerScript = preload("res://core_v2/player/PlayerControllerV2.gd")


class DummyPivot:
	extends Spatial

	func step_animator(_dt: float, _velocity: Vector3) -> void:
		pass

	func play_override_animation(_anim_name: String) -> void:
		pass


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

	var spring_arm := SpringArm.new()
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


func test_hyper_low_profile_marks_auto_align_for_disable() -> void:
	var hp = get_tree().root.get_node_or_null("HardwareProfile")
	assert_object(hp).is_not_null()
	var previous_hyper_low = hp._hyper_low_mode
	hp._hyper_low_mode = true

	var root := Node.new()
	root.name = "PlayerHandheldControlProfileRoot"
	get_tree().root.add_child(root)

	var player = _build_player()
	root.add_child(player)
	yield (get_tree(), "idle_frame")

	assert_bool(player._should_disable_auto_align_for_profile()).is_true()
	player.enable_auto_align = true
	if player._should_disable_auto_align_for_profile():
		player.enable_auto_align = false
	assert_bool(player.enable_auto_align).is_false()

	yield (_free_node(root), "completed")
	hp._hyper_low_mode = previous_hyper_low


func test_hyper_low_profile_keeps_animator_frame_throttle_disabled() -> void:
	var hp = get_tree().root.get_node_or_null("HardwareProfile")
	assert_object(hp).is_not_null()
	var previous_hyper_low = hp._hyper_low_mode
	hp._hyper_low_mode = true

	var root := Node.new()
	root.name = "PlayerHandheldAnimatorThrottleRoot"
	get_tree().root.add_child(root)

	var player = _build_player()
	root.add_child(player)
	yield (get_tree(), "idle_frame")

	assert_bool(player._should_throttle_animator_for_profile()).is_false()
	assert_bool(player._hyper_low_animator_throttle).is_false()

	yield (_free_node(root), "completed")
	hp._hyper_low_mode = previous_hyper_low


func test_hyper_low_profile_keeps_cinematic_zone_scan_enabled() -> void:
	var hp = get_tree().root.get_node_or_null("HardwareProfile")
	assert_object(hp).is_not_null()
	var previous_hyper_low = hp._hyper_low_mode
	hp._hyper_low_mode = true

	var root := Node.new()
	root.name = "PlayerHandheldCameraZoneRoot"
	get_tree().root.add_child(root)

	var player = _build_player()
	root.add_child(player)
	yield (get_tree(), "idle_frame")

	assert_bool(player._perf_disable_cinematic_zone_scan).is_false()

	yield (_free_node(root), "completed")
	hp._hyper_low_mode = previous_hyper_low
