# test_coolant_lab.gd - GdUnit3 test suite for CoolantLab.tscn (FD-265)
# Validates scene setup, OCLS graph topology, flow control, manometer readings, patch mechanics, and win condition.

extends GdUnitTestSuite

const COOLANT_LAB_SCENE = "res://core_v2/scenes/CoolantLab.tscn"

var _runner: GdUnitSceneRunner = null


func before_test() -> void:
	_runner = auto_free(scene_runner(COOLANT_LAB_SCENE))


func test_coolant_lab_initial_state() -> void:
	yield(_runner.simulate_frames(5), "completed")
	var lab = _runner.scene()
	assert_object(lab).is_not_null()

	var adapter_west = lab.get_node("CoolantFlowAdapterWest")
	var adapter_east = lab.get_node("CoolantFlowAdapterEast")
	assert_object(adapter_west).is_not_null()
	assert_object(adapter_east).is_not_null()

	# Initially valves are open, tanks have coolant -> flow is active on both branches
	assert_bool(adapter_west.is_flow_active()).is_true()
	assert_bool(adapter_east.is_flow_active()).is_true()

	# Both leaks start active -> patch points are unpatched initially
	var patch_west = lab.get_node("LeakWest_Patch")
	var patch_east = lab.get_node("LeakEast_Patch")
	assert_bool(patch_west.is_patched()).is_false()
	assert_bool(patch_east.is_patched()).is_false()

	# System is not stabilized initially due to active leaks
	assert_bool(lab.is_stabilized()).is_false()


func test_valve_interactivity_stops_branch_flow() -> void:
	yield(_runner.simulate_frames(5), "completed")
	var lab = _runner.scene()
	var valve_west_1 = lab.get_node("ValveWest_1")
	var adapter_west = lab.get_node("CoolantFlowAdapterWest")
	var manometer_west = lab.get_node("ManometerWest")

	var initial_pressure: float = manometer_west.get_pressure()
	assert_float(initial_pressure).is_greater(0.0)

	# Close ValveWest_1 via interact()
	valve_west_1.interact()
	yield(_runner.simulate_frames(5), "completed")

	# West flow should now be stopped and pressure reduced
	assert_bool(adapter_west.is_flow_active()).is_false()
	assert_float(manometer_west.get_pressure()).is_less(initial_pressure)

	# Re-open ValveWest_1
	valve_west_1.interact()
	yield(_runner.simulate_frames(5), "completed")

	# West flow active again
	assert_bool(adapter_west.is_flow_active()).is_true()


func test_patching_fissures_stabilizes_lab() -> void:
	yield(_runner.simulate_frames(5), "completed")
	var lab = _runner.scene()
	var patch_west = lab.get_node("LeakWest_Patch")
	var patch_east = lab.get_node("LeakEast_Patch")

	# Patch West leak
	assert_bool(patch_west.patch_with_gloo()).is_true()
	yield(_runner.simulate_frames(5), "completed")

	assert_bool(lab.is_stabilized()).is_false() # East still unpatched

	# Patch East leak
	assert_bool(patch_east.patch_with_gloo()).is_true()
	yield(_runner.simulate_frames(5), "completed")

	# System should now be stabilized
	assert_bool(lab.is_stabilized()).is_true()

	var status_label = lab.get_node("UI/Control/StatusLabel")
	assert_str(status_label.text).is_equal("SISTEMA ESTABILIZADO")


func test_snapshot_determinism() -> void:
	yield(_runner.simulate_frames(5), "completed")
	var lab = _runner.scene()
	var patch_west = lab.get_node("LeakWest_Patch")
	patch_west.patch_with_gloo()
	yield(_runner.simulate_frames(10), "completed")

	var adapter_west = lab.get_node("CoolantFlowAdapterWest")
	var snap_1: Dictionary = adapter_west.get_snapshot()

	yield(_runner.simulate_frames(20), "completed")

	adapter_west.restore_snapshot(snap_1)
	var snap_2: Dictionary = adapter_west.get_snapshot()

	assert_dict(snap_1).is_equal(snap_2)
