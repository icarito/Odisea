extends GdUnitTestSuite

const CM_PATH := "/root/CinematicManager"
const PlayerControllerScript = preload("res://core_v2/player/PlayerControllerV2.gd")
const InputDataV2Script = preload("res://core_v2/input/InputDataV2.gd")


class DummyRig:
	extends Spatial
	var transition_time: float = 0.35
	var _camera: Camera = null

	func _init():
		_camera = Camera.new()
		_camera.name = "Camera"
		add_child(_camera)

	func activate(_make_current: bool = true) -> void:
		pass

	func deactivate(_restore_camera: bool = true) -> void:
		pass

	func get_camera() -> Camera:
		return _camera


class DummyZone:
	extends Node
	var is_zone_active: bool = true
	var _inside: bool = false
	var _rig_node: Node = null
	var control_mode: int = 0
	var latch_on_enter: bool = true
	var latch_on_exit: bool = true
	var _volume: float = 1.0

	func _init(rig: Node = null, volume: float = 1.0, mode: int = 2):
		_rig_node = rig
		_volume = volume
		control_mode = mode

	func is_body_in_zone(_body: Node) -> bool:
		return _inside

	func get_volume() -> float:
		return _volume

	func set_zone_occlusion_for_body(_body: Node, _active: bool) -> void:
		pass


class DummyPivot:
	extends Spatial

	func step_animator(_dt: float, _velocity: Vector3) -> void:
		pass

	func play_override_animation(_anim_name: String) -> void:
		pass


func _setup_root() -> Node:
	var root := Node.new()
	root.name = "PlayerCameraZoneRequestCleanupRoot"
	get_tree().root.add_child(root)
	return root


func _teardown_root(root: Node) -> void:
	if root and is_instance_valid(root):
		root.queue_free()
	yield (get_tree(), "idle_frame")


func _setup_player(root: Node) -> KinematicBody:
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

	player.set_script(PlayerControllerScript)
	root.add_child(player)
	return player


func test_zone_switch_releases_previous_request_and_exit_clears_last_request():
	var cm = get_node(CM_PATH)
	assert_object(cm).is_not_null()

	cm.reset()

	var root = _setup_root()
	var player = _setup_player(root)

	var rig_a := DummyRig.new()
	rig_a.name = "RigA"
	root.add_child(rig_a)

	var rig_b := DummyRig.new()
	rig_b.name = "RigB"
	root.add_child(rig_b)

	var zone_a := DummyZone.new(rig_a, 1.0, cm.ControlMode.LOCKED_VIEW)
	zone_a.name = "ZoneA"
	root.add_child(zone_a)
	zone_a.add_to_group("CameraZoneV2")

	var zone_b := DummyZone.new(rig_b, 1.0, cm.ControlMode.LOCKED_VIEW)
	zone_b.name = "ZoneB"
	root.add_child(zone_b)
	zone_b.add_to_group("CameraZoneV2")

	yield (get_tree(), "idle_frame")

	var input = InputDataV2Script.new()

	zone_a._inside = true
	player._update_cinematic_zone_detection(input, 1.0 / 60.0)
	var req_a: int = player._current_zone_request_id
	assert_bool(req_a != -1).is_true()
	assert_int(cm._active_requests.size()).is_equal(1)
	assert_bool(cm._active_requests.has(req_a)).is_true()

	zone_a._inside = false
	zone_b._inside = true
	player._update_cinematic_zone_detection(input, 1.0 / 60.0)
	var req_b: int = player._current_zone_request_id
	assert_bool(req_b != -1).is_true()
	assert_bool(req_b != req_a).is_true()
	assert_int(cm._active_requests.size()).is_equal(1)
	assert_bool(cm._active_requests.has(req_b)).is_true()
	assert_bool(cm._active_requests.has(req_a)).is_false()

	zone_b._inside = false
	for _i in range(14):
		player._update_cinematic_zone_detection(input, 1.0 / 60.0)

	assert_int(player._current_zone_request_id).is_equal(-1)
	assert_int(cm._active_requests.size()).is_equal(0)

	cm.reset()
	yield (_teardown_root(root), "completed")
