extends GdUnitTestSuite

const CM_PATH := "/root/CinematicManager"

class DummyRig:
	extends Spatial
	var transition_time := 0.45
	var _camera: Camera = null
	var activate_calls := 0
	var deactivate_calls := 0

	func _init():
		_camera = Camera.new()
		_camera.name = "Camera"
		add_child(_camera)

	func activate(make_current: bool = true):
		activate_calls += 1
		if make_current and is_instance_valid(_camera):
			_camera.current = true

	func deactivate(_restore_camera: bool = true):
		deactivate_calls += 1

	func get_camera() -> Camera:
		return _camera


class DummyCameraRig:
	extends Spatial
	var align_calls := 0
	var sync_calls := 0

	func align_exit_from_cinematic(_target_cam: Camera) -> void:
		align_calls += 1

	func sync_camera_to_rig() -> void:
		sync_calls += 1


func _setup_root() -> Node:
	var root := Node.new()
	root.name = "CinematicManagerTestRoot"
	get_tree().root.add_child(root)
	return root


func _teardown_root(root: Node) -> void:
	if root and is_instance_valid(root):
		root.queue_free()
	yield (get_tree(), "idle_frame")


func _setup_player_with_camera(root: Node) -> Dictionary:
	var player := KinematicBody.new()
	player.name = "Player"
	player.add_to_group("player")
	root.add_child(player)

	var camera_rig := DummyCameraRig.new()
	camera_rig.name = "CameraRig"
	player.add_child(camera_rig)

	var yaw := Spatial.new()
	yaw.name = "Yaw"
	camera_rig.add_child(yaw)

	var pitch := Spatial.new()
	pitch.name = "Pitch"
	yaw.add_child(pitch)

	var spring := Spatial.new()
	spring.name = "SpringArm"
	pitch.add_child(spring)

	var cam := Camera.new()
	cam.name = "Camera"
	cam.transform.origin = Vector3(0, 2.0, 8.0)
	spring.add_child(cam)
	cam.current = true

	return {
		"player": player,
		"camera_rig": camera_rig,
		"camera": cam
	}


func _setup_rig(root: Node, rig_name: String, cam_pos: Vector3) -> DummyRig:
	var rig := DummyRig.new()
	rig.name = rig_name
	root.add_child(rig)
	rig.get_camera().transform.origin = cam_pos
	return rig


func _find_event(events: Array, name: String) -> Dictionary:
	for e in events:
		if e is Dictionary and e.get("event", "") == name:
			return e
	return {}


func _ease_transition_t(raw_t: float) -> float:
	var t := clamp(raw_t, 0.0, 1.0)
	return -0.5 * (cos(PI * t) - 1.0)


func test_exit_transition_interrupted_by_new_zone_request():
	var cm = get_node(CM_PATH)
	assert_object(cm).is_not_null()

	cm.reset()
	cm.set_transition_debug(true)
	cm.clear_transition_debug_events()

	var root = _setup_root()
	_setup_player_with_camera(root)
	var rig_a: DummyRig = _setup_rig(root, "RigA", Vector3(8, 3, 6))
	var rig_b = _setup_rig(root, "RigB", Vector3(-6, 2.5, 12))

	yield (get_tree(), "idle_frame")

	var req_a = cm.request_camera_mode(
		cm.ControlMode.LOCKED_VIEW,
		{"rig": rig_a, "transition_time": 0.5},
		"test_a",
		10
	)
	cm.step(1.0 / 60.0)

	cm.release_camera_request(req_a)
	cm.step(1.0 / 60.0)
	assert_bool(cm._transition_active).is_true()

	var _req_b = cm.request_camera_mode(
		cm.ControlMode.LOCKED_VIEW,
		{"rig": rig_b, "transition_time": 0.5},
		"test_b",
		10
	)
	cm.step(1.0 / 60.0)

	assert_bool(cm._transition_active).is_true()
	assert_bool(cm.active_rig == rig_b).is_true()
	assert_int(rig_b.activate_calls).is_greater_equal(1)

	for _i in range(40):
		cm.step(1.0 / 60.0)
	assert_bool(cm._transition_active).is_false()

	var events = cm.get_transition_debug_events()
	assert_bool(_find_event(events, "dynamic_cancel").size() > 0).is_true()
	assert_bool(_find_event(events, "to_cinematic_blend").size() > 0).is_true()

	cm.reset()
	yield (_teardown_root(root), "completed")


func test_dynamic_finish_logs_residual_and_aligns_player_rig():
	var cm = get_node(CM_PATH)
	assert_object(cm).is_not_null()

	cm.reset()
	cm.set_transition_debug(true)
	cm.clear_transition_debug_events()

	var root = _setup_root()
	var player_data = _setup_player_with_camera(root)
	var player_cam: Camera = player_data["camera"]
	var camera_rig: DummyCameraRig = player_data["camera_rig"]

	var rig_a = _setup_rig(root, "RigA", Vector3(10, 3, 9))
	yield (get_tree(), "idle_frame")

	cm._start_dynamic_transition(rig_a.get_camera(), player_cam, 0.3)
	assert_bool(cm._transition_active).is_true()

	# Force a large mismatch right before finish to emulate a bad handoff frame.
	if CameraTransition and CameraTransition.camera3D:
		CameraTransition.camera3D.global_transform = Transform(
			Basis(Vector3.UP, deg2rad(90.0)),
			player_cam.global_transform.origin + Vector3(2.0, 0.0, 0.0)
		)
		CameraTransition.camera3D.fov = 40.0

	cm._finish_dynamic_transition()

	assert_bool(cm._transition_active).is_false()
	assert_bool(player_cam.current).is_true()
	assert_int(camera_rig.align_calls).is_greater_equal(1)
	assert_int(camera_rig.sync_calls).is_greater_equal(1)

	var ev = _find_event(cm.get_transition_debug_events(), "dynamic_finish")
	assert_bool(ev.size() > 0).is_true()
	assert_bool(bool(ev.get("data", {}).get("aligned", false))).is_true()

	cm.reset()
	yield (_teardown_root(root), "completed")


func test_get_active_camera_prefers_dynamic_transition_camera():
	var cm = get_node(CM_PATH)
	assert_object(cm).is_not_null()

	cm.reset()
	var root = _setup_root()
	var player_data = _setup_player_with_camera(root)
	var player_cam: Camera = player_data["camera"]
	var rig_a = _setup_rig(root, "RigA", Vector3(10, 3, 9))
	yield (get_tree(), "idle_frame")

	cm._start_dynamic_transition(rig_a.get_camera(), player_cam, 0.5)

	var active_cam = cm.get_active_camera()
	assert_bool(active_cam == CameraTransition.camera3D).is_true()

	cm.reset()
	yield (_teardown_root(root), "completed")


func test_is_active_when_camera_shake_running():
	var cm = get_node(CM_PATH)
	assert_object(cm).is_not_null()

	cm.reset()
	assert_bool(cm.is_active()).is_false()

	cm.trigger_camera_shake(0.5, 0.1, 20.0, 1.0)
	assert_bool(cm.is_active()).is_true()

	cm.stop_camera_shake()
	assert_bool(cm.is_active()).is_false()


func test_to_cinematic_dynamic_transition_tracks_moving_rig_target():
	var cm = get_node(CM_PATH)
	assert_object(cm).is_not_null()

	cm.reset()
	var root = _setup_root()
	_setup_player_with_camera(root)
	var rig_a = _setup_rig(root, "RigA", Vector3(8, 3, 6))
	yield (get_tree(), "idle_frame")

	cm.request_camera_mode(
		cm.ControlMode.LOCKED_VIEW,
		{"rig": rig_a, "transition_time": 0.6},
		"test_move_target_entry",
		10
	)
	cm.step(1.0 / 60.0)

	assert_bool(cm._transition_active).is_true()
	assert_str(cm._transition_purpose).is_equal("to_cinematic")
	assert_object(CameraTransition.camera3D).is_not_null()

	for i in range(1, 10):
		var rig_cam: Camera = rig_a.get_camera()
		var moved_tx: Transform = rig_cam.global_transform
		moved_tx.origin = Vector3(8.0 + float(i) * 0.9, 3.0, 6.0 + float(i) * 0.35)
		rig_cam.global_transform = moved_tx

		cm.step(1.0 / 60.0)

		var raw_t: float = float(cm._transition_elapsed) / max(0.0001, float(cm._transition_duration))
		var t: float = _ease_transition_t(raw_t)
		var expected_tx: Transform = cm._transition_start_transform.interpolate_with(rig_cam.global_transform, t)
		var blend_tx: Transform = CameraTransition.camera3D.global_transform
		assert_float(blend_tx.origin.distance_to(expected_tx.origin)).is_less(0.0015)

	cm.reset()
	yield (_teardown_root(root), "completed")


func test_to_free_dynamic_transition_tracks_moving_player_target():
	var cm = get_node(CM_PATH)
	assert_object(cm).is_not_null()

	cm.reset()
	var root = _setup_root()
	var player_data = _setup_player_with_camera(root)
	var player_cam: Camera = player_data["camera"]
	var rig_a = _setup_rig(root, "RigA", Vector3(10, 3, 9))
	yield (get_tree(), "idle_frame")

	cm._start_dynamic_transition(rig_a.get_camera(), player_cam, 0.6, "to_free")
	assert_bool(cm._transition_active).is_true()
	assert_str(cm._transition_purpose).is_equal("to_free")
	assert_object(CameraTransition.camera3D).is_not_null()

	for i in range(1, 10):
		var moved_tx: Transform = player_cam.global_transform
		moved_tx.origin = Vector3(0.0 + float(i) * 0.6, 2.0, 8.0 + float(i) * 0.4)
		player_cam.global_transform = moved_tx

		cm.step(1.0 / 60.0)

		var raw_t: float = float(cm._transition_elapsed) / max(0.0001, float(cm._transition_duration))
		var t: float = _ease_transition_t(raw_t)
		var expected_tx: Transform = cm._transition_start_transform.interpolate_with(player_cam.global_transform, t)
		var blend_tx: Transform = CameraTransition.camera3D.global_transform
		assert_float(blend_tx.origin.distance_to(expected_tx.origin)).is_less(0.0015)

	cm.reset()
	yield (_teardown_root(root), "completed")
