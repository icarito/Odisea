extends GdUnitTestSuite

const FireEmitterScript = preload("res://core_v2/props/emitters/FireEmitter.gd")
const GasParticleManagerScript = preload("res://core_v2/systems/gas/GasParticleManager.gd")
const STEP := 1.0 / 60.0

func _make_fire_emitter(jet_vel: Vector3 = Vector3.ZERO) -> Spatial:
	var emitter = auto_free(FireEmitterScript.new())
	emitter.tick_interval = 0.2
	emitter.damage_per_tick = 10.0
	emitter.particles_per_second = 20
	emitter.jet_velocity = jet_vel
	emitter.is_active = true

	var manager = emitter.get_node_or_null("GasParticleManager")
	if manager == null:
		manager = auto_free(GasParticleManagerScript.new())
		manager.name = "GasParticleManager"
		emitter.add_child(manager)

	add_child(emitter)
	return emitter

func test_default_jet_velocity_is_zero() -> void:
	var emitter = _make_fire_emitter()
	assert_vector3(emitter.jet_velocity).is_equal(Vector3.ZERO)

	emitter._spawn_flame_particle()

	var manager: GasParticleManager = emitter.get_node_or_null("GasParticleManager")
	assert_object(manager).is_not_null()

	var active_indices: Array = manager.get_active_particle_indices()
	assert_int(active_indices.size()).is_equal(1)

	var particle: Dictionary = manager.particles[active_indices[0]]
	assert_vector3(particle["velocity"]).is_equal(Vector3.ZERO)

func test_directional_jet_velocity() -> void:
	var target_vel := Vector3(0.0, 0.0, -8.0)
	var emitter = _make_fire_emitter(target_vel)
	assert_vector3(emitter.jet_velocity).is_equal(target_vel)

	emitter._spawn_flame_particle()

	var manager: GasParticleManager = emitter.get_node_or_null("GasParticleManager")
	assert_object(manager).is_not_null()

	var active_indices: Array = manager.get_active_particle_indices()
	assert_int(active_indices.size()).is_equal(1)

	var particle: Dictionary = manager.particles[active_indices[0]]
	assert_vector3(particle["velocity"]).is_equal(target_vel)

func test_jet_velocity_determinism_and_snapshot_restore() -> void:
	var target_vel := Vector3(0.0, 2.0, -8.0)
	var emitter_a = _make_fire_emitter(target_vel)
	var manager_a: GasParticleManager = emitter_a.get_node_or_null("GasParticleManager")

	var emitter_b = _make_fire_emitter(target_vel)
	var manager_b: GasParticleManager = emitter_b.get_node_or_null("GasParticleManager")

	# Run both for 15 ticks
	for _i in range(15):
		emitter_a._physics_process(STEP)
		manager_a._physics_process(STEP)

		emitter_b._physics_process(STEP)
		manager_b._physics_process(STEP)

	# Take snapshot of emitter A
	var snap_a: Dictionary = emitter_a.get_snapshot()

	# Run both for 20 more ticks
	for _i in range(20):
		emitter_a._physics_process(STEP)
		manager_a._physics_process(STEP)

		emitter_b._physics_process(STEP)
		manager_b._physics_process(STEP)

	# Assert emitter A and B match without restore
	var indices_a: Array = manager_a.get_active_particle_indices()
	var indices_b: Array = manager_b.get_active_particle_indices()
	assert_int(indices_a.size()).is_equal(indices_b.size())

	for i in range(indices_a.size()):
		var idx_a: int = indices_a[i]
		var idx_b: int = indices_b[i]
		var p_a: Dictionary = manager_a.particles[idx_a]
		var p_b: Dictionary = manager_b.particles[idx_b]
		assert_vector3(p_a["position"]).is_equal_approx(p_b["position"], Vector3(0.0001, 0.0001, 0.0001))
		assert_vector3(p_a["velocity"]).is_equal_approx(p_b["velocity"], Vector3(0.0001, 0.0001, 0.0001))

	# Restore snapshot on B and run 20 ticks again
	emitter_b.restore_snapshot(snap_a)

	for _i in range(20):
		emitter_b._physics_process(STEP)
		manager_b._physics_process(STEP)

	indices_a = manager_a.get_active_particle_indices()
	indices_b = manager_b.get_active_particle_indices()
	assert_int(indices_a.size()).is_equal(indices_b.size())

	for i in range(indices_a.size()):
		var idx_a: int = indices_a[i]
		var idx_b: int = indices_b[i]
		var p_a: Dictionary = manager_a.particles[idx_a]
		var p_b: Dictionary = manager_b.particles[idx_b]
		assert_vector3(p_a["position"]).is_equal_approx(p_b["position"], Vector3(0.0001, 0.0001, 0.0001))
		assert_vector3(p_a["velocity"]).is_equal_approx(p_b["velocity"], Vector3(0.0001, 0.0001, 0.0001))
