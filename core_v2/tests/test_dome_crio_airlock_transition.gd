extends GdUnitTestSuite

const DOME_CRIO_SCENE = preload("res://core_v2/levels/interiors/Dome_Crio.tscn")
const ODISEA_EXTERIOR_SCENE_PATH := "res://core_v2/levels/OdiseaExterior.tscn"
const AIRLOCK_NAMES := ["Airlock_North", "Airlock_South", "Airlock_East", "Airlock_West"]


class FakePlayer:
	extends KinematicBody

	var velocity := Vector3.ZERO

	func _init() -> void:
		add_to_group("player")

	func get_full_snapshot() -> Dictionary:
		return {
			"position": global_transform.origin,
			"velocity": velocity,
			"controller_mode": 1,
			"gravity_mode": 2
		}

func test_dome_crio_airlocks_are_wired_to_odisea_exterior() -> void:
	var dome = auto_free(DOME_CRIO_SCENE.instance())
	add_child(dome)

	for airlock_name in AIRLOCK_NAMES:
		var zone = dome.get_node("%s/AirlockZoneV2" % airlock_name)
		assert_str(zone.target_scene).is_equal(ODISEA_EXTERIOR_SCENE_PATH)
		assert_str(zone.target_spawn_id).is_equal("from_exterior_dome_01")
		assert_str(String(zone.target_airlock_path)).is_equal(airlock_name)


func test_walking_the_dome_crio_north_airlock_triggers_exterior_transition_state():
	var dome = auto_free(DOME_CRIO_SCENE.instance())
	add_child(dome)
	yield(get_tree(), "idle_frame")

	var zone = dome.get_node("Airlock_North/AirlockZoneV2")
	zone.set_physics_process(false)
	zone._scene_ready = true
	zone._background_load = null

	var player = auto_free(FakePlayer.new())
	dome.add_child(player)
	zone._on_host_body_entered(player)

	var samples := _walk_player_through_trigger(zone, player)
	yield(get_tree(), "idle_frame")

	assert_int(samples.size()).is_equal(4)
	assert_float(samples[0]).is_less(samples[1])
	assert_float(samples[1]).is_less(samples[2])
	assert_float(samples[2]).is_less(samples[3])
	assert_float(samples[3]).is_greater_equal(0.6)
	assert_bool(zone._has_triggered).is_true()
	assert_str(zone.target_scene).is_equal(ODISEA_EXTERIOR_SCENE_PATH)
	assert_str(zone.target_spawn_id).is_equal("from_exterior_dome_01")

	var state_data: Dictionary = zone._build_state_data(player)
	assert_bool(state_data.has("player_snapshot")).is_true()
	assert_str(state_data["target_airlock_path"]).is_equal("Airlock_North")
	assert_str(state_data["target_airlock_exit_door"]).is_equal("outer")
	var relative_position: Vector3 = state_data["airlock_relative_position"]
	var relative_transform: Transform = state_data["airlock_relative_transform"]
	var relative_velocity: Vector3 = state_data["airlock_relative_velocity"]
	assert_float(relative_position.x).is_equal_approx(0.0, 0.001)
	assert_float(relative_position.y).is_equal_approx(1.0, 0.001)
	assert_float(relative_position.z).is_equal_approx(1.2, 0.001)
	assert_float(relative_transform.origin.x).is_equal_approx(0.0, 0.001)
	assert_float(relative_transform.origin.y).is_equal_approx(1.0, 0.001)
	assert_float(relative_transform.origin.z).is_equal_approx(1.2, 0.001)
	assert_float(relative_velocity.x).is_equal_approx(0.0, 0.001)
	assert_float(relative_velocity.y).is_equal_approx(0.0, 0.001)
	assert_float(relative_velocity.z).is_equal_approx(2.0, 0.001)


func _walk_player_through_trigger(zone: Area, player: KinematicBody) -> Array:
	var local_points := [
		Vector3(0, 1, -3.8),
		Vector3(0, 1, -2.0),
		Vector3(0, 1, -0.2),
		Vector3(0, 1, 1.2)
	]
	var progress_samples := []
	player.velocity = zone.global_transform.basis.xform(Vector3(0, 0, 2.0))
	for local_point in local_points:
		var tx := player.global_transform
		tx.origin = zone.global_transform.xform(local_point)
		player.global_transform = tx
		zone._physics_process(1.0 / 60.0)
		progress_samples.append(zone._progress)
	return progress_samples
