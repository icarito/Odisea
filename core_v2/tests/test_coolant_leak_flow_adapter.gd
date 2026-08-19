extends GdUnitTestSuite

# TestSuite for CoolantLeak with CoolantFlowAdapter integration (FD-270 / T4)

const CoolantLeakScript = preload("res://core_v2/systems/cryo/CoolantLeak.gd")
const STEP := 1.0 / 60.0

class DummyValve extends Spatial:
	signal valve_state_changed(is_open)
	var is_active: bool = true


class MockFlowAdapter extends Node:
	var is_pressurized: bool = false

	func is_pressurized_at(_node: Node) -> bool:
		return is_pressurized


func _step_leak(leak: Spatial, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		leak._physics_process(STEP)


func test_leak_remains_depressurized_when_upstream_adapter_unpressurized() -> void:
	var valve = auto_free(DummyValve.new())
	valve.name = "DummyValve"
	add_child(valve)

	var adapter = auto_free(MockFlowAdapter.new())
	adapter.name = "MockFlowAdapter"
	adapter.is_pressurized = true  # Initially pressurized
	add_child(adapter)

	var leak = auto_free(CoolantLeakScript.new())
	leak.valve_path = valve.get_path()
	leak.flow_adapter_path = adapter.get_path()
	add_child(leak)

	# Initially active and leaking
	leak.trigger_leak()
	_step_leak(leak, leak.warning_duration + 0.5)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)
	assert_float(leak.get_leak_intensity()).is_greater(0.0)

	# Depressurize leak (e.g. own valve closed)
	valve.is_active = false
	valve.emit_signal("valve_state_changed", false)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.DEPRESSURIZED)
	assert_bool(leak.is_depressurized()).is_true()

	# Dissipate intensity to 0
	_step_leak(leak, leak.dissipate_duration + 0.5)
	assert_float(leak.get_leak_intensity()).is_equal(0.0)

	# Upstream valve closes (adapter is_pressurized_at -> false) while own valve is re-opened
	adapter.is_pressurized = false
	valve.is_active = true
	valve.emit_signal("valve_state_changed", true)

	# Fissure must remain in DEPRESSURIZED and leak intensity must not start rising
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.DEPRESSURIZED)
	assert_bool(leak.is_depressurized()).is_true()

	_step_leak(leak, 2.0)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.DEPRESSURIZED)
	assert_float(leak.get_leak_intensity()).is_equal(0.0)


func test_leak_repressurizes_when_upstream_adapter_becomes_pressurized() -> void:
	var valve = auto_free(DummyValve.new())
	valve.name = "DummyValve"
	add_child(valve)

	var adapter = auto_free(MockFlowAdapter.new())
	adapter.name = "MockFlowAdapter"
	adapter.is_pressurized = false
	add_child(adapter)

	var leak = auto_free(CoolantLeakScript.new())
	leak.valve_path = valve.get_path()
	leak.flow_adapter_path = adapter.get_path()
	add_child(leak)

	# Try triggering leak while adapter is unpressurized -> stays DEPRESSURIZED
	leak.trigger_leak()
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.DEPRESSURIZED)

	# Now upstream adapter becomes pressurized (true)
	adapter.is_pressurized = true

	# Triggering leak now allows transition to WARNING / LEAKING
	leak.trigger_leak()
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)

	_step_leak(leak, leak.ramp_up_duration + 0.5)
	assert_float(leak.get_leak_intensity()).is_equal_approx(1.0, 0.0001)


func test_leak_without_flow_adapter_preserves_single_valve_behavior() -> void:
	var valve = auto_free(DummyValve.new())
	valve.name = "DummyValve"
	add_child(valve)

	var leak = auto_free(CoolantLeakScript.new())
	leak.valve_path = valve.get_path()
	add_child(leak)

	leak.set_active(true)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.WARNING)

	_step_leak(leak, leak.warning_duration + 0.5)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)

	valve.emit_signal("valve_state_changed", false)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.DEPRESSURIZED)

	valve.emit_signal("valve_state_changed", true)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)
