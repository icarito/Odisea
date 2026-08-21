extends GdUnitTestSuite

# test_coolant_circuit_flow.gd - Unit test suite for FD-264/FD-266 coolant circuit flow logic,
# adapter bridging, gloo patching decay, manometers, status UI, and snapshot determinism.

const CoolantTankScript = preload("res://core_v2/props/pipe/CoolantTank.gd")
const CoolantLeakScript = preload("res://core_v2/systems/cryo/CoolantLeak.gd")
const LeakPatchPointScript = preload("res://core_v2/systems/cryo/LeakPatchPoint.gd")
const PipeCoolantRunScript = preload("res://core_v2/props/pipe/PipeCoolantRun.gd")
const PipeValveScript = preload("res://core_v2/props/pipe/PipeValve.gd")
const CoolantFlowAdapterScript = preload("res://core_v2/systems/cryo/CoolantFlowAdapter.gd")
const PipeNetworkResourceScript = preload("res://core_v2/systems/pipe/PipeNetworkResource.gd")
const PipeManometerScript = preload("res://core_v2/props/pipe/PipeManometer.gd")
const CoolantSystemStatusUIScript = preload("res://core_v2/things/CoolantSystemStatusUI.gd")
const MultiToolGlooProjectileScript = preload("res://core_v2/player/MultiToolGlooProjectile.gd")

const STEP := 1.0 / 60.0


func _make_network(tank: Node, pipe_run: Node, valve: Node = null, leak: Node = null) -> Resource:
	var net: Resource = auto_free(Resource.new())
	net.set_script(PipeNetworkResourceScript)
	net.set("branches", {
		"main": {
			"tank": tank.get_path(),
			"segments": [
				{
					"pipe_run": pipe_run.get_path(),
					"valve": valve.get_path() if valve != null else NodePath(""),
					"leak": leak.get_path() if leak != null else NodePath(""),
					"flow_dir": Vector3.RIGHT
				}
			]
		}
	})
	return net


func _step_tree(nodes: Array, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		for node in nodes:
			if is_instance_valid(node) and node.has_method("_physics_process"):
				node._physics_process(STEP)


func test_valve_closure_ramps_speed_and_reduces_intensity() -> void:
	var tank = auto_free(CoolantTankScript.new())
	tank.tank_level = 1.0
	add_child(tank)

	var valve = auto_free(PipeValveScript.new())
	valve.starts_active = true
	valve.is_active = true
	add_child(valve)

	var pipe_run = auto_free(PipeCoolantRunScript.new())
	pipe_run.flow_speed = 0.7
	pipe_run.flow_intensity = 1.0
	add_child(pipe_run)

	var adapter = auto_free(CoolantFlowAdapterScript.new())
	adapter.network = _make_network(tank, pipe_run, valve)
	adapter.branch_id = "main"
	add_child(adapter)

	_step_tree([tank, valve, pipe_run, adapter], 0.1)

	assert_bool(adapter.is_flow_active()).is_true()
	assert_float(adapter.get_computed_speed()).is_equal(0.7)
	assert_float(adapter.get_computed_intensity()).is_equal(1.0)

	# Close valve
	valve.is_active = false
	valve.emit_signal("valve_state_changed", false)
	_step_tree([tank, valve, pipe_run, adapter], 0.1)

	assert_bool(adapter.is_flow_active()).is_false()
	assert_float(adapter.get_computed_speed()).is_equal(0.0)
	assert_float(adapter.get_computed_intensity()).is_equal(0.0)

	# Verify speed ramp down on PipeCoolantRun
	assert_float(pipe_run.flow_speed).is_equal(0.0)
	assert_float(pipe_run._current_speed).is_greater(0.0) # Gradually slowing down
	_step_tree([tank, valve, pipe_run, adapter], pipe_run.speed_ramp + 0.2)
	assert_float(pipe_run._current_speed).is_equal_approx(0.0, 0.001)

	# Re-open valve
	valve.is_active = true
	valve.emit_signal("valve_state_changed", true)
	_step_tree([tank, valve, pipe_run, adapter], 0.1)
	assert_bool(adapter.is_flow_active()).is_true()
	assert_float(adapter.get_computed_speed()).is_equal(0.7)


func test_pipe_visual_intensity_fades_when_flow_stops() -> void:
	var pipe_run = auto_free(PipeCoolantRunScript.new())
	pipe_run.flow_intensity = 1.0
	pipe_run.intensity_ramp = 0.5
	add_child(pipe_run)

	pipe_run.set_flow_intensity(0.0)
	pipe_run._physics_process(0.25)
	assert_float(pipe_run._current_flow_intensity).is_greater(0.0)
	assert_float(pipe_run._current_flow_intensity).is_less(1.0)

	pipe_run._physics_process(0.3)
	assert_float(pipe_run._current_flow_intensity).is_equal_approx(0.0, 0.001)


func test_fissure_and_provisional_gloo_patch_decay_cycle() -> void:
	var tank = auto_free(CoolantTankScript.new())
	tank.tank_level = 1.0
	add_child(tank)

	var pipe_run = auto_free(PipeCoolantRunScript.new())
	add_child(pipe_run)

	var leak = auto_free(CoolantLeakScript.new())
	leak.warning_duration = 0.1
	leak.ramp_up_duration = 0.2
	add_child(leak)

	var adapter = auto_free(CoolantFlowAdapterScript.new())
	adapter.network = _make_network(tank, pipe_run, null, leak)
	adapter.branch_id = "main"
	add_child(adapter)

	var patch_point = auto_free(LeakPatchPointScript.new())
	patch_point.leak_path = leak.get_path()
	patch_point.flow_adapter_path = adapter.get_path()
	patch_point.gloo_patch_duration = 0.5
	# Under pressure, gloo forms provisional patch
	add_child(patch_point)

	_step_tree([tank, pipe_run, leak, adapter, patch_point], 0.05)
	leak.trigger_leak()
	_step_tree([tank, pipe_run, leak, adapter, patch_point], 0.4)

	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)
	assert_float(leak.get_leak_intensity()).is_equal_approx(1.0, 0.01)

	# Apply Gloo patch under pressure -> provisional patch
	patch_point.patch_with_gloo()
	_step_tree([leak, patch_point], 0.05)

	assert_bool(patch_point.is_patched()).is_true()
	assert_bool(patch_point.is_firmly_patched()).is_false()

	# Step until decay duration finishes
	_step_tree([leak, patch_point], 0.6)

	assert_bool(patch_point.is_patched()).is_false()
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)


func test_gloo_projectile_patches_fissure_on_collision() -> void:
	var tank = auto_free(CoolantTankScript.new())
	tank.tank_level = 1.0
	add_child(tank)

	var pipe_run = auto_free(PipeCoolantRunScript.new())
	add_child(pipe_run)

	var leak = auto_free(CoolantLeakScript.new())
	leak.warning_duration = 0.1
	leak.ramp_up_duration = 0.1
	add_child(leak)

	var adapter = auto_free(CoolantFlowAdapterScript.new())
	adapter.network = _make_network(tank, pipe_run, null, leak)
	adapter.branch_id = "main"
	add_child(adapter)

	var patch_point = auto_free(LeakPatchPointScript.new())
	patch_point.leak_path = leak.get_path()
	patch_point.flow_adapter_path = adapter.get_path()
	patch_point.gloo_patch_duration = 10.0
	add_child(patch_point)

	leak.trigger_leak()
	_step_tree([tank, pipe_run, leak, adapter, patch_point], 0.3)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)

	var proj = auto_free(MultiToolGlooProjectileScript.new())
	add_child(proj)
	proj._stick_at(patch_point, Vector3.ZERO, Vector3.UP)

	assert_bool(patch_point.is_patched()).is_true()


func test_manometer_reading_reflects_pressure() -> void:
	var tank = auto_free(CoolantTankScript.new())
	tank.tank_level = 1.0
	add_child(tank)

	var pipe_run = auto_free(PipeCoolantRunScript.new())
	add_child(pipe_run)

	var adapter = auto_free(CoolantFlowAdapterScript.new())
	adapter.network = _make_network(tank, pipe_run)
	adapter.branch_id = "main"
	add_child(adapter)

	var manometer = auto_free(PipeManometerScript.new())
	manometer.tank_path = tank.get_path()
	manometer.flow_adapter_path = adapter.get_path()
	manometer.max_pressure = 5.0
	manometer.segment_index = 0
	add_child(manometer)

	_step_tree([tank, pipe_run, adapter, manometer], 0.1)
	assert_float(manometer.get_pressure()).is_equal_approx(5.0, 0.01)

	# Drop tank level
	tank.tank_level = 0.5
	_step_tree([tank, pipe_run, adapter, manometer], 0.1)
	assert_float(manometer.get_pressure()).is_equal_approx(1.25, 0.01)


func test_status_ui_displays_tank_level() -> void:
	var tank = auto_free(CoolantTankScript.new())
	tank.tank_level = 0.8
	add_child(tank)

	var rows = VBoxContainer.new()
	rows.name = "Rows"

	var ui = auto_free(CoolantSystemStatusUIScript.new())
	ui.add_child(rows)
	add_child(ui)

	_step_tree([tank, ui], 0.1)

	assert_bool(ui._tank_label != null).is_true()
	assert_str(ui._tank_label.text).is_equal("80%")


func test_snapshot_determinism() -> void:
	var tank = auto_free(CoolantTankScript.new())
	tank.tank_level = 1.0
	add_child(tank)

	var pipe_run = auto_free(PipeCoolantRunScript.new())
	add_child(pipe_run)

	var leak = auto_free(CoolantLeakScript.new())
	leak.warning_duration = 0.1
	add_child(leak)

	var adapter = auto_free(CoolantFlowAdapterScript.new())
	adapter.network = _make_network(tank, pipe_run, null, leak)
	adapter.branch_id = "main"
	add_child(adapter)

	var patch_point = auto_free(LeakPatchPointScript.new())
	patch_point.leak_path = leak.get_path()
	patch_point.flow_adapter_path = adapter.get_path()
	patch_point.gloo_patch_duration = 5.0
	add_child(patch_point)

	leak.trigger_leak()
	_step_tree([tank, pipe_run, leak, patch_point, adapter], 0.3)
	patch_point.patch_with_gloo()
	_step_tree([tank, pipe_run, leak, patch_point, adapter], 1.0)

	var snap_tank = tank.get_snapshot()
	var snap_leak = leak.get_snapshot()
	var snap_patch = patch_point.get_snapshot()
	var snap_adapter = adapter.get_snapshot()

	_step_tree([tank, pipe_run, leak, patch_point, adapter], 1.5)
	var speed_adv = adapter.get_computed_speed()
	var remaining_adv = patch_point.get_patch_time_remaining()

	tank.restore_snapshot(snap_tank)
	leak.restore_snapshot(snap_leak)
	patch_point.restore_snapshot(snap_patch)
	adapter.restore_snapshot(snap_adapter)

	_step_tree([tank, pipe_run, leak, patch_point, adapter], 1.5)

	assert_float(adapter.get_computed_speed()).is_equal_approx(speed_adv, 0.0001)
	assert_float(patch_point.get_patch_time_remaining()).is_equal_approx(remaining_adv, 0.0001)
