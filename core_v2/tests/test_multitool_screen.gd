extends GdUnitTestSuite

# test_multitool_screen.gd - Unit tests for MultiToolV2 screen integration (FD-296 F2)

const MultiToolScene = preload("res://core_v2/player/MultiToolV2.tscn")
const MultiToolScreenScript = preload("res://core_v2/things/MultiToolScreen.gd")
const LaserScreenScript = preload("res://core_v2/ui/hud/LaserScreen.gd")
const GlooScreenScript = preload("res://core_v2/ui/hud/GlooScreen.gd")

var _tool = null
var _screen = null

func before_test() -> void:
	SuitOS.clear_slots()
	SuitOS.close_screen()
	SuitOS.set_context({})
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)

	_tool = auto_free(MultiToolScene.instance())
	add_child(_tool)

	_screen = auto_free(MultiToolScreenScript.new())
	_screen.multitool_path = _tool.get_path()
	add_child(_screen)
	# Las pantallas equipables Laser/Gloo las instancia el propio MultiToolV2 (call_deferred).
	yield(get_tree(), "idle_frame")

func test_multitool_exposed_api() -> void:
	assert_str(_tool.get_mode_name()).is_equal("LASER")
	var charge = _tool.get_charge_info()
	assert_dict(charge).contains_keys(["active", "max"])
	assert_int(int(charge["active"])).is_equal(0)

func test_screen_snapshot_and_registration() -> void:
	assert_bool(SuitOS.has_screen("player:multitool")).is_true()

	var snapshot = _screen.widget_snapshot()
	assert_str(snapshot.get("id", "")).is_equal("player:multitool")
	assert_str(snapshot.get("mode", "")).is_equal("LASER")
	assert_dict(snapshot).contains_keys(["proto", "title", "charge"])

func test_laser_and_gloo_screens_register_and_equip() -> void:
	assert_bool(SuitOS.has_screen("player:laser")).is_true()
	assert_bool(SuitOS.has_screen("player:gloo")).is_true()

	var laser = _tool.get_node_or_null("LaserScreen")
	var gloo = _tool.get_node_or_null("GlooScreen")
	assert_object(laser).is_not_null()
	assert_object(gloo).is_not_null()

	assert_bool(laser.perform_action("equip", {"desired": true}).get("ok", false)).is_true()
	assert_int(_tool.equipped_tool).is_equal(1) # LASER
	assert_bool(gloo.perform_action("equip", {"desired": true}).get("ok", false)).is_true()
	assert_int(_tool.equipped_tool).is_equal(2) # GLOO
	assert_bool(gloo.perform_action("equip", {"desired": false}).get("ok", false)).is_true()
	assert_int(_tool.equipped_tool).is_equal(0) # NONE


func test_equip_updates_relevance_and_snapshot() -> void:
	var initial_rel = _screen.relevance()

	# Equipar GLOO (Equipped.GLOO = 2)
	assert_bool(_tool.set_equipped(2)).is_true()
	assert_str(_tool.get_mode_name()).is_equal("GLOO")

	var gloo_rel = _screen.relevance()
	assert_float(gloo_rel).is_greater(initial_rel)

	var snapshot = _screen.widget_snapshot()
	assert_str(snapshot.get("mode", "")).is_equal("GLOO")
