extends GdUnitTestSuite

const GasParticleManagerScript = preload("res://core_v2/systems/gas/GasParticleManager.gd")
const STEP := 1.0 / 60.0

func test_cpu_lod_replaces_multimesh_and_keeps_pool() -> void:
	var manager = auto_free(GasParticleManagerScript.new())
	manager.distance_lod_enabled = false
	manager.lod_cpu_enabled = true
	manager.collide_with_world = false
	add_child(manager)
	var index: int = manager.emit_particle(Vector3.ZERO, Vector3(0.0, 2.0, 0.5))
	assert_int(index).is_greater_equal(0)
	assert_bool(manager.is_cpu_lod_active()).is_false()
	manager._set_cpu_lod_active(true)
	assert_bool(manager.is_cpu_lod_active()).is_true()
	var cpu: CPUParticles = manager.get_node_or_null("LODParticles")
	assert_object(cpu).is_not_null()
	assert_bool(manager.multimesh_instance.visible).is_false()
	assert_vector3(cpu.direction.normalized()).is_equal_approx(Vector3(0.0, 2.0, 0.5).normalized(), Vector3(0.001, 0.001, 0.001))
	var snapshot: Dictionary = manager.get_snapshot()
	assert_int(snapshot["particles"].size()).is_equal(1)
	manager._set_cpu_lod_active(false)
	assert_bool(manager.is_cpu_lod_active()).is_false()
	assert_bool(manager.multimesh_instance.visible).is_true()
	manager.step(STEP)
	assert_bool(manager.particles[index]["active"]).is_true()


func test_force_cpu_lod_skips_multimesh_step() -> void:
	var manager = auto_free(GasParticleManagerScript.new())
	manager.force_cpu_lod = true
	manager.distance_lod_enabled = false
	manager.collide_with_world = false
	add_child(manager)
	assert_bool(manager.is_cpu_lod_active()).is_true()
	manager.emit_particle(Vector3.ZERO, Vector3.UP)
	manager._physics_process(STEP)
	assert_bool(manager.is_cpu_lod_active()).is_true()
	assert_object(manager.get_node_or_null("LODParticles")).is_not_null()
