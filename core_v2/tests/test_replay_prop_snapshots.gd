extends GdUnitTestSuite

const ElevatorPropScene = preload("res://core_v2/props/ElevatorProp.tscn")
const CriopodScene = preload("res://core_v2/props/Criopod_vert.tscn")

func _scene_host() -> Node:
	return get_tree().current_scene if get_tree().current_scene else self

func test_world_snapshot_includes_elevator_platform_and_criopod_door_state() -> void:
	var host = _scene_host()
	var root := Spatial.new()
	root.name = "ReplayPropSnapshotRoot"
	host.add_child(root)

	var elevator = ElevatorPropScene.instance()
	elevator.name = "ElevatorUnderTest"
	root.add_child(elevator)

	var criopod = CriopodScene.instance()
	criopod.name = "CriopodUnderTest"
	root.add_child(criopod)

	yield (get_tree(), "idle_frame")

	var door = criopod.get_node("RotatingObjectV2")
	var platform = elevator.get_node("Platform")
	door.set_active(true, true)
	var door_snapshot = door.get_snapshot()
	var platform_snapshot = platform.get_snapshot()

	assert_bool(platform.is_in_group("replay_sync")).is_true()
	assert_bool(door.is_in_group("replay_sync")).is_true()
	assert_bool(bool(door_snapshot.get("active", false))).is_true()
	assert_bool(platform_snapshot.has("target_height")).is_true()

	root.queue_free()
	yield (get_tree(), "idle_frame")

func test_elevator_controller_snapshot_roundtrip_preserves_runtime_state() -> void:
	var host = _scene_host()
	var elevator = ElevatorPropScene.instance()
	host.add_child(elevator)
	yield (get_tree(), "idle_frame")

	elevator.requests = [2, 1]
	elevator.current_floor = 1
	elevator.target_floor = 2
	elevator.is_moving = true
	var snapshot = elevator.get_snapshot()

	var restored = ElevatorPropScene.instance()
	host.add_child(restored)
	yield (get_tree(), "idle_frame")
	restored.restore_snapshot(snapshot)

	assert_array(restored.requests).contains_exactly([2, 1])
	assert_int(restored.current_floor).is_equal(1)
	assert_int(restored.target_floor).is_equal(2)
	assert_bool(restored.is_moving).is_true()

	elevator.queue_free()
	restored.queue_free()
	yield (get_tree(), "idle_frame")

func test_elevator_platform_snapshot_roundtrip_preserves_motion_state() -> void:
	var host = _scene_host()
	var elevator = ElevatorPropScene.instance()
	host.add_child(elevator)
	yield (get_tree(), "idle_frame")

	var platform = elevator.get_node("Platform")
	platform.global_transform.origin = Vector3(0, 3.5, 0)
	platform.target_height = 5.0
	platform.current_velocity_y = 1.25
	platform.is_moving = true
	var snapshot = platform.get_snapshot()

	var restored_elevator = ElevatorPropScene.instance()
	host.add_child(restored_elevator)
	yield (get_tree(), "idle_frame")
	var restored_platform = restored_elevator.get_node("Platform")
	restored_platform.restore_snapshot(snapshot)

	assert_float(restored_platform.global_transform.origin.y).is_equal(3.5)
	assert_float(restored_platform.target_height).is_equal(5.0)
	assert_float(restored_platform.current_velocity_y).is_equal(1.25)
	assert_bool(restored_platform.is_moving).is_true()
	assert_bool(restored_platform.is_in_group("replay_sync")).is_true()

	elevator.queue_free()
	restored_elevator.queue_free()
	yield (get_tree(), "idle_frame")
