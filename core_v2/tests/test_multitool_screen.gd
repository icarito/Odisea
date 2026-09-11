extends GdUnitTestSuite

# test_multitool_screen.gd - Unit tests for MultiToolV2 screen integration (FD-296 F2)

const MultiToolScene = preload("res://core_v2/player/MultiToolV2.tscn")
const MultiToolScreenScript = preload("res://core_v2/things/MultiToolScreen.gd")

var _tool = null
var _screen = null

func before_test() -> void:
	SuitOS.min_relevance_a = SuitOS.MIN_RELEVANCE_A
	SuitOS.unpin_screen()
	SuitOS.close_screen()
	SuitOS.set_context({})
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)

	_tool = auto_free(MultiToolScene.instance())
	add_child(_tool)

	_screen = auto_free(MultiToolScreenScript.new())
	_screen.multitool_path = _tool.get_path()
	add_child(_screen)

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

func test_mode_switch_emits_signal_and_updates_relevance() -> void:
	var initial_rel = _screen.relevance()

	# Switch mode to GLOO
	_tool._switch_mode(1) # Mode.GLOO
	assert_str(_tool.get_mode_name()).is_equal("GLOO")

	var gloo_rel = _screen.relevance()
	assert_float(gloo_rel).is_greater(initial_rel)

	var snapshot = _screen.widget_snapshot()
	assert_str(snapshot.get("mode", "")).is_equal("GLOO")
