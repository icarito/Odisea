extends GdUnitTestSuite

# test_coolant_puzzle_loop.gd - GdUnit3 test suite for FD-266 coolant puzzle semantics.
# Verifies depressurization, leak-driven tank drain, provisional vs firm gloo patching,
# laboratory stabilization, and snapshot/restore determinism.

const CoolantLeakScript = preload("res://core_v2/systems/cryo/CoolantLeak.gd")
const CoolantTankScript = preload("res://core_v2/props/pipe/CoolantTank.gd")
const CoolantFlowAdapterScript = preload("res://core_v2/systems/cryo/CoolantFlowAdapter.gd")
const LeakPatchPointScript = preload("res://core_v2/systems/cryo/LeakPatchPoint.gd")
const PipeValveScript = preload("res://core_v2/props/pipe/PipeValve.gd")
const PipeManometerScript = preload("res://core_v2/props/pipe/PipeManometer.gd")
const CoolantLabScript = preload("res://core_v2/scenes/CoolantLab.gd")

const STEP := 1.0 / 60.0


func _step_tree(nodes: Array, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		for node in nodes:
			if is_instance_valid(node) and node.has_method("_physics_process"):
				node._physics_process(STEP)


# 1. Closing valve dissipates leak intensity to 0 without SEALED; reopening returns to LEAKING without WARNING
func test_valve_depressurizes_without_sealing() -> void:
	var valve = auto_free(PipeValveScript.new())
	valve.starts_active = true
	valve.is_active = true
	add_child(valve)

	var leak = auto_free(CoolantLeakScript.new())
	leak.warning_duration = 0.1
	leak.ramp_up_duration = 0.2
	leak.dissipate_duration = 0.3
	leak.valve_path = valve.get_path()
	add_child(leak)

	_step_tree([valve, leak], 0.05)
	leak.trigger_leak()
	_step_tree([valve, leak], 0.4)

	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)
	assert_float(leak.get_leak_intensity()).is_equal_approx(1.0, 0.01)

	# Close valve -> transitions to DEPRESSURIZED
	valve.is_active = false
	valve.emit_signal("valve_state_changed", false)
	_step_tree([valve, leak], 0.05)

	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.DEPRESSURIZED)
	assert_bool(leak.is_depressurized()).is_true()

	_step_tree([valve, leak], 0.4)
	assert_float(leak.get_leak_intensity()).is_equal(0.0)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.DEPRESSURIZED)

	# Re-open valve -> returns directly to LEAKING
	var warning_count := [0]
	leak.connect("warning_started", self, "_count_event", [warning_count])

	valve.is_active = true
	valve.emit_signal("valve_state_changed", true)
	_step_tree([valve, leak], 0.05)

	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)
	assert_int(warning_count[0]).is_equal(0) # Bypassed WARNING phase


# 2. Tank drains only while leaks are active/pressurized; closing valve stops draining
func test_tank_drains_only_on_active_pressurized_leaks() -> void:
	var tank = auto_free(CoolantTankScript.new())
	tank.tank_level = 1.0
	tank.drain_rate = 0.1
	add_child(tank)

	var valve = auto_free(PipeValveScript.new())
	valve.starts_active = true
	valve.is_active = true
	add_child(valve)

	var leak = auto_free(CoolantLeakScript.new())
	leak.warning_duration = 0.01
	leak.ramp_up_duration = 0.01
	leak.dissipate_duration = 0.1
	add_child(leak)

	var adapter = auto_free(CoolantFlowAdapterScript.new())
	adapter.tank_path = tank.get_path()
	adapter.valves = [valve.get_path()]
	adapter.leaks = [leak.get_path()]
	add_child(adapter)

	_step_tree([tank, valve, leak, adapter], 0.05)
	leak.trigger_leak()
	_step_tree([tank, valve, leak, adapter], 0.05)

	var level_1: float = tank.tank_level
	_step_tree([tank, valve, leak, adapter], 1.0)
	var level_2: float = tank.tank_level

	assert_float(level_2).is_less(level_1)

	# Close valve -> leak stops draining tank
	valve.is_active = false
	_step_tree([tank, valve, leak, adapter], 0.2)
	var level_3: float = tank.tank_level

	_step_tree([tank, valve, leak, adapter], 1.0)
	var level_4: float = tank.tank_level

	assert_float(level_4).is_equal_approx(level_3, 0.001)


# 3. Gloo on pressurized section forms provisional patch that expires
func test_gloo_on_pressurized_run_expires() -> void:
	var tank = auto_free(CoolantTankScript.new())
	tank.tank_level = 1.0
	add_child(tank)

	var valve = auto_free(PipeValveScript.new())
	valve.starts_active = true
	valve.is_active = true
	add_child(valve)

	var leak = auto_free(CoolantLeakScript.new())
	leak.warning_duration = 0.01
	leak.ramp_up_duration = 0.01
	add_child(leak)

	var adapter = auto_free(CoolantFlowAdapterScript.new())
	adapter.tank_path = tank.get_path()
	adapter.valves = [valve.get_path()]
	adapter.leaks = [leak.get_path()]
	add_child(adapter)

	var manometer = auto_free(PipeManometerScript.new())
	manometer.tank_path = tank.get_path()
	manometer.flow_adapter_path = adapter.get_path()
	manometer.leak_path = leak.get_path()
	manometer.max_pressure = 5.0
	add_child(manometer)

	var patch_point = auto_free(LeakPatchPointScript.new())
	patch_point.leak_path = leak.get_path()
	patch_point.manometer_path = manometer.get_path()
	patch_point.gloo_patch_duration = 0.5
	patch_point.firm_patch_pressure_threshold = 0.2
	add_child(patch_point)

	_step_tree([tank, valve, leak, adapter, manometer, patch_point], 0.05)
	leak.trigger_leak()
	_step_tree([tank, valve, leak, adapter, manometer, patch_point], 0.05)

	assert_float(manometer.get_pressure()).is_greater(1.0)

	# Patch under pressure
	patch_point.patch_with_gloo()
	_step_tree([tank, valve, leak, adapter, manometer, patch_point], 0.05)

	assert_bool(patch_point.is_patched()).is_true()
	assert_bool(patch_point.is_firmly_patched()).is_false()

	# Step past duration -> patch expires
	_step_tree([tank, valve, leak, adapter, manometer, patch_point], 0.6)

	assert_bool(patch_point.is_patched()).is_false()
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)


# 4. Gloo on depressurized run forms firm patch; reopening restores flow without leak
func test_gloo_on_depressurized_run_is_firm() -> void:
	var tank = auto_free(CoolantTankScript.new())
	tank.tank_level = 1.0
	add_child(tank)

	var valve = auto_free(PipeValveScript.new())
	valve.starts_active = true
	valve.is_active = true
	add_child(valve)

	var leak = auto_free(CoolantLeakScript.new())
	leak.warning_duration = 0.01
	leak.ramp_up_duration = 0.01
	leak.dissipate_duration = 0.1
	leak.valve_path = valve.get_path()
	add_child(leak)

	var adapter = auto_free(CoolantFlowAdapterScript.new())
	adapter.tank_path = tank.get_path()
	adapter.valves = [valve.get_path()]
	adapter.leaks = [leak.get_path()]
	add_child(adapter)

	var manometer = auto_free(PipeManometerScript.new())
	manometer.tank_path = tank.get_path()
	manometer.flow_adapter_path = adapter.get_path()
	manometer.leak_path = leak.get_path()
	manometer.max_pressure = 5.0
	add_child(manometer)

	var patch_point = auto_free(LeakPatchPointScript.new())
	patch_point.leak_path = leak.get_path()
	patch_point.manometer_path = manometer.get_path()
	patch_point.gloo_patch_duration = 0.3
	patch_point.firm_patch_pressure_threshold = 0.2
	add_child(patch_point)

	_step_tree([tank, valve, leak, adapter, manometer, patch_point], 0.05)
	leak.trigger_leak()
	_step_tree([tank, valve, leak, adapter, manometer, patch_point], 0.05)

	# Close valve to depressurize
	valve.is_active = false
	valve.emit_signal("valve_state_changed", false)
	_step_tree([tank, valve, leak, adapter, manometer, patch_point], 0.2)

	assert_float(manometer.get_pressure()).is_less(0.1)

	# Patch depressurized run -> firm patch
	patch_point.patch_with_gloo()
	_step_tree([tank, valve, leak, adapter, manometer, patch_point], 0.05)

	assert_bool(patch_point.is_firmly_patched()).is_true()

	# Re-open valve -> flow active, no leak, firm patch does not expire
	valve.is_active = true
	valve.emit_signal("valve_state_changed", true)
	_step_tree([tank, valve, leak, adapter, manometer, patch_point], 0.5)

	assert_bool(patch_point.is_firmly_patched()).is_true()
	assert_bool(adapter.is_flow_active()).is_true()
	assert_float(leak.get_leak_intensity()).is_equal(0.0)


# 5. Full puzzle loop in both branches stabilizes lab permanently
func test_full_lab_puzzle_loop_stabilizes_permanently() -> void:
	var lab = auto_free(CoolantLabScript.new())
	var adapter_w = auto_free(CoolantFlowAdapterScript.new())
	var adapter_e = auto_free(CoolantFlowAdapterScript.new())
	var patch_w = auto_free(LeakPatchPointScript.new())
	var patch_e = auto_free(LeakPatchPointScript.new())
	var man_w = auto_free(PipeManometerScript.new())
	var man_e = auto_free(PipeManometerScript.new())

	add_child(lab)
	add_child(adapter_w)
	add_child(adapter_e)
	add_child(patch_w)
	add_child(patch_e)
	add_child(man_w)
	add_child(man_e)

	lab.flow_adapter_west_path = adapter_w.get_path()
	lab.flow_adapter_east_path = adapter_e.get_path()
	lab.leak_west_patch_path = patch_w.get_path()
	lab.leak_east_patch_path = patch_e.get_path()
	lab.manometer_west_path = man_w.get_path()
	lab.manometer_east_path = man_e.get_path()

	# Wire fake active state & firm patches
	adapter_w._last_computed_flow = true
	adapter_e._last_computed_flow = true
	man_w._current_pressure = 4.0
	man_e._current_pressure = 4.0
	patch_w._is_patched = true
	patch_w._is_firm_patch = true
	patch_e._is_patched = true
	patch_e._is_firm_patch = true

	_step_tree([lab, adapter_w, adapter_e, patch_w, patch_e, man_w, man_e], 0.1)

	assert_bool(lab.is_stabilized()).is_true()

	_step_tree([lab, adapter_w, adapter_e, patch_w, patch_e, man_w, man_e], 2.0)
	assert_bool(lab.is_stabilized()).is_true()


# 6. Snapshot determinism across puzzle cycle
func test_puzzle_snapshot_determinism() -> void:
	var tank = auto_free(CoolantTankScript.new())
	var valve = auto_free(PipeValveScript.new())
	var leak = auto_free(CoolantLeakScript.new())
	var adapter = auto_free(CoolantFlowAdapterScript.new())
	var patch = auto_free(LeakPatchPointScript.new())

	add_child(tank)
	add_child(valve)
	add_child(leak)
	add_child(adapter)
	add_child(patch)

	valve.starts_active = true
	valve.is_active = true
	leak.warning_duration = 0.01
	leak.ramp_up_duration = 0.01
	adapter.tank_path = tank.get_path()
	adapter.valves = [valve.get_path()]
	adapter.leaks = [leak.get_path()]
	patch.leak_path = leak.get_path()

	_step_tree([tank, valve, leak, adapter, patch], 0.05)
	leak.trigger_leak()
	_step_tree([tank, valve, leak, adapter, patch], 0.2)

	var snap_tank = tank.get_snapshot()
	var snap_leak = leak.get_snapshot()
	var snap_patch = patch.get_snapshot()

	_step_tree([tank, valve, leak, adapter, patch], 0.5)
	var tank_lvl_advanced = tank.tank_level
	var leak_int_advanced = leak.get_leak_intensity()

	tank.restore_snapshot(snap_tank)
	leak.restore_snapshot(snap_leak)
	patch.restore_snapshot(snap_patch)

	_step_tree([tank, valve, leak, adapter, patch], 0.5)

	assert_float(tank.tank_level).is_equal_approx(tank_lvl_advanced, 0.00001)
	assert_float(leak.get_leak_intensity()).is_equal_approx(leak_int_advanced, 0.00001)


func _count_event(sink: Array) -> void:
	sink[0] += 1


# El grafo OCLS entra por set_active(), no por la senal de la valvula: LogicCircuitManager
# lo llama sobre cada nodo PROP cuando cambia la energia aguas arriba. Esa puerta seguia
# sellando la fisura (reparandola sola al apagarse el circuito) y ningun test la cubria,
# porque todos construyen la fuga suelta, sin manager.
func test_circuit_set_active_depressurizes_instead_of_sealing() -> void:
	var leak = auto_free(CoolantLeakScript.new())
	add_child(leak)
	leak.trigger_leak()
	leak._set_state(CoolantLeak.State.LEAKING)

	leak.set_active(false)

	assert_int(leak.get_state()).is_equal(CoolantLeak.State.DEPRESSURIZED)
	assert_bool(leak.get("_has_been_sealed")).is_false()

	# Y reabrir vuelve a soltar la fuga: el cano nunca se reparo solo.
	leak.set_active(true)
	assert_int(leak.get_state()).is_equal(CoolantLeak.State.LEAKING)


# El parche vive mientras viva el gloo. Con FD-266 un parche firme ya no caduca solo, asi
# que si nadie avisa al destruir el blob la fisura queda tapada para siempre.
func test_destroying_gloo_reopens_the_fissure() -> void:
	var leak = auto_free(CoolantLeakScript.new())
	add_child(leak)
	var patch = auto_free(LeakPatchPointScript.new())
	add_child(patch)
	patch.set("leak_path", patch.get_path_to(leak))
	patch._resolve_references()

	leak.trigger_leak()
	leak._set_state(CoolantLeak.State.LEAKING)

	# Sin presion => parche FIRME, el que no caduca solo.
	assert_bool(patch.patch_with_gloo()).is_true()
	assert_bool(patch.is_firmly_patched()).is_true()

	patch.remove_patch()

	assert_bool(patch.is_patched()).is_false()
	assert_int(leak.get_state()).is_not_equal(CoolantLeak.State.HEALTHY)


# Un parche provisorio tambien tiene que reabrir al destruir el gloo.
func test_destroying_gloo_reopens_provisional_patch() -> void:
	var leak = auto_free(CoolantLeakScript.new())
	add_child(leak)
	var patch = auto_free(LeakPatchPointScript.new())
	add_child(patch)
	patch.set("leak_path", patch.get_path_to(leak))
	patch.set("firm_patch_pressure_threshold", -1.0) # nada alcanza el umbral => provisorio
	patch._resolve_references()

	leak.trigger_leak()
	leak._set_state(CoolantLeak.State.LEAKING)
	assert_bool(patch.patch_with_gloo()).is_true()
	assert_bool(patch.is_firmly_patched()).is_false()

	patch.remove_patch()
	assert_bool(patch.is_patched()).is_false()
