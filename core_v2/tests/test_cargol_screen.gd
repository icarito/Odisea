extends GdUnitTestSuite

# test_cargol_screen.gd - Unit tests for CargolScreen and CargolHUD migration (FD-296 F2)

const CargolHUDScript = preload("res://core_v2/ui/CargolHUD.gd")
const CargolScreenScript = preload("res://core_v2/things/CargolScreen.gd")

class DummyDrone:
	extends Spatial
	var state := 0
	var cooldown_timer := 0.0
	var lure_cooldown := 10.0
	var emp_cooldown := 5.0

var _screen = null
var _hud = null

func before_test() -> void:
	SuitOS.min_relevance_a = SuitOS.MIN_RELEVANCE_A
	SuitOS.unpin_screen()
	SuitOS.close_screen()
	SuitOS.set_context({})
	for id in SuitOS.get_registered_screens():
		SuitOS.unregister_screen(id)

	_hud = auto_free(CargolHUDScript.new())
	add_child(_hud)

	_screen = auto_free(CargolScreenScript.new())
	add_child(_screen)

func test_screen_registration_and_snapshot() -> void:
	assert_bool(SuitOS.has_screen("drone:cargol")).is_true()

	var snapshot = _screen.widget_snapshot()
	assert_str(snapshot.get("id", "")).is_equal("drone:cargol")
	assert_str(snapshot.get("title", "")).is_equal("Cargol")
	assert_dict(snapshot).contains_keys(["proto", "drone_state", "cooldown", "source"])

func test_relevance_boost_on_active_drone_state() -> void:
	var dummy_drone = auto_free(DummyDrone.new())
	dummy_drone.add_to_group("cargol_defensive")
	add_child(dummy_drone)

	var rel_idle = _screen.relevance()
	assert_float(rel_idle).is_equal(0.1)

	# State STUNNED = 5 -> higher relevance
	dummy_drone.state = 5
	var rel_stunned = _screen.relevance()
	assert_float(rel_stunned).is_greater(rel_idle)

func test_cargol_hud_no_regression() -> void:
	# Ensure CargolHUD process without errors
	_hud._process(0.016)
	assert_bool(_hud.visible).is_false() # No drone in tree
