extends GdUnitTestSuite

# Test focalizado de HangarPlatform (FD-289 T3, tracker #319).
# Cubre: contrato (replay_sync + API), estados TOP/DESCENDING/BOTTOM, descenso
# determinista hasta el fondo, snapshot roundtrip y roundtrip antes de _ready.

const PlatformScene = preload("res://core_v2/props/hangar/HangarPlatform.tscn")

func _spawn_platform() -> Node:
	var host: Spatial = auto_free(Spatial.new())
	host.name = "HangarPlatformTestHost"
	add_child(host)
	var platform: Node = PlatformScene.instance()
	host.add_child(platform)
	return platform

func test_contract_and_initial_state() -> void:
	var platform = _spawn_platform()
	yield(get_tree(), "idle_frame")

	assert_bool(platform.is_in_group("replay_sync")).is_true()
	assert_bool(platform.has_method("descend")).is_true()
	assert_bool(platform.has_method("activate")).is_true()
	assert_bool(platform.has_method("get_snapshot")).is_true()
	assert_bool(platform.has_method("restore_snapshot")).is_true()
	assert_int(platform.state).is_equal(platform.State.TOP)
	assert_float(platform.bottom_height).is_equal(platform.global_transform.origin.y - platform.travel_distance)

func test_descend_reaches_bottom() -> void:
	var platform = _spawn_platform()
	yield(get_tree(), "idle_frame")

	platform.descend()
	platform.set_physics_process(false) # aislar: el test integra con step()
	assert_int(platform.state).is_equal(platform.State.DESCENDING)

	var guard := 0
	while platform.state == platform.State.DESCENDING and guard < 100000:
		platform.step(0.05)
		guard += 1

	assert_int(platform.state).is_equal(platform.State.BOTTOM)
	assert_int(guard).is_less(100000)
	assert_float(platform.global_transform.origin.y).is_equal(platform.bottom_height)
	assert_float(platform.current_velocity_y).is_equal(0.0)

func test_two_platforms_descend_identically() -> void:
	var a = _spawn_platform()
	var b = _spawn_platform()
	yield(get_tree(), "idle_frame")

	a.descend()
	b.descend()
	a.set_physics_process(false)
	b.set_physics_process(false)
	for _i in range(50):
		a.step(0.05)
		b.step(0.05)

	assert_float(a.global_transform.origin.y).is_equal(b.global_transform.origin.y)
	assert_float(a.current_velocity_y).is_equal(b.current_velocity_y)

func test_snapshot_roundtrip_preserves_descent_state() -> void:
	var a = _spawn_platform()
	yield(get_tree(), "idle_frame")

	a.descend()
	a.set_physics_process(false)
	for _i in range(25):
		a.step(0.05)
	var snapshot = a.get_snapshot()

	var b = _spawn_platform()
	yield(get_tree(), "idle_frame")
	b.restore_snapshot(snapshot)

	assert_int(b.state).is_equal(a.state)
	assert_float(b.global_transform.origin.y).is_equal(a.global_transform.origin.y)
	assert_float(b.current_velocity_y).is_equal(a.current_velocity_y)
	assert_bool(b.is_in_group("replay_sync")).is_true()

func test_restore_before_ready_is_deferred() -> void:
	var platform: Node = PlatformScene.instance()
	var snapshot := {
		"state": 1,
		"position": [0.0, -3.0, 0.0],
		"top_height": 0.0,
		"bottom_height": -12.0,
		"current_velocity_y": 1.2,
		"travel_distance": 12.0,
		"speed": 1.6,
		"acceleration": 2.5,
		"deceleration": 2.5,
		"auto_descend_on_player": true,
		"debug_passengers": false
	}
	platform.restore_snapshot(snapshot)
	var host: Spatial = auto_free(Spatial.new())
	add_child(host)
	host.add_child(platform)
	# El snapshot se aplico en _ready (deferido); congelar para que un tick de fisica
	# del motor no avance el descenso antes de comprobar la pose restaurada.
	platform.set_physics_process(false)
	yield(get_tree(), "idle_frame")

	assert_int(platform.state).is_equal(platform.State.DESCENDING)
	assert_float(platform.global_transform.origin.y).is_equal(-3.0)
	assert_float(platform.current_velocity_y).is_equal(1.2)
