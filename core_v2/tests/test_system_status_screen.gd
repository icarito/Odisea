extends GdUnitTestSuite

# test_system_status_screen.gd - Integration tests for SystemStatusScreen and SuitOS (FD-296 F2)

const ShipSystemBusScript = preload("res://core_v2/systems/ship/ShipSystemBus.gd")
const SystemStatusScreenScript = preload("res://core_v2/things/SystemStatusScreen.gd")
const CoolantTankScript = preload("res://core_v2/props/pipe/CoolantTank.gd")

var _bus = null
var _screen = null

func before_test() -> void:
	SuitOS.min_relevance_a = SuitOS.MIN_RELEVANCE_A
	SuitOS.unpin_screen()
	SuitOS.close_screen()
	SuitOS.set_context({})
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)

	_bus = auto_free(ShipSystemBusScript.new())
	add_child(_bus)

	_screen = auto_free(SystemStatusScreenScript.new())
	_screen.bus_path = _bus.get_path()
	add_child(_screen)

func test_registration_and_snapshot() -> void:
	assert_bool(SuitOS.has_screen("ship:systems")).is_true()

	var snapshot = _screen.widget_snapshot()
	assert_str(snapshot.get("id", "")).is_equal("ship:systems")
	assert_str(snapshot.get("title", "")).is_equal("Sistemas de nave")
	assert_str(snapshot.get("source", "")).is_equal("online")
	assert_dict(snapshot).contains_keys(["proto", "systems"])

func test_relevance_boost_on_system_failure() -> void:
	# Default relevance without failures -> low (0.1)
	var rel_initial = _screen.relevance()
	assert_float(rel_initial).is_equal(0.1)

	# Attach a coolant tank and set level to 0.0 -> STATE_FALLO
	var tank = auto_free(CoolantTankScript.new())
	tank.tank_level = 0.0
	add_child(tank)

	_bus.set_sources({"criocoolant": tank.get_path()})
	_bus.evaluate_systems()

	var rel_boosted = _screen.relevance()
	assert_float(rel_boosted).is_greater(0.5)

	# Check that Slot A picks up ship:systems due to high relevance
	SuitOS.set_context({"player_position": [0, 0, 0]})
	var slot_a = SuitOS.get_slot_snapshot("slot_a")
	assert_str(slot_a.get("id", "")).is_equal("ship:systems")

func test_dome_intro_scene_has_bus_and_screen() -> void:
	var scene = load("res://core_v2/levels/interiors/Dome_Intro.tscn")
	assert_object(scene).is_not_null()

	var inst = auto_free(scene.instance())
	add_child(inst)

	var bus_node = inst.get_node_or_null("ShipSystemBus")
	assert_object(bus_node).is_not_null()

	var screen_node = inst.get_node_or_null("SystemStatusScreen")
	assert_object(screen_node).is_not_null()

	assert_bool(SuitOS.has_screen("ship:systems")).is_true()
