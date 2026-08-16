extends GdUnitTestSuite

const GasAreaScript = preload("res://core_v2/systems/gas/GasArea3D.gd")
const FireEmitterScript = preload("res://core_v2/props/emitters/FireEmitter.gd")
const STEP := 1.0 / 60.0

class DummyPlayerBody extends Area:
	func _init() -> void:
		add_to_group("player")

func _make_gas_area(res: int = 8) -> Spatial:
	var gas_area = auto_free(GasAreaScript.new())
	gas_area.grid_resolution = res
	gas_area.initial_particle_count = 32
	add_child(gas_area)
	return gas_area

func _make_fire_emitter() -> Spatial:
	var emitter = auto_free(FireEmitterScript.new())
	emitter.tick_interval = 0.2
	emitter.damage_per_tick = 10.0
	emitter.particles_per_second = 20
	emitter.is_active = true

	var manager = emitter.get_node_or_null("GasParticleManager")
	if manager == null:
		var manager_script = preload("res://core_v2/systems/gas/GasParticleManager.gd")
		manager = manager_script.new()
		manager.name = "GasParticleManager"
		emitter.add_child(manager)

	add_child(emitter)
	return emitter

# --- GasArea3D Tests ---

func test_gas_area_group_membership() -> void:
	var gas_area = _make_gas_area()
	assert_bool(gas_area.is_in_group("replay_sync")).is_true()

func test_gas_area_snapshot_and_restore_densities() -> void:
	var gas_area = _make_gas_area(8)
	if gas_area.manager:
		for i in range(16):
			gas_area.manager.emit_particle(Vector3(i * 0.1, 0.0, i * 0.1))

	for _i in range(10):
		gas_area._physics_process(STEP)
		if gas_area.manager:
			gas_area.manager._physics_process(STEP)

	var snapshot: Dictionary = gas_area.get_snapshot()
	assert_bool(snapshot.has("grid")).is_true()
	assert_bool(snapshot.has("grid_resolution")).is_true()

	var initial_densities := []
	for cell in snapshot["grid"]:
		initial_densities.append(float(cell["density"]))

	for _i in range(20):
		gas_area._physics_process(STEP)
		if gas_area.manager:
			gas_area.manager._physics_process(STEP)

	gas_area.restore_snapshot(snapshot)

	var restored_snapshot: Dictionary = gas_area.get_snapshot()
	var restored_grid: Array = restored_snapshot["grid"]
	assert_int(restored_grid.size()).is_equal(initial_densities.size())

	for i in range(initial_densities.size()):
		assert_float(float(restored_grid[i]["density"])).is_equal_approx(initial_densities[i], 0.0001)

func test_gas_area_restore_tolerance_grid_resolution_mismatch() -> void:
	var gas_area = _make_gas_area(8)
	var snapshot: Dictionary = gas_area.get_snapshot()

	snapshot["grid_resolution"] = 16

	gas_area.restore_snapshot(snapshot)
	assert_int(gas_area.grid_resolution).is_equal(8)

# --- FireEmitter Tests ---

func test_fire_emitter_damage_is_physics_tick_dependent_not_process() -> void:
	var emitter = _make_fire_emitter()
	var player = auto_free(DummyPlayerBody.new())
	add_child(player)

	var damage_ticks_a := [0]
	emitter.connect("damage_tick", self, "_on_damage_tick", [damage_ticks_a])

	emitter._on_body_entered(player)
	for _i in range(60):
		emitter._physics_process(STEP)

	var count_without_process: int = damage_ticks_a[0]
	assert_int(count_without_process).is_greater(0)

	var emitter_b = _make_fire_emitter()
	var player_b = auto_free(DummyPlayerBody.new())
	add_child(player_b)

	var damage_ticks_b := [0]
	emitter_b.connect("damage_tick", self, "_on_damage_tick", [damage_ticks_b])

	emitter_b._on_body_entered(player_b)
	for _i in range(60):
		emitter_b._physics_process(STEP)

	var count_with_process: int = damage_ticks_b[0]
	assert_int(count_with_process).is_equal(count_without_process)

func test_fire_emitter_snapshot_roundtrip() -> void:
	var emitter = _make_fire_emitter()
	var player = auto_free(DummyPlayerBody.new())
	add_child(player)

	emitter._on_body_entered(player)
	for _i in range(15):
		emitter._physics_process(STEP)

	var snapshot: Dictionary = emitter.get_snapshot()
	var tick_timer_orig: float = snapshot["tick_timer"]
	var spawn_timer_orig: float = snapshot["spawn_timer"]
	var emit_counter_orig: int = snapshot["emit_counter"]

	for _i in range(30):
		emitter._physics_process(STEP)

	emitter.restore_snapshot(snapshot)
	var restored_snap: Dictionary = emitter.get_snapshot()

	assert_float(float(restored_snap["tick_timer"])).is_equal_approx(tick_timer_orig, 0.0001)
	assert_float(float(restored_snap["spawn_timer"])).is_equal_approx(spawn_timer_orig, 0.0001)
	assert_int(int(restored_snap["emit_counter"])).is_equal(emit_counter_orig)

func _on_damage_tick(_damage: float, sink: Array) -> void:
	sink[0] += 1
