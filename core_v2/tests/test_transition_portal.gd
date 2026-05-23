extends GdUnitTestSuite

const TransitionPortalScript = preload("res://core_v2/components/TransitionPortal.gd")
const AirlockControllerScript = preload("res://core_v2/components/AirlockControllerV2.gd")

class FakeInputProvider:
	extends Reference
	var hardware_input_enabled := true

class FakePlayer:
	extends KinematicBody
	var input_provider = FakeInputProvider.new()
	var is_replay_mode := false

	func _init() -> void:
		add_to_group("player")

	func get_full_snapshot() -> Dictionary:
		return {
			"position": [1.0, 2.0, 3.0],
			"velocity": [0.0, 0.0, 0.0],
			"controller_mode": 1,
			"gravity_mode": 2
		}

class FakeMovingPlayer:
	extends KinematicBody
	var velocity := Vector3.ZERO

	func _init() -> void:
		add_to_group("player")

class FakeDoor:
	extends Node
	var is_active := false
	var immediate_used := false

	func set_active(value: bool, immediate: bool = false) -> void:
		is_active = value
		immediate_used = immediate

func test_transition_portal_scene_loads() -> void:
	var scene: PackedScene = load("res://core_v2/components/TransitionPortal.tscn")
	assert_object(scene).is_not_null()
	var portal = auto_free(scene.instance())
	assert_object(portal).is_not_null()
	assert_bool(portal is Area).is_true()

func test_vertical_transition_scenes_load() -> void:
	assert_object(load("res://core_v2/levels/Interior_A.tscn")).is_not_null()
	assert_object(load("res://core_v2/levels/Terrace_A.tscn")).is_not_null()
	assert_object(load("res://core_v2/props/AirlockContainerChamber.tscn")).is_not_null()

func test_transition_params_include_spawn_snapshot_and_restore_input_state() -> void:
	var portal = auto_free(TransitionPortalScript.new())
	add_child(portal)
	portal.target_scene = "res://core_v2/levels/Terrace_A.tscn"
	portal.target_spawn_id = "from_interior_a"
	portal.transition_style = "airlock"
	portal.fade_out = 0.25
	portal.fade_in = 0.35

	var player = auto_free(FakePlayer.new())
	add_child(player)
	portal._capture_and_disable_input(player)
	var params: Dictionary = portal._build_transition_params(player)

	assert_str(params["target_spawn_id"]).is_equal("from_interior_a")
	assert_str(params["transition"]).is_equal("fade")
	assert_float(params["fade_out"]).is_equal(0.25)
	assert_float(params["fade_in"]).is_equal(0.35)
	assert_bool(params["preserve_player_state"]).is_true()
	assert_bool(params["input_restore_state"]["hardware_input_enabled"]).is_true()
	assert_bool(player.input_provider.hardware_input_enabled).is_false()
	assert_bool(params["state_data"].has("player_snapshot")).is_true()
	assert_int(params["state_data"]["gravity_mode"]).is_equal(2)
	assert_int(params["state_data"]["controller_mode"]).is_equal(1)

func test_transition_portal_direction_gate_uses_velocity() -> void:
	var portal = auto_free(TransitionPortalScript.new())
	add_child(portal)
	portal.required_entry_direction = Vector3(0, 0, -1)
	portal.min_entry_alignment = 0.25

	var player = auto_free(FakeMovingPlayer.new())
	add_child(player)

	player.velocity = Vector3(0, 0, -2)
	assert_bool(portal._passes_entry_direction(player)).is_true()

	player.velocity = Vector3(0, 0, 2)
	assert_bool(portal._passes_entry_direction(player)).is_false()

	player.velocity = Vector3.ZERO
	assert_bool(portal._passes_entry_direction(player)).is_false()

func test_transition_portal_preload_does_not_disable_input() -> void:
	var portal = auto_free(TransitionPortalScript.new())
	add_child(portal)
	portal.target_scene = "res://core_v2/levels/Terrace_A.tscn"

	var player = auto_free(FakePlayer.new())
	add_child(player)

	assert_bool(portal._begin_preload(player)).is_true()
	assert_bool(player.input_provider.hardware_input_enabled).is_true()

func test_transition_params_include_airlock_relative_frame() -> void:
	var airlock = auto_free(AirlockControllerScript.new())
	add_child(airlock)
	airlock.global_transform.origin = Vector3(10, 0, 0)

	var portal = TransitionPortalScript.new()
	airlock.add_child(portal)
	portal.target_airlock_path = NodePath("TerraceAirlock")
	portal.target_airlock_exit_door = "outer"

	var player = auto_free(FakeMovingPlayer.new())
	add_child(player)
	player.global_transform.origin = Vector3(10, 1, -1.25)
	player.velocity = Vector3(0, 0, -2)

	var state_data: Dictionary = portal._build_state_data(player)

	assert_bool(state_data.has("airlock_relative_transform")).is_true()
	assert_str(state_data["target_airlock_path"]).is_equal("TerraceAirlock")
	assert_str(state_data["target_airlock_exit_door"]).is_equal("outer")
	assert_vector3(state_data["airlock_relative_transform"].origin).is_equal(Vector3(0, 1, -1.25))
	assert_vector3(state_data["airlock_relative_velocity"]).is_equal(Vector3(0, 0, -2))

func test_airlock_start_cycle_reaches_ready_state() -> void:
	var airlock = auto_free(AirlockControllerScript.new())
	add_child(airlock)
	airlock.pressurize_time = 0.0
	airlock.reset_time = 1.0

	assert_bool(airlock.start_cycle(true)).is_true()
	assert_bool(airlock.is_airlock_ready()).is_true()
	assert_int(airlock.state).is_equal(3)

func test_airlock_open_exit_door_opens_selected_side() -> void:
	var airlock = auto_free(AirlockControllerScript.new())
	var outer = FakeDoor.new()
	var inner = FakeDoor.new()
	outer.name = "OuterDoor"
	inner.name = "InnerDoor"
	airlock.add_child(outer)
	airlock.add_child(inner)
	add_child(airlock)
	airlock.outer_door_path = NodePath("OuterDoor")
	airlock.inner_door_path = NodePath("InnerDoor")
	airlock._ready()

	assert_bool(airlock.open_exit_door("outer", true)).is_true()
	assert_bool(outer.is_active).is_true()
	assert_bool(inner.is_active).is_false()
	assert_bool(outer.immediate_used).is_true()
	assert_bool(airlock.is_airlock_ready()).is_true()
