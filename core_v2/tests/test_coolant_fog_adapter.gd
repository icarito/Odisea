extends GdUnitTestSuite

# TestSuite for CoolantFogAdapter (FD-255 J7 / FD-256)

const CoolantLeakScript = preload("res://core_v2/systems/cryo/CoolantLeak.gd")
const GasAreaScript = preload("res://core_v2/systems/gas/GasArea3D.gd")
const CoolantFogAdapterScript = preload("res://core_v2/systems/cryo/CoolantFogAdapter.gd")
const STEP := 1.0 / 60.0


func _make_setup(particles_at_full: int = 60) -> Dictionary:
	var leak = auto_free(CoolantLeakScript.new())
	leak.warning_duration = 0.2
	leak.ramp_up_duration = 1.0
	leak.dissipate_duration = 1.0
	add_child(leak)

	var gas = auto_free(GasAreaScript.new())
	gas.initial_particle_count = 0
	gas.damage_per_second = 20.0
	add_child(gas)

	var adapter = auto_free(CoolantFogAdapterScript.new())
	adapter.particles_at_full = particles_at_full
	adapter.leak_path = leak.get_path()
	adapter.gas_path = gas.get_path()
	add_child(adapter)

	return {
		"leak": leak,
		"gas": gas,
		"adapter": adapter
	}


func _step_setup(setup: Dictionary, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		setup["leak"]._physics_process(STEP)
		setup["adapter"]._physics_process(STEP)
		setup["gas"]._physics_process(STEP)
		if setup["gas"].manager:
			setup["gas"].manager._physics_process(STEP)


func test_gas_damage_is_enforced_zero() -> void:
	var setup := _make_setup()
	var gas: Spatial = setup["gas"]

	assert_float(gas.damage_per_second).is_equal(0.0)

	gas.damage_per_second = 50.0
	_step_setup(setup, STEP)

	assert_float(gas.damage_per_second).is_equal(0.0)


func test_particle_count_grows_with_leak_and_clears_when_sealed() -> void:
	var setup := _make_setup(60)
	var leak: Spatial = setup["leak"]
	var gas: Spatial = setup["gas"]

	assert_int(gas.manager.get_active_particle_indices().size()).is_equal(0)

	leak.trigger_leak()
	_step_setup(setup, leak.warning_duration + 0.1)

	# Ramp up phase
	_step_setup(setup, 0.5)
	var midway_count: int = gas.manager.get_active_particle_indices().size()
	assert_int(midway_count).is_greater(10)
	assert_int(midway_count).is_less(60)

	# Full ramp up
	_step_setup(setup, 0.8)
	var full_count: int = gas.manager.get_active_particle_indices().size()
	assert_int(full_count).is_equal(60)

	# Seal leak
	leak.seal()
	_step_setup(setup, leak.dissipate_duration + 0.2)

	assert_int(gas.manager.get_active_particle_indices().size()).is_equal(0)


func test_determinism_identical_runs_produce_exact_particle_positions() -> void:
	var setup_a := _make_setup(40)
	var setup_b := _make_setup(40)

	setup_a["leak"].trigger_leak()
	setup_b["leak"].trigger_leak()

	_step_setup(setup_a, 0.8)
	_step_setup(setup_b, 0.8)

	var indices_a: Array = setup_a["gas"].manager.get_active_particle_indices()
	var indices_b: Array = setup_b["gas"].manager.get_active_particle_indices()

	assert_int(indices_a.size()).is_equal(indices_b.size())

	for i in range(indices_a.size()):
		var idx_a: int = indices_a[i]
		var idx_b: int = indices_b[i]
		assert_int(idx_a).is_equal(idx_b)

		var pos_a: Vector3 = setup_a["gas"].manager.get_particle_world_position(idx_a)
		var pos_b: Vector3 = setup_b["gas"].manager.get_particle_world_position(idx_b)

		assert_float(pos_a.x).is_equal_approx(pos_b.x, 0.0001)
		assert_float(pos_a.y).is_equal_approx(pos_b.y, 0.0001)
		assert_float(pos_a.z).is_equal_approx(pos_b.z, 0.0001)


func test_snapshot_restore_reproduces_exact_state() -> void:
	var setup := _make_setup(50)
	var leak: Spatial = setup["leak"]
	var gas: Spatial = setup["gas"]
	var adapter: Spatial = setup["adapter"]

	leak.trigger_leak()
	_step_setup(setup, leak.warning_duration + 0.4)

	var snap_leak: Dictionary = leak.get_snapshot()
	var snap_adapter: Dictionary = adapter.get_snapshot()
	var snap_gas: Dictionary = gas.get_snapshot()
	var snap_manager: Dictionary = gas.manager.get_snapshot()

	var active_indices_orig: Array = gas.manager.get_active_particle_indices()
	var count_orig: int = active_indices_orig.size()
	assert_int(count_orig).is_greater(10)

	# Advance 30 physics steps
	_step_setup(setup, STEP * 30.0)
	var count_advanced: int = gas.manager.get_active_particle_indices().size()

	# Restore snapshot
	leak.restore_snapshot(snap_leak)
	adapter.restore_snapshot(snap_adapter)
	gas.restore_snapshot(snap_gas)
	gas.manager.restore_snapshot(snap_manager)

	assert_int(gas.manager.get_active_particle_indices().size()).is_equal(count_orig)

	# Advance 30 physics steps again
	_step_setup(setup, STEP * 30.0)

	assert_int(gas.manager.get_active_particle_indices().size()).is_equal(count_advanced)
