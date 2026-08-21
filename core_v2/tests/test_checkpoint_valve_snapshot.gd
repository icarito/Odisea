extends GdUnitTestSuite

const CheckpointManagerScript = preload("res://core_v2/systems/CheckpointManager.gd")
const Room3DScript = preload("res://core_v2/systems/room/Room3D.gd")
const IceLevelScript = preload("res://core_v2/systems/ice/IceLevel.gd")


class MockValve extends Spatial:
	var is_open: bool = true

	func get_snapshot() -> Dictionary:
		return {"is_open": is_open}

	func restore_snapshot(data: Dictionary) -> void:
		is_open = bool(data.get("is_open", true))


class MockPlayer extends Spatial:
	var yaw: float = 0.0
	var pitch: float = 0.0
	var initial_transform: Transform = Transform.IDENTITY


func test_initial_respawn_restores_valve_snapshot() -> void:
	var player: MockPlayer = auto_free(MockPlayer.new())
	player.add_to_group("player")
	add_child(player)
	var valve: MockValve = auto_free(MockValve.new())
	valve.add_to_group("replay_sync")
	add_child(valve)
	var checkpoint: Node = auto_free(CheckpointManagerScript.new())
	add_child(checkpoint)

	valve.is_open = false
	checkpoint._cache_default_spawn()
	valve.is_open = true
	checkpoint.get_respawn_transform()

	assert_bool(valve.is_open).is_false()


func test_active_checkpoint_restores_valve_snapshot() -> void:
	var valve: MockValve = auto_free(MockValve.new())
	valve.add_to_group("replay_sync")
	add_child(valve)
	var checkpoint: Node = auto_free(CheckpointManagerScript.new())
	add_child(checkpoint)

	valve.is_open = false
	checkpoint.set_active_checkpoint(Vector3(1.0, 2.0, 3.0), 0.0, 0.0)
	valve.is_open = true
	checkpoint.get_respawn_transform()

	assert_bool(valve.is_open).is_false()


func test_active_checkpoint_restores_room3d_replay_snapshot() -> void:
	var player: MockPlayer = auto_free(MockPlayer.new())
	player.add_to_group("player")
	add_child(player)
	var room: Node = auto_free(Room3DScript.new())
	room.temperature = 20.0
	room.pressure = 1.0
	room.contamination = 0.0
	add_child(room)
	var checkpoint: Node = auto_free(CheckpointManagerScript.new())
	add_child(checkpoint)

	room.set_temperature(-20.0)
	room.set_pressure(1.8)
	room.set_contamination(0.9)
	checkpoint.set_active_checkpoint(Vector3(1.0, 2.0, 3.0), 0.0, 0.0)
	room.set_temperature(-35.0)
	room.set_pressure(0.2)
	room.set_contamination(1.0)
	checkpoint.get_respawn_transform()

	assert_float(room.temperature).is_equal(-20.0)
	assert_float(room.pressure).is_equal(1.8)
	assert_float(room.contamination).is_equal(0.9)


func test_initial_snapshot_restores_room3d_environment() -> void:
	var player: MockPlayer = auto_free(MockPlayer.new())
	player.add_to_group("player")
	add_child(player)
	var room: Node = auto_free(Room3DScript.new())
	room.temperature = 20.0
	room.pressure = 1.0
	room.contamination = 0.0
	add_child(room)
	assert_bool(room.is_in_group("replay_sync")).is_true()
	var checkpoint: Node = auto_free(CheckpointManagerScript.new())
	add_child(checkpoint)

	checkpoint._cache_default_spawn()
	room.set_temperature(-35.0)
	room.set_pressure(2.0)
	room.set_contamination(0.8)
	checkpoint.get_respawn_transform()

	assert_float(room.temperature).is_equal(20.0)
	assert_float(room.pressure).is_equal(1.0)
	assert_float(room.contamination).is_equal(0.0)


func test_initial_snapshot_restores_ice_level_state() -> void:
	var player: MockPlayer = auto_free(MockPlayer.new())
	player.add_to_group("player")
	add_child(player)
	var ice: Node = auto_free(IceLevelScript.new())
	ice.auto_start = false
	ice.debug_draw = false
	add_child(ice)
	var checkpoint: Node = auto_free(CheckpointManagerScript.new())
	add_child(checkpoint)

	ice.ice_height = 4.5
	checkpoint._cache_default_spawn()
	ice.ice_height = 0.0
	checkpoint.get_respawn_transform()

	assert_float(ice.ice_height).is_equal_approx(4.5, 0.0001)


func test_empty_active_checkpoint_falls_back_to_initial_snapshot() -> void:
	var player: MockPlayer = auto_free(MockPlayer.new())
	player.initial_transform = Transform(Basis.IDENTITY, Vector3(3.0, 4.0, 5.0))
	player.add_to_group("player")
	add_child(player)
	var valve: MockValve = auto_free(MockValve.new())
	valve.add_to_group("replay_sync")
	add_child(valve)
	var checkpoint: Node = auto_free(CheckpointManagerScript.new())
	add_child(checkpoint)

	valve.is_open = false
	checkpoint._cache_default_spawn()
	checkpoint.active_checkpoint_pos = Vector3(9.0, 9.0, 9.0)
	checkpoint.active_replay_snapshot.clear()
	valve.is_open = true
	var respawn: Dictionary = checkpoint.get_respawn_transform()

	assert_bool(valve.is_open).is_false()
	assert_float((respawn["position"] as Vector3).distance_to(player.initial_transform.origin)).is_equal_approx(0.0, 0.0001)
