extends GdUnitTestSuite

const AirlockZoneScript = preload("res://core_v2/components/AirlockZoneV2.gd")
const AirlockControllerScript = preload("res://core_v2/components/AirlockControllerV2.gd")

class FakePlayer:
	extends KinematicBody
	var velocity := Vector3.ZERO

	func _init() -> void:
		add_to_group("player")

	func get_full_snapshot() -> Dictionary:
		return {
			"position": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
			"velocity": [velocity.x, velocity.y, velocity.z],
			"controller_mode": 1,
			"gravity_mode": 2
		}

func _make_zone() -> Area:
	var zone = AirlockZoneScript.new()
	var shape_node := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(2.85, 2.5, 4.0)
	shape_node.shape = box
	zone.add_child(shape_node)
	zone.zone_extents = box.extents
	return zone

func test_forward_zone_progress_uses_centered_airlock_length() -> void:
	var zone = auto_free(_make_zone())
	add_child(zone)
	zone.zone_dir = Vector3.FORWARD

	var player = auto_free(FakePlayer.new())
	add_child(player)

	player.global_transform.origin = Vector3(0, 0, 4.0)
	zone._update_progress(player)
	assert_float(zone._progress).is_equal_approx(0.0, 0.001)

	player.global_transform.origin = Vector3(0, 0, -3.2)
	zone._update_progress(player)
	assert_float(zone._progress).is_equal_approx(0.9, 0.001)

func test_reverse_zone_progress_supports_rotated_terrace_airlock() -> void:
	var zone = auto_free(_make_zone())
	add_child(zone)
	zone.zone_dir = Vector3.BACK

	var player = auto_free(FakePlayer.new())
	add_child(player)

	player.global_transform.origin = Vector3(0, 0, -4.0)
	zone._update_progress(player)
	assert_float(zone._progress).is_equal_approx(0.0, 0.001)

	player.global_transform.origin = Vector3(0, 0, 3.2)
	zone._update_progress(player)
	assert_float(zone._progress).is_equal_approx(0.9, 0.001)

func test_transition_state_includes_player_snapshot_airlock_frame_and_exit_door() -> void:
	var airlock = auto_free(AirlockControllerScript.new())
	add_child(airlock)
	airlock.global_transform.origin = Vector3(10, 0, 0)

	var zone = _make_zone()
	airlock.add_child(zone)
	zone.zone_dir = Vector3.FORWARD
	zone.target_airlock_path = NodePath("TerraceAirlock")

	var player = auto_free(FakePlayer.new())
	add_child(player)
	player.global_transform.origin = Vector3(10, 1, -3.2)
	player.velocity = Vector3(0, 0, -2)

	var state_data: Dictionary = zone._build_state_data(player)

	assert_bool(state_data.has("player_snapshot")).is_true()
	assert_vector3(state_data["airlock_relative_position"]).is_equal(Vector3(0, 1, -3.2))
	assert_vector3(state_data["airlock_relative_transform"].origin).is_equal(Vector3(0, 1, -3.2))
	assert_str(state_data["target_airlock_path"]).is_equal("TerraceAirlock")
	assert_str(state_data["target_airlock_exit_door"]).is_equal("inner")
	assert_vector3(state_data["airlock_relative_velocity"]).is_equal(Vector3(0, 0, -2))

func test_transition_state_clamps_falling_vertical_offset() -> void:
	var airlock = auto_free(AirlockControllerScript.new())
	add_child(airlock)
	airlock.global_transform.origin = Vector3(0, 1.15, -6)

	var zone = _make_zone()
	airlock.add_child(zone)
	zone.zone_dir = Vector3.BACK
	zone._has_safe_relative_y = true
	zone._last_safe_relative_y = -0.2

	var player = auto_free(FakePlayer.new())
	add_child(player)
	player.global_transform.origin = Vector3(0.5, -2.4, -2.8)
	player.velocity = Vector3(0, -8, 0)

	var state_data: Dictionary = zone._build_state_data(player)

	assert_float(state_data["airlock_relative_position"].y).is_equal_approx(-0.2, 0.001)
	assert_float(state_data["airlock_relative_velocity"].y).is_equal_approx(0.0, 0.001)
