extends GdUnitTestSuite

# test_ship_system_bus.gd - Unit tests for ShipSystemBus (FD-296 F2)

const ShipSystemBusScript = preload("res://core_v2/systems/ship/ShipSystemBus.gd")
const CoolantTankScript = preload("res://core_v2/props/pipe/CoolantTank.gd")
const PlasmaConduitScript = preload("res://core_v2/systems/plasma/PlasmaConduit.gd")
const PressureSectionScript = preload("res://core_v2/systems/atmosphere/PressureSection.gd")
const AuxPowerBusScript = preload("res://core_v2/systems/auxpower/AuxPowerBus.gd")

var _bus = null

func before_test() -> void:
	_bus = auto_free(ShipSystemBusScript.new())
	add_child(_bus)

func test_missing_sources_default_to_offline() -> void:
	_bus.evaluate_systems()
	var summary = _bus.get_summary()

	assert_int(summary["criocoolant"]["state"]).is_equal(ShipSystemBusScript.STATE_OFFLINE)
	assert_str(summary["criocoolant"]["detail"]).is_equal("sin fuente")

	assert_int(summary["plasma"]["state"]).is_equal(ShipSystemBusScript.STATE_OFFLINE)
	assert_str(summary["plasma"]["detail"]).is_equal("sin fuente")

	assert_int(summary["atmosfera"]["state"]).is_equal(ShipSystemBusScript.STATE_OFFLINE)
	assert_str(summary["atmosfera"]["detail"]).is_equal("sin fuente")

	assert_int(summary["energia"]["state"]).is_equal(ShipSystemBusScript.STATE_OFFLINE)
	assert_str(summary["energia"]["detail"]).is_equal("sin fuente")

func test_criocoolant_states() -> void:
	var tank = auto_free(CoolantTankScript.new())
	add_child(tank)

	_bus.set_sources({"criocoolant": tank.get_path()})

	# Full tank -> STATE_OK
	tank.tank_level = 1.0
	_bus.evaluate_systems()
	assert_int(_bus.get_system_state("criocoolant")).is_equal(ShipSystemBusScript.STATE_OK)

	# Half degraded -> STATE_DEGRADADO
	tank.tank_level = 0.3
	_bus.evaluate_systems()
	assert_int(_bus.get_system_state("criocoolant")).is_equal(ShipSystemBusScript.STATE_DEGRADADO)

	# Empty tank -> STATE_FALLO
	tank.tank_level = 0.0
	_bus.evaluate_systems()
	assert_int(_bus.get_system_state("criocoolant")).is_equal(ShipSystemBusScript.STATE_FALLO)

func test_plasma_conduit_states() -> void:
	var conduit = auto_free(PlasmaConduitScript.new())
	add_child(conduit)

	_bus.set_sources({"plasma": conduit.get_path()})

	conduit.reset()
	_bus.evaluate_systems()
	assert_int(_bus.get_system_state("plasma")).is_equal(ShipSystemBusScript.STATE_OK)

	conduit.trigger_overheat()
	_bus.evaluate_systems()
	assert_int(_bus.get_system_state("plasma")).is_equal(ShipSystemBusScript.STATE_DEGRADADO)

func test_snapshot_roundtrip() -> void:
	var tank = auto_free(CoolantTankScript.new())
	tank.name = "CoolantTankTest"
	tank.tank_level = 0.3
	add_child(tank)

	_bus.set_sources({"criocoolant": tank.get_path()})
	_bus.evaluate_systems()

	var snapshot = _bus.get_snapshot()
	assert_dict(snapshot).contains_keys(["sources", "summary"])

	var new_bus = auto_free(ShipSystemBusScript.new())
	add_child(new_bus)
	new_bus.restore_snapshot(snapshot)

	assert_int(new_bus.get_system_state("criocoolant")).is_equal(ShipSystemBusScript.STATE_DEGRADADO)
