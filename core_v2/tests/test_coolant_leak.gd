extends GdUnitTestSuite

# TestSuite for CoolantLeak (FD-256 / FD-255 / FD-266)

const CoolantLeakScript = preload("res://core_v2/systems/cryo/CoolantLeak.gd")
const STEP := 1.0 / 60.0

class DummyValve extends Spatial:
	signal valve_state_changed(is_open)


func _make_leak(starts_leaking: bool = false) -> Spatial:
	var leak = auto_free(CoolantLeakScript.new())
	leak.starts_leaking = starts_leaking
	add_child(leak)
	return leak


func _step_leak(leak: Spatial, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		leak._physics_process(STEP)


func test_full_time_cycle_transitions_and_intensity_ramp_up() -> void:
	var leak = _make_leak()
	var warnings := [0]
	var leaks := [0]
	leak.connect("warning_started", self, "_count_event", [warnings])
	leak.connect("leak_started", self, "_count_event", [leaks])

	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.HEALTHY)
	assert_float(leak.get_leak_intensity()).is_equal(0.0)

	leak.trigger_leak()

	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.WARNING)
	assert_int(warnings[0]).is_equal(1)
	assert_int(leaks[0]).is_equal(0)

	# Step through warning phase
	_step_leak(leak, leak.warning_duration - 0.1)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.WARNING)
	assert_float(leak.get_leak_intensity()).is_equal(0.0)

	_step_leak(leak, 0.2)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)
	assert_int(leaks[0]).is_equal(1)

	# Ramp up midway
	_step_leak(leak, leak.ramp_up_duration * 0.5)
	assert_float(leak.get_leak_intensity()).is_greater(0.4)
	assert_float(leak.get_leak_intensity()).is_less(0.6)

	# Full ramp up
	_step_leak(leak, leak.ramp_up_duration * 0.6)
	assert_float(leak.get_leak_intensity()).is_equal_approx(1.0, 0.0001)


func test_seal_during_warning_returns_to_healthy() -> void:
	var leak = _make_leak()
	var leaks := [0]
	var seals := [0]
	leak.connect("leak_started", self, "_count_event", [leaks])
	leak.connect("leak_sealed", self, "_count_event", [seals])

	leak.trigger_leak()
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.WARNING)

	_step_leak(leak, 2.0)
	leak.seal()

	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.HEALTHY)
	assert_float(leak.get_leak_intensity()).is_equal(0.0)
	assert_int(seals[0]).is_equal(1)
	assert_int(leaks[0]).is_equal(0)

	_step_leak(leak, 5.0)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.HEALTHY)
	assert_float(leak.get_leak_intensity()).is_equal(0.0)


func test_seal_during_leaking_transitions_to_sealed_and_dissipates() -> void:
	var leak = _make_leak()
	var seals := [0]
	leak.connect("leak_sealed", self, "_count_event", [seals])

	leak.trigger_leak()
	_step_leak(leak, leak.warning_duration + leak.ramp_up_duration + 0.2)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)
	assert_float(leak.get_leak_intensity()).is_equal_approx(1.0, 0.0001)

	leak.seal()
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.SEALED)
	assert_int(seals[0]).is_equal(1)

	_step_leak(leak, leak.dissipate_duration * 0.5)
	assert_float(leak.get_leak_intensity()).is_greater(0.4)
	assert_float(leak.get_leak_intensity()).is_less(0.6)

	_step_leak(leak, leak.dissipate_duration * 0.6)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.HEALTHY)
	assert_float(leak.get_leak_intensity()).is_equal_approx(0.0, 0.0001)


func test_determinism_and_snapshot_restore() -> void:
	var leak = _make_leak(true) # starts_leaking = true

	_step_leak(leak, 2.0) # in WARNING
	_step_leak(leak, 3.0) # into LEAKING

	var snapshot: Dictionary = leak.get_snapshot()
	var intensity_at_snap: float = leak.get_leak_intensity()

	_step_leak(leak, 1.5)
	var intensity_after_1: float = leak.get_leak_intensity()
	var state_after_1: int = leak.get_state()

	leak.restore_snapshot(snapshot)
	assert_float(leak.get_leak_intensity()).is_equal_approx(intensity_at_snap, 0.0000001)

	_step_leak(leak, 1.5)
	assert_int(leak.get_state()).is_equal(state_after_1)
	assert_float(leak.get_leak_intensity()).is_equal_approx(intensity_after_1, 0.0000001)


func test_pipe_valve_integration_depressurizes_without_sealing() -> void:
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

	# FD-266 semantics: closing valve depressurizes, does NOT seal physically
	valve.emit_signal("valve_state_changed", false)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.DEPRESSURIZED)
	assert_bool(leak.is_depressurized()).is_true()

	_step_leak(leak, leak.dissipate_duration + 0.5)
	assert_float(leak.get_leak_intensity()).is_equal(0.0)
	# Re-opening valve re-triggers leak immediately without WARNING
	valve.emit_signal("valve_state_changed", true)
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.LEAKING)

	leak.reset()
	assert_int(leak.get_state()).is_equal(CoolantLeakScript.State.HEALTHY)
	assert_float(leak.get_leak_intensity()).is_equal(0.0)


func _count_event(sink: Array) -> void:
	sink[0] += 1
