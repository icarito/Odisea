extends GdUnitTestSuite

# Test contract class with custom method set_flicker_multiplier
class MethodTarget:
	extends Node
	var last_multiplier: float = -1.0
	var is_active: bool = true
	func set_flicker_multiplier(f: float) -> void:
		last_multiplier = f

class SpatialLightTarget:
	extends Spatial
	var omni: OmniLight
	var mesh: MeshInstance
	var is_active: bool = true

	func _init():
		omni = OmniLight.new()
		omni.light_energy = 2.0
		add_child(omni)

		mesh = MeshInstance.new()
		var mat := SpatialMaterial.new()
		mat.emission_enabled = true
		mat.emission_energy = 3.0
		mesh.material_override = mat
		add_child(mesh)

func test_seed_reproducibility():
	var flicker1 := LightFlicker.new()
	flicker1.seed = 12345
	flicker1.period = 0.8
	flicker1.on_ratio = 0.75

	var flicker2 := LightFlicker.new()
	flicker2.seed = 12345
	flicker2.period = 0.8
	flicker2.on_ratio = 0.75

	var flicker_diff := LightFlicker.new()
	flicker_diff.seed = 99999
	flicker_diff.period = 0.8
	flicker_diff.on_ratio = 0.75

	auto_free(flicker1)
	auto_free(flicker2)
	auto_free(flicker_diff)

	var sequence1: Array = []
	var sequence2: Array = []
	var sequence_diff: Array = []

	var t: float = 0.0
	for _i in range(20):
		sequence1.append(flicker1.calculate_factor(t))
		sequence2.append(flicker2.calculate_factor(t))
		sequence_diff.append(flicker_diff.calculate_factor(t))
		t += 0.1

	assert_array(sequence1).is_equal(sequence2)
	assert_array(sequence1).is_not_equal(sequence_diff)

func test_snapshot_restore_roundtrip():
	var flicker := auto_free(LightFlicker.new())
	flicker.seed = 42
	flicker.period = 1.0

	var target := auto_free(MethodTarget.new())
	add_child(target)
	add_child(flicker)
	flicker.target_path = flicker.get_path_to(target)

	flicker.step(0.5)
	var factor_mid = target.last_multiplier
	assert_float(factor_mid).is_greater_equal(0.0)

	var snapshot = flicker.get_snapshot()
	assert_dict(snapshot).has_key("time_acc")
	assert_dict(snapshot).has_key("seed")
	assert_int(snapshot["seed"]).is_equal(42)

	# Advance time further
	flicker.step(1.5)
	var factor_later = target.last_multiplier

	# Restore snapshot
	flicker.restore_snapshot(snapshot)
	var factor_restored = target.last_multiplier

	assert_float(factor_restored).is_equal(factor_mid)

func test_target_method_contract_modulation():
	var flicker := auto_free(LightFlicker.new())
	var target := auto_free(MethodTarget.new())
	add_child(target)
	add_child(flicker)
	flicker.target_path = flicker.get_path_to(target)

	flicker.step(0.2)
	assert_float(target.last_multiplier).is_greater_equal(0.0)

func test_light_energy_and_material_emission_modulation():
	var flicker := auto_free(LightFlicker.new())
	flicker.seed = 777
	flicker.base_intensity = 1.5

	var target := auto_free(SpatialLightTarget.new())
	add_child(target)
	add_child(flicker)
	flicker.target_path = flicker.get_path_to(target)
	yield(get_tree(), "idle_frame")

	flicker.step(0.1)

	var omni: OmniLight = target.omni
	var mat: SpatialMaterial = target.mesh.material_override

	assert_object(omni).is_not_null()
	assert_object(mat).is_not_null()

	# Base energy was 2.0, emission was 3.0
	# Factor will scale both proportionally
	var factor = flicker.calculate_factor(0.1)
	assert_float(omni.light_energy).is_equal_approx(2.0 * factor, 0.001)
	assert_float(mat.emission_energy).is_equal_approx(3.0 * factor, 0.001)

func test_only_when_active_culling_restores_base_values():
	var flicker := auto_free(LightFlicker.new())
	flicker.only_when_active = true

	var target := auto_free(SpatialLightTarget.new())
	add_child(target)
	add_child(flicker)
	flicker.target_path = flicker.get_path_to(target)
	yield(get_tree(), "idle_frame")

	# Step while active
	target.is_active = true
	flicker.step(0.3)

	# Set target inactive
	target.is_active = false
	flicker.step(0.1)

	# Base values should be restored
	assert_float(target.omni.light_energy).is_equal_approx(2.0, 0.001)
	assert_float(target.mesh.material_override.emission_energy).is_equal_approx(3.0, 0.001)
