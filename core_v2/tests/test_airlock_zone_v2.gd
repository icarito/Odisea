extends GdUnitTestSuite

const AirlockZoneScript = preload("res://core_v2/components/AirlockZoneV2.gd")
const AirlockControllerScript = preload("res://core_v2/components/AirlockControllerV2.gd")
const AirlockManagerScript = preload("res://core_v2/autoloads/AirlockManager.gd")
const WorldRotatorScript = preload("res://core_v2/systems/WorldRotator.gd")
const AirlockChamberScene = preload("res://core_v2/props/AirlockChamber.tscn")

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

class FakeAnimator:
	extends Node
	var last_direction := Vector3.ZERO

	func snap_visual_to_direction(world_direction: Vector3) -> void:
		last_direction = world_direction

class FakeVisualPlayer:
	extends KinematicBody
	var animator: Node = null

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

func test_transition_state_opens_outer_exit_when_entering_from_inner() -> void:
	var airlock = auto_free(AirlockControllerScript.new())
	add_child(airlock)

	var zone = _make_zone()
	airlock.add_child(zone)
	zone._entry_door_name = "inner"

	var player = auto_free(FakePlayer.new())
	add_child(player)

	var state_data: Dictionary = zone._build_state_data(player)

	assert_str(state_data["target_airlock_exit_door"]).is_equal("outer")

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

func test_zone_triggers_transition_when_player_crosses_60_percent() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	var zone = _make_zone()
	airlock.add_child(zone)
	zone._scene_ready = true
	zone._background_load = null
	zone.zone_dir = Vector3.FORWARD

	var player = auto_free(FakePlayer.new())
	add_child(player)
	# Start at entry side — below 60% threshold
	player.global_transform.origin = airlock.global_transform.xform(Vector3(0, 1, 3.8))

	zone._on_host_body_entered(player)
	zone._physics_process(1.0 / 60.0)

	assert_float(zone._progress).is_less(0.6)
	assert_bool(zone._has_triggered).is_false()
	assert_bool(airlock._pressurize_active).is_false()

	# Move past 60% — pressurization should auto-trigger
	player.global_transform.origin = airlock.global_transform.xform(Vector3(0, 1, -1.0))
	zone._physics_process(1.0 / 60.0)
	assert_float(zone._progress).is_greater_equal(0.6)
	assert_bool(airlock._pressurize_active).is_true()
	assert_bool(zone._has_triggered).is_false()

	airlock.step(airlock.pressurize_time + 0.1)
	zone._physics_process(1.0 / 60.0)

	assert_bool(zone._has_triggered).is_true()

func test_transition_request_requires_pressurizing_sealed_entry() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	yield(get_tree(), "idle_frame")

	# request_transition_pressurization auto-starts the cycle from IDLE and pressurizes.
	assert_bool(airlock.request_transition_pressurization()).is_true()
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.PRESSURIZING)
	assert_bool(airlock.is_transition_requested()).is_false()
	airlock.step(airlock.pressurize_time + 0.1)
	assert_bool(airlock.is_transition_requested()).is_true()

func test_waiting_airlock_allows_entry_door_abort_but_locks_exit() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	yield(get_tree(), "idle_frame")

	# Before pressurize is triggered (player hasn't reached 60% yet), entry door aborts cycle
	assert_bool(airlock.start_transition_cycle("outer")).is_true()
	assert_bool(airlock.request_door_interaction("inner")).is_false()
	assert_bool(airlock.request_door_interaction("outer")).is_true()

	var outer = airlock.get_node("OuterDoor")
	var inner = airlock.get_node("InnerDoor")
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.ENTRY_OPEN)
	assert_bool(outer.is_active).is_true()
	assert_bool(inner.is_active).is_false()

func test_exit_door_timeout_returns_to_waiting_same_green_side() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	yield(get_tree(), "idle_frame")

	assert_bool(airlock.open_exit_door("outer", true)).is_true()
	airlock.step(airlock.reset_time + 0.1)

	assert_int(airlock.state).is_equal(AirlockControllerV2.State.PRESSURIZING)
	assert_bool(airlock.request_door_interaction("inner")).is_false()
	assert_bool(airlock.request_door_interaction("outer")).is_true()

func test_transition_cycle_can_restart_from_open_exit_for_return_trip() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	yield(get_tree(), "idle_frame")

	assert_bool(airlock.open_exit_door("outer", true)).is_true()
	assert_bool(airlock.start_transition_cycle("outer")).is_true()

	var outer = airlock.get_node("OuterDoor")
	var inner = airlock.get_node("InnerDoor")
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.PRESSURIZING)
	assert_bool(airlock._pressurize_active).is_false()
	assert_bool(outer.is_active).is_false()
	assert_bool(inner.is_active).is_false()

func test_transition_cycle_can_restart_after_exit_timeout_waiting_state() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	yield(get_tree(), "idle_frame")

	assert_bool(airlock.open_exit_door("outer", true)).is_true()
	airlock.step(airlock.reset_time + 0.1)

	assert_int(airlock.state).is_equal(AirlockControllerV2.State.PRESSURIZING)
	assert_bool(airlock.start_transition_cycle("outer")).is_true()
	assert_bool(airlock._pressurize_active).is_false()

func test_airlock_chamber_open_exit_door_opens_real_iris_and_keeps_it_interactable() -> void:
	var airlock = auto_free(AirlockChamberScene.instance())
	add_child(airlock)
	yield(get_tree(), "idle_frame")

	assert_bool(airlock.open_exit_door("outer", true)).is_true()

	var outer = airlock.get_node("OuterDoor")
	var outer_state = outer.get_node("IrisMechanism")
	assert_bool(outer_state.is_active).is_true()
	assert_bool(outer.is_in_group("interactable")).is_true()
	assert_bool(outer.has_meta("airlock_controller_owned")).is_true()

	assert_bool(airlock.open_exit_door("inner", true)).is_true()

	var inner = airlock.get_node("InnerDoor")
	var inner_state = inner.get_node("IrisMechanism")
	assert_bool(outer_state.is_active).is_false()
	assert_bool(inner_state.is_active).is_true()
	assert_bool(inner.is_in_group("interactable")).is_true()
	assert_bool(inner.has_meta("airlock_controller_owned")).is_true()

func test_zone_auto_arms_when_player_is_already_inside_after_scene_load() -> void:
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

	zone._physics_process(1.0 / 60.0)

	assert_bool(zone._player_in_zone).is_true()
	assert_int(airlock.state).is_equal(AirlockControllerV2.State.PRESSURIZING)
	assert_bool(airlock._pressurize_active).is_false()

func test_airlock_manager_carries_active_chamber_into_scene_without_static_airlock() -> void:
	var manager = auto_free(AirlockManagerScript.new())
	add_child(manager)

	var old_scene = auto_free(Node.new())
	old_scene.name = "OldScene"
	add_child(old_scene)
	var new_scene = auto_free(Node.new())
	new_scene.name = "NewScene"
	add_child(new_scene)

	var airlock = _make_airlock_with_doors()
	airlock.name = "Airlock_North"
	old_scene.add_child(airlock)
	yield(get_tree(), "idle_frame")
	assert_bool(airlock.start_transition_cycle("inner")).is_true()

	var player = FakePlayer.new()
	player.name = "Pilot"
	old_scene.add_child(player)

	var params := {
		"state_data": {
			"target_airlock_path": NodePath("Airlock_North"),
			"target_airlock_exit_door": "outer"
		}
	}
	manager.notify_transition("res://core_v2/levels/OdiseaExterior.tscn")
	manager._on_pre_scene_swap(old_scene, new_scene, params)
	manager._on_pre_spawn_state("res://core_v2/levels/OdiseaExterior.tscn", new_scene, params)

	assert_bool(params.get("_airlock_manager_placed", false)).is_true()
	assert_bool(new_scene.has_node("Airlock_North")).is_true()
	assert_bool(new_scene.has_node("Pilot")).is_true()

func test_session_airlock_exit_outer_faces_project_forward_negative_z() -> void:
	var session = auto_free(load("res://core_v2/autoloads/SessionManager.gd").new())
	add_child(session)

	var airlock = auto_free(AirlockControllerScript.new())
	add_child(airlock)

	var state_data := {"target_airlock_exit_door": "outer"}
	var out: Transform = session._face_airlock_exit(airlock, state_data, Transform.IDENTITY)
	var forward := -out.basis.z

	assert_vector3(forward).is_equal_approx(Vector3.FORWARD, Vector3(0.001, 0.001, 0.001))

func test_session_opens_outer_exit_immediately_on_real_airlock() -> void:
	var session = auto_free(load("res://core_v2/autoloads/SessionManager.gd").new())
	add_child(session)
	var airlock = auto_free(AirlockChamberScene.instance())
	add_child(airlock)
	yield(get_tree(), "idle_frame")

	session._open_transition_airlock_exit(airlock, {"target_airlock_exit_door": "outer"})

	var outer_state = airlock.get_node("OuterDoor/IrisMechanism")
	assert_bool(outer_state.is_active).is_true()
	assert_float(outer_state.anim_progress).is_equal_approx(1.0, 0.001)

func test_session_visual_snap_uses_animator_expected_direction_sign() -> void:
	var session = auto_free(load("res://core_v2/autoloads/SessionManager.gd").new())
	add_child(session)
	var player = auto_free(FakeVisualPlayer.new())
	var animator = FakeAnimator.new()
	player.animator = animator
	player.add_child(animator)

	session.set("player", player)
	session._snap_transition_visual(Transform.IDENTITY)

	assert_vector3(animator.last_direction).is_equal(Vector3.BACK)

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

func test_waiting_airlock_does_not_geometrically_block_player() -> void:
	var airlock = auto_free(_make_airlock_with_doors())
	add_child(airlock)
	var zone = _make_zone()
	airlock.add_child(zone)
	zone.zone_dir = Vector3.FORWARD
	zone._scene_ready = true
	yield(get_tree(), "idle_frame")

	var player = auto_free(FakePlayer.new())
	add_child(player)
	player.global_transform.origin = airlock.global_transform.xform(Vector3(0, 1, 3.7))

	zone._on_host_body_entered(player)
	zone._physics_process(1.0 / 60.0)

	var tx: Transform = player.global_transform
	tx.origin = airlock.global_transform.xform(Vector3(0, 1, -3.7))
	player.global_transform = tx
	zone._physics_process(1.0 / 60.0)

	var local_pos: Vector3 = airlock.global_transform.affine_inverse().xform(player.global_transform.origin)
	assert_float(local_pos.z).is_equal_approx(-3.7, 0.001)
	assert_bool(zone._has_triggered).is_false()

func test_world_rotator_ignores_airlock_suspended_player_for_continuous_tracking() -> void:
	var rotator = auto_free(WorldRotatorScript.new())
	add_child(rotator)

	var player = auto_free(FakePlayer.new())
	add_child(player)
	player.set_meta("airlock_tracking_suspended", true)

	assert_object(rotator._get_tracking_target()).is_null()
