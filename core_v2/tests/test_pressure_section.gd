extends GdUnitTestSuite

# TestSuite for PressureSection and PurgeDial (FD-258 / FD-255).

const PressureSectionScript = preload("res://core_v2/systems/atmosphere/PressureSection.gd")
const PurgeDialScript = preload("res://core_v2/systems/atmosphere/PurgeDial.gd")
const STEP := 1.0 / 60.0


func _make_section(starts_rising: bool = false) -> Spatial:
	var section = auto_free(PressureSectionScript.new())
	section.starts_rising = starts_rising
	add_child(section)
	return section


func _make_dial(section: Spatial) -> Spatial:
	var dial = auto_free(PurgeDialScript.new())
	add_child(dial)
	if section != null:
		dial.section_path = dial.get_path_to(section)
	return dial


func _step_node(node: Spatial, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		node._physics_process(STEP)


func _step_two_nodes(node1: Spatial, node2: Spatial, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		node1._physics_process(STEP)
		node2._physics_process(STEP)


func test_full_time_cycle_transitions_pressure_and_single_blowout() -> void:
	var section = _make_section()
	var alarms := [0]
	var sparks := [0]
	var blowouts := [0]
	section.connect("alarm_started", self, "_count_event_0", [alarms])
	section.connect("spark_started", self, "_count_event_0", [sparks])
	section.connect("blowout", self, "_count_event_2", [blowouts])

	assert_int(section.get_state()).is_equal(PressureSectionScript.State.NOMINAL)
	assert_float(section.get_pressure()).is_equal(1.0)
	assert_bool(section.is_sealed()).is_false()
	section.raise_pressure()

	assert_int(section.get_state()).is_equal(PressureSectionScript.State.RISING)
	assert_bool(section.is_sealed()).is_true()
	assert_int(alarms[0]).is_equal(1)
	_step_node(section, section.warning_duration * 0.5)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.RISING)
	assert_float(section.get_pressure()).is_greater(1.0)
	assert_float(section.get_pressure()).is_less(section.critical_pressure)
	assert_float(section.get_alarm_phase()).is_greater(0.4)
	assert_float(section.get_alarm_phase()).is_less(0.6)

	_step_node(section, section.warning_duration * 0.5 + 0.1)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.CRITICAL)
	assert_int(sparks[0]).is_equal(1)
	assert_int(blowouts[0]).is_equal(0)
	assert_float(section.get_pressure()).is_equal(section.critical_pressure)

	_step_node(section, section.spark_duration + 0.1)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.VENTED)
	assert_int(blowouts[0]).is_equal(1)
	_step_node(section, section.recover_duration + 0.2)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.NOMINAL)
	assert_float(section.get_pressure()).is_equal(1.0)
	assert_bool(section.is_sealed()).is_false()
	assert_int(blowouts[0]).is_equal(1)


func test_warning_and_spark_order_respected() -> void:
	var section = _make_section()
	var alarms := [0]
	var sparks := [0]
	var blowouts := [0]
	section.connect("alarm_started", self, "_count_event_0", [alarms])
	section.connect("spark_started", self, "_count_event_0", [sparks])
	section.connect("blowout", self, "_count_event_2", [blowouts])
	section.raise_pressure()

	_step_node(section, section.warning_duration - 0.2)
	assert_int(alarms[0]).is_equal(1)
	assert_int(sparks[0]).is_equal(0)
	assert_int(blowouts[0]).is_equal(0)
	_step_node(section, 0.4)
	assert_int(sparks[0]).is_equal(1)
	assert_int(blowouts[0]).is_equal(0)


func test_purge_during_rising_and_critical_stabilizes_without_blowout() -> void:
	var section = _make_section()
	var blowouts := [0]
	var stabilized := [0]
	section.connect("blowout", self, "_count_event_2", [blowouts])
	section.connect("pressure_stabilized", self, "_count_event_0", [stabilized])

	section.raise_pressure()
	_step_node(section, section.warning_duration * 0.5)
	section.purge()
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.VENTED)
	assert_int(stabilized[0]).is_equal(1)
	_step_node(section, section.recover_duration + 0.5)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.NOMINAL)
	assert_int(blowouts[0]).is_equal(0)

	section.raise_pressure()
	_step_node(section, section.warning_duration + section.spark_duration * 0.5)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.CRITICAL)
	section.purge()
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.VENTED)
	assert_int(stabilized[0]).is_equal(2)
	_step_node(section, section.recover_duration + 0.5)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.NOMINAL)
	assert_int(blowouts[0]).is_equal(0)


func test_is_sealed_returns_true_when_not_nominal() -> void:
	var section = _make_section()
	assert_bool(section.is_sealed()).is_false()
	section.raise_pressure()
	assert_bool(section.is_sealed()).is_true()
	_step_node(section, section.warning_duration + 0.1)
	assert_bool(section.is_sealed()).is_true()
	_step_node(section, section.spark_duration + 0.1)
	assert_bool(section.is_sealed()).is_true()
	_step_node(section, section.recover_duration + 0.1)
	assert_bool(section.is_sealed()).is_false()


func test_purge_dial_mechanics_and_proximity() -> void:
	var section = _make_section()
	var dial = _make_dial(section)
	var locks := [0]
	var slips := [0]
	dial.connect("dial_locked", self, "_count_event_0", [locks])
	dial.connect("dial_slipped", self, "_count_event_0", [slips])

	section.raise_pressure()
	_step_node(section, 1.0)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.RISING)
	assert_float(dial.get_proximity()).is_less(0.5)
	dial.nudge(0.62)
	assert_float(dial.value).is_equal_approx(0.62, 0.0001)
	assert_float(dial.get_proximity()).is_equal_approx(1.0, 0.0001)

	_step_two_nodes(section, dial, dial.hold_duration * 0.5)
	assert_int(locks[0]).is_equal(0)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.RISING)
	dial.nudge(-0.3)
	_step_two_nodes(section, dial, STEP)
	assert_int(slips[0]).is_equal(1)
	assert_int(locks[0]).is_equal(0)

	dial.nudge(0.3)
	_step_two_nodes(section, dial, dial.hold_duration + 0.1)
	assert_int(locks[0]).is_equal(1)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.VENTED)


func test_determinism_and_snapshot_restore_no_duplicate_blowout() -> void:
	var section = _make_section(true)
	_step_node(section, section.warning_duration + section.spark_duration * 0.5)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.CRITICAL)
	var snapshot: Dictionary = section.get_snapshot()
	var blowouts := [0]
	section.connect("blowout", self, "_count_event_2", [blowouts])

	_step_node(section, section.spark_duration * 0.6)
	assert_int(blowouts[0]).is_equal(1)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.VENTED)
	section.restore_snapshot(snapshot)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.CRITICAL)
	_step_node(section, section.spark_duration * 0.6)
	assert_int(blowouts[0]).is_equal(2)

	var snapshot_after: Dictionary = section.get_snapshot()
	section.restore_snapshot(snapshot_after)
	_step_node(section, section.recover_duration + 0.5)
	assert_int(section.get_state()).is_equal(PressureSectionScript.State.NOMINAL)
	assert_int(blowouts[0]).is_equal(2)


func _count_event_0(sink: Array) -> void:
	sink[0] += 1


func _count_event_2(_arg1, _arg2, sink: Array) -> void:
	sink[0] += 1
