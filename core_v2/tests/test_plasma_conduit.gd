extends GdUnitTestSuite

# TestSuite for PlasmaConduit & PlasmaRoute (FD-257 / FD-255)

const PlasmaConduitScript = preload("res://core_v2/systems/plasma/PlasmaConduit.gd")
const PlasmaRouteScript = preload("res://core_v2/systems/plasma/PlasmaRoute.gd")
const STEP := 1.0 / 60.0

class DummyValve extends Spatial:
	signal valve_state_changed(is_open)
	var is_active: bool = false

	func set_valve_state(active: bool) -> void:
		is_active = active
		emit_signal("valve_state_changed", is_active)


func _make_conduit(starts_overheating: bool = false) -> Spatial:
	var conduit = auto_free(PlasmaConduitScript.new())
	conduit.starts_overheating = starts_overheating
	add_child(conduit)
	return conduit


func _step_conduit(conduit: Spatial, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		conduit._physics_process(STEP)


func test_full_time_cycle_transitions_and_warning_progress() -> void:
	var conduit = _make_conduit()
	var overheat_count := [0]
	var vent_count := [0]
	conduit.connect("overheat_started", self, "_count_event", [overheat_count])
	conduit.connect("vent_started", self, "_count_event", [vent_count])

	assert_int(conduit.get_state()).is_equal(PlasmaConduitScript.State.NOMINAL)
	assert_float(conduit.get_hazard_intensity()).is_equal(0.0)
	assert_float(conduit.get_warning_progress()).is_equal(0.0)

	conduit.trigger_overheat()

	assert_int(conduit.get_state()).is_equal(PlasmaConduitScript.State.OVERHEATING)
	assert_int(overheat_count[0]).is_equal(1)
	assert_int(vent_count[0]).is_equal(0)

	# Warning progress advances from 0 to 1 during OVERHEATING
	_step_conduit(conduit, conduit.warning_duration * 0.5)
	assert_int(conduit.get_state()).is_equal(PlasmaConduitScript.State.OVERHEATING)
	assert_float(conduit.get_warning_progress()).is_greater(0.4)
	assert_float(conduit.get_warning_progress()).is_less(0.6)
	assert_float(conduit.get_hazard_intensity()).is_equal(0.0)

	_step_conduit(conduit, conduit.warning_duration * 0.6)
	assert_int(conduit.get_state()).is_equal(PlasmaConduitScript.State.VENTING)
	assert_int(vent_count[0]).is_equal(1)
	assert_float(conduit.get_warning_progress()).is_equal(1.0)

	# Intensity ramps up to 1.0 during VENTING
	_step_conduit(conduit, conduit.ramp_up_duration + 0.1)
	assert_float(conduit.get_hazard_intensity()).is_equal_approx(1.0, 0.0001)


func test_warning_precedes_damage() -> void:
	var conduit = _make_conduit()
	conduit.trigger_overheat()
	assert_int(conduit.get_state()).is_equal(PlasmaConduitScript.State.OVERHEATING)

	# Ensure hazard_intensity remains 0 throughout warning phase
	_step_conduit(conduit, conduit.warning_duration * 0.9)
	assert_int(conduit.get_state()).is_equal(PlasmaConduitScript.State.OVERHEATING)
	assert_float(conduit.get_hazard_intensity()).is_equal(0.0)


func test_reroute_during_venting_dissipates_to_nominal() -> void:
	var conduit = _make_conduit()
	var rerouted_count := [0]
	conduit.connect("flow_rerouted", self, "_count_event", [rerouted_count])

	conduit.trigger_overheat()
	_step_conduit(conduit, conduit.warning_duration + conduit.ramp_up_duration + 0.2)
	assert_int(conduit.get_state()).is_equal(PlasmaConduitScript.State.VENTING)
	assert_float(conduit.get_hazard_intensity()).is_equal_approx(1.0, 0.0001)

	conduit.reroute()
	assert_int(conduit.get_state()).is_equal(PlasmaConduitScript.State.REROUTED)
	assert_int(rerouted_count[0]).is_equal(1)

	# Intensity decreases toward 0 over shutdown_duration
	_step_conduit(conduit, conduit.shutdown_duration * 0.5)
	assert_float(conduit.get_hazard_intensity()).is_greater(0.4)
	assert_float(conduit.get_hazard_intensity()).is_less(0.6)

	_step_conduit(conduit, conduit.shutdown_duration * 0.6)
	assert_int(conduit.get_state()).is_equal(PlasmaConduitScript.State.NOMINAL)
	assert_float(conduit.get_hazard_intensity()).is_equal(0.0)


func test_plasma_route_with_three_valves() -> void:
	var conduit = _make_conduit()
	conduit.trigger_overheat()
	_step_conduit(conduit, conduit.warning_duration + 0.1)
	assert_int(conduit.get_state()).is_equal(PlasmaConduitScript.State.VENTING)

	var v1 = auto_free(DummyValve.new())
	var v2 = auto_free(DummyValve.new())
	var v3 = auto_free(DummyValve.new())
	v1.name = "V1"
	v2.name = "V2"
	v3.name = "V3"
	add_child(v1)
	add_child(v2)
	add_child(v3)

	var route = auto_free(PlasmaRouteScript.new())
	route.conduit_path = conduit.get_path()
	route.valve_paths = [v1.get_path(), v2.get_path(), v3.get_path()]
	route.required_pattern = PoolIntArray([1, 0, 1])
	add_child(route)
	route._bind_valves()

	var solved_count := [0]
	var broken_count := [0]
	route.connect("route_solved", self, "_count_event", [solved_count])
	route.connect("route_broken", self, "_count_event", [broken_count])

	# Set valves to matching pattern [1, 0, 1]
	v1.set_valve_state(true)
	v2.set_valve_state(false)
	v3.set_valve_state(true)

	assert_int(solved_count[0]).is_equal(1)
	assert_bool(route.is_solved()).is_true()
	assert_int(conduit.get_state()).is_equal(PlasmaConduitScript.State.REROUTED)

	# Break pattern by changing v2 to true -> pattern is now [1, 1, 1]
	v2.set_valve_state(true)

	assert_int(broken_count[0]).is_equal(1)
	assert_bool(route.is_solved()).is_false()
	assert_int(conduit.get_state()).is_equal(PlasmaConduitScript.State.OVERHEATING)


func test_determinism_and_snapshot_restore() -> void:
	var conduit = _make_conduit(true) # starts_overheating = true

	_step_conduit(conduit, 1.5) # in OVERHEATING
	_step_conduit(conduit, 2.0) # into VENTING

	var snapshot: Dictionary = conduit.get_snapshot()
	var intensity_at_snap: float = conduit.get_hazard_intensity()
	var progress_at_snap: float = conduit.get_warning_progress()

	_step_conduit(conduit, 1.0)
	var intensity_after: float = conduit.get_hazard_intensity()
	var state_after: int = conduit.get_state()

	conduit.restore_snapshot(snapshot)
	assert_float(conduit.get_hazard_intensity()).is_equal_approx(intensity_at_snap, 0.0000001)
	assert_float(conduit.get_warning_progress()).is_equal_approx(progress_at_snap, 0.0000001)

	_step_conduit(conduit, 1.0)
	assert_int(conduit.get_state()).is_equal(state_after)
	assert_float(conduit.get_hazard_intensity()).is_equal_approx(intensity_after, 0.0000001)


func _count_event(sink: Array) -> void:
	sink[0] += 1
