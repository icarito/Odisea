extends GdUnitTestSuite

const AirlockZoneScript = preload("res://core_v2/components/AirlockZoneV2.gd")
const AirlockControllerScript = preload("res://core_v2/components/AirlockControllerV2.gd")
const WorldRotatorScript = preload("res://core_v2/systems/WorldRotator.gd")

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

class FakeDoor:
	extends Spatial
	var is_active := false
	var anim_progress := 0.0
	var target_progress := 0.0

	func set_active(value: bool, immediate: bool = false) -> void:
		is_active = value
		target_progress = 1.0 if value else 0.0
		if immediate:
			anim_progress = target_progress

	func interact() -> void:
		if has_meta("airlock_controller_owned") and bool(get_meta("airlock_controller_owned")):
			var owner_path = get_meta("airlock_controller_owner_path")
			var owner: Node = null
			if owner_path is NodePath:
				owner = get_node_or_null(owner_path)
			if is_instance_valid(owner) and owner.has_method("request_door_interaction"):
				owner.request_door_interaction(String(get_meta("airlock_door_name")))
			return
		set_active(not is_active, true)

func _make_zone() -> Area:
	var zone = AirlockZoneScript.new()
	var shape_node := CollisionShape.new()
	var box := BoxShape.new()
	box.extents = Vector3(2.85, 2.5, 4.0)
	shape_node.shape = box
	zone.add_child(shape_node)
	zone.zone_extents = box.extents
	return zone

func _make_airlock_with_doors() -> AirlockControllerV2:
	var airlock = AirlockControllerScript.new()
	var outer = FakeDoor.new()
	outer.name = "OuterDoor"
	var inner = FakeDoor.new()
	inner.name = "InnerDoor"
	airlock.add_child(outer)
	airlock.add_child(inner)
	airlock.outer_door_path = NodePath("OuterDoor")
	airlock.inner_door_path = NodePath("InnerDoor")
	return airlock

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

func test_resolve_active_dome_id_uses_player_metadata_after_transition() -> void:
	var zone = auto_free(_make_zone())
	add_child(zone)

	var player = auto_free(FakePlayer.new())
	player.set_meta("dome_id", "dome_03")
	add_child(player)

	assert_str(zone._resolve_active_dome_id()).is_equal("dome_03")

func test_pressurizing_airlock_ignores_manual_interact() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	yield(get_tree(), "idle_frame")

	assert_bool(airlock.start_transition_cycle("outer")).is_true()
	airlock.interact()

	var outer = airlock.get_node("OuterDoor")
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.PRESSURIZING)
	assert_bool(outer.is_active).is_false()

func test_managed_door_direct_interact_routes_through_controller() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	yield(get_tree(), "idle_frame")

	var outer = airlock.get_node("OuterDoor")
	var inner = airlock.get_node("InnerDoor")
	outer.interact()

	assert_bool(outer.has_meta("airlock_controller_owned")).is_true()
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.ENTRY_OPEN)
	assert_bool(outer.is_active).is_true()
	assert_bool(inner.is_active).is_false()

func test_open_exit_door_switches_side_exclusively() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	yield(get_tree(), "idle_frame")

	var outer = airlock.get_node("OuterDoor")
	var inner = airlock.get_node("InnerDoor")

	assert_bool(airlock.open_exit_door("outer", true)).is_true()
	assert_bool(outer.is_active).is_true()
	assert_bool(inner.is_active).is_false()

	assert_bool(airlock.open_exit_door("inner", true)).is_true()
	assert_bool(outer.is_active).is_false()
	assert_bool(inner.is_active).is_true()
	assert_str(airlock.get_open_exit_door_name()).is_equal("inner")

func test_abort_transition_reopens_entry_red_state_then_auto_closes() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	yield(get_tree(), "idle_frame")

	assert_bool(airlock.start_transition_cycle("outer")).is_true()
	assert_bool(airlock.abort_transition_cycle("outer")).is_true()

	var outer = airlock.get_node("OuterDoor")
	var inner = airlock.get_node("InnerDoor")
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.ENTRY_OPEN)
	assert_bool(outer.is_active).is_true()
	assert_bool(inner.is_active).is_false()

	airlock.step(airlock.reset_time + 0.1)

	assert_int(airlock.state).is_equal(AirlockControllerV2.State.IDLE)
	assert_bool(outer.is_active).is_false()

func test_zone_triggers_transition_when_entry_door_is_sealed() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	var zone = _make_zone()
	airlock.add_child(zone)
	zone._scene_ready = true
	zone._background_load = null
	zone.zone_dir = Vector3.FORWARD

	var player = auto_free(FakePlayer.new())
	add_child(player)
	player.global_transform.origin = airlock.global_transform.xform(Vector3(0, 1, 3.8))

	zone._on_host_body_entered(player)
	zone._physics_process(1.0 / 60.0)

	assert_float(zone._progress).is_less(0.6)
	assert_bool(zone._has_triggered).is_true()

func test_zone_exit_before_transition_aborts_to_entry_open() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	var zone = _make_zone()
	airlock.add_child(zone)
	zone._scene_ready = false
	zone._background_load = null
	zone.zone_dir = Vector3.FORWARD

	var player = auto_free(FakePlayer.new())
	add_child(player)

	zone._on_host_body_entered(player)
	zone._on_host_body_exited(player)

	var outer = airlock.get_node("OuterDoor")
	assert_bool(zone._has_triggered).is_false()
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.ENTRY_OPEN)
	assert_bool(outer.is_active).is_true()

func test_zone_suspends_tracking_until_player_exits_airlock() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	var zone = _make_zone()
	airlock.add_child(zone)

	var player = auto_free(FakePlayer.new())
	add_child(player)

	zone._on_host_body_entered(player)
	assert_bool(player.has_meta("airlock_tracking_suspended")).is_true()

	zone._on_host_body_exited(player)
	assert_bool(player.has_meta("airlock_tracking_suspended")).is_false()

func test_open_exit_door_clamps_player_to_exit_side() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	var zone = _make_zone()
	airlock.add_child(zone)
	zone.zone_dir = Vector3.FORWARD
	yield(get_tree(), "idle_frame")

	var player = auto_free(FakePlayer.new())
	add_child(player)
	player.global_transform.origin = airlock.global_transform.xform(Vector3(0, 1, -1.0))

	airlock.open_exit_door("outer", true)
	zone._clamp_to_open_exit_side(player)

	var local_pos: Vector3 = airlock.global_transform.affine_inverse().xform(player.global_transform.origin)
	assert_float(local_pos.z).is_greater_equal(0.15)

func test_open_inner_exit_door_clamps_player_to_inner_side() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	var zone = _make_zone()
	airlock.add_child(zone)
	zone.zone_dir = Vector3.FORWARD
	yield(get_tree(), "idle_frame")

	var player = auto_free(FakePlayer.new())
	add_child(player)
	player.global_transform.origin = airlock.global_transform.xform(Vector3(0, 1, 1.0))

	airlock.open_exit_door("inner", true)
	zone._clamp_to_open_exit_side(player)

	var local_pos: Vector3 = airlock.global_transform.affine_inverse().xform(player.global_transform.origin)
	assert_float(local_pos.z).is_less_equal(-0.15)

func test_world_rotator_ignores_airlock_suspended_player_for_continuous_tracking() -> void:
	var rotator = auto_free(WorldRotatorScript.new())
	add_child(rotator)

	var player = auto_free(FakePlayer.new())
	add_child(player)
	player.set_meta("airlock_tracking_suspended", true)

	assert_object(rotator._get_tracking_target()).is_null()
