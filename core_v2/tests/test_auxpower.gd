extends GdUnitTestSuite

# TestSuite for AuxPower system (FD-259 / FD-255)

const AuxPowerBusScript = preload("res://core_v2/systems/auxpower/AuxPowerBus.gd")
const SealedDoorLockScript = preload("res://core_v2/systems/auxpower/SealedDoorLock.gd")
const AuxPowerSequenceScript = preload("res://core_v2/systems/circuit/examples/AuxPowerSequence.gd")
const LogicCircuitManagerScript = preload("res://core_v2/systems/circuit/LogicCircuitManager.gd")

const STEP := 1.0 / 60.0

class DummyDoor extends Spatial:
	var is_active: bool = false

	func set_active(v: bool) -> void:
		is_active = v


class DummyPanel extends Spatial:
	signal activated()
	signal deactivated()

	var is_active: bool = false

	func set_active(v: bool) -> void:
		is_active = v

	func activate() -> void:
		is_active = true
		emit_signal("activated")

	func deactivate() -> void:
		is_active = false
		emit_signal("deactivated")


func _make_bus(starts_offline: bool = true, restore_duration: float = 2.5) -> Spatial:
	var bus = auto_free(AuxPowerBusScript.new())
	bus.starts_offline = starts_offline
	bus.restore_duration = restore_duration
	add_child(bus)
	return bus


func _step_bus(bus: Spatial, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _i in range(steps):
		bus._physics_process(STEP)


func test_initial_offline_state_and_flicker_phase_determinism() -> void:
	var bus = _make_bus(true) # starts_offline = true

	assert_int(bus.get_state()).is_equal(AuxPowerBusScript.State.OFFLINE)
	assert_bool(bus.is_powered()).is_false()
	assert_float(bus.get_power_level()).is_equal(0.0)

	var phase0: float = bus.get_flicker_phase()
	assert_float(phase0).is_equal(0.0)

	_step_bus(bus, 0.4) # Half of flicker_period (0.8)
	var phase1: float = bus.get_flicker_phase()
	assert_float(phase1).is_equal_approx(0.5, 0.01)

	_step_bus(bus, 0.4) # Completed one full flicker_period
	var phase2: float = bus.get_flicker_phase()
	assert_float(phase2).is_equal_approx(0.0, 0.01)


func test_request_restore_ramps_power_level_and_transitions_to_powered() -> void:
	var bus = _make_bus(true, 2.0) # restore_duration = 2.0s
	var state_changes := [0]
	var restores := [0]
	bus.connect("state_changed", self, "_count_event_1", [state_changes])
	bus.connect("power_restored", self, "_count_event_0", [restores])

	assert_int(bus.get_state()).is_equal(AuxPowerBusScript.State.OFFLINE)

	bus.request_restore()

	assert_int(bus.get_state()).is_equal(AuxPowerBusScript.State.RESTORING)
	assert_int(state_changes[0]).is_equal(1)
	assert_int(restores[0]).is_equal(0)

	# Mid-way through restoration
	_step_bus(bus, 1.0)
	assert_int(bus.get_state()).is_equal(AuxPowerBusScript.State.RESTORING)
	assert_float(bus.get_power_level()).is_greater(0.4)
	assert_float(bus.get_power_level()).is_less(0.6)

	# Complete restoration
	_step_bus(bus, 1.1)
	assert_int(bus.get_state()).is_equal(AuxPowerBusScript.State.POWERED)
	assert_bool(bus.is_powered()).is_true()
	assert_float(bus.get_power_level()).is_equal(1.0)
	assert_int(restores[0]).is_equal(1)


func test_sealed_door_lock_controls_door_based_on_bus_power() -> void:
	var root = auto_free(Spatial.new())
	add_child(root)

	var bus = AuxPowerBusScript.new()
	bus.name = "AuxBus"
	bus.starts_offline = true
	bus.restore_duration = 0.5
	root.add_child(bus)

	var door = DummyDoor.new()
	door.name = "Door"
	root.add_child(door)

	var lock = SealedDoorLockScript.new()
	root.add_child(lock)
	lock.bus_path = lock.get_path_to(bus)
	lock.door_path = lock.get_path_to(door)
	lock._setup_bus_connection()

	# Initially OFFLINE -> door is false (closed/sealed)
	assert_bool(door.is_active).is_false()

	# Power restored -> door becomes active (open/unsealed)
	bus.request_restore()
	_step_bus(bus, 0.6)
	assert_bool(bus.is_powered()).is_true()
	assert_bool(door.is_active).is_true()

	# Power cut -> door becomes inactive (closed/sealed)
	bus.cut_power()
	assert_bool(bus.is_powered()).is_false()
	assert_bool(door.is_active).is_false()


func test_snapshot_restore_determinism_mid_restoring() -> void:
	var bus = _make_bus(true, 2.0) # starts_offline, restore_duration = 2s
	bus.request_restore()

	_step_bus(bus, 1.0) # Step 1 second into RESTORING
	var snap: Dictionary = bus.get_snapshot()
	var mid_power: float = bus.get_power_level()

	# Step further to completion
	_step_bus(bus, 1.5)
	var final_power_1: float = bus.get_power_level()
	var final_state_1: int = bus.get_state()

	assert_int(final_state_1).is_equal(AuxPowerBusScript.State.POWERED)

	# Restore snapshot into a clean bus instance
	var bus2 = _make_bus(true, 2.0)
	bus2.restore_snapshot(snap)

	assert_float(bus2.get_power_level()).is_equal_approx(mid_power, 0.000001)
	assert_int(bus2.get_state()).is_equal(AuxPowerBusScript.State.RESTORING)

	# Step bus2 by the same remaining 1.5s
	_step_bus(bus2, 1.5)

	assert_int(bus2.get_state()).is_equal(final_state_1)
	assert_float(bus2.get_power_level()).is_equal_approx(final_power_1, 0.000001)


func test_three_panel_sequence_logic_circuit_drives_bus() -> void:
	var manager: Spatial = auto_free(LogicCircuitManagerScript.new())

	var p1: DummyPanel = auto_free(DummyPanel.new())
	p1.name = "Panel1"
	manager.add_child(p1)

	var p2: DummyPanel = auto_free(DummyPanel.new())
	p2.name = "Panel2"
	manager.add_child(p2)

	var p3: DummyPanel = auto_free(DummyPanel.new())
	p3.name = "Panel3"
	manager.add_child(p3)

	var bus = auto_free(AuxPowerBusScript.new())
	bus.name = "AuxBus"
	bus.starts_offline = true
	bus.restore_duration = 0.1
	manager.add_child(bus)

	var graph = AuxPowerSequenceScript.create_graph(
		manager.get_path_to(p1),
		manager.get_path_to(p2),
		manager.get_path_to(p3),
		manager.get_path_to(bus)
	)

	manager.set("circuit_data", graph)
	add_child(manager)

	# Initialize inactive states across all panels
	p1.deactivate()
	p2.deactivate()
	p3.deactivate()

	for _i in range(5):
		manager.call("step", STEP)
		bus._physics_process(STEP)

	assert_bool(bus.is_powered()).is_false()

	# Activate only 2 panels
	p1.activate()
	p2.activate()

	for _i in range(5):
		manager.call("step", STEP)
		bus._physics_process(STEP)

	assert_bool(bus.is_powered()).is_false()
	assert_int(bus.get_state()).is_equal(AuxPowerBusScript.State.OFFLINE)

	# Activate 3rd panel
	p3.activate()

	for _i in range(15):
		manager.call("step", STEP)
		bus._physics_process(STEP)

	assert_bool(bus.is_powered()).is_true()
	assert_int(bus.get_state()).is_equal(AuxPowerBusScript.State.POWERED)


func _count_event_0(sink: Array) -> void:
	sink[0] += 1


func _count_event_1(_a1, sink: Array) -> void:
	sink[0] += 1
