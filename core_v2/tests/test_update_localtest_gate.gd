extends GdUnitTestSuite

# test_update_localtest_gate.gd - El updater se calla el dia que se instalo un build de
# prueba local (make android-install), para no interrumpir la sesion de debug.

const UpdateManagerScript = preload("res://core_v2/update/UpdateManager.gd")

# Sin add_child a proposito: _ready() del autoload hace I/O sobre user://updates.
func _manager(version: String, seen: Dictionary) -> Node:
	var um = auto_free(UpdateManagerScript.new())
	um._build_meta_cache = {"version": version, "channel": "nightly"}
	um._local_state = {"local_test_first_seen": seen} if not seen.empty() else {}
	return um

func _date(offset_days: int) -> String:
	var d: Dictionary = OS.get_datetime_from_unix_time(OS.get_unix_time() + offset_days * 86400)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]

func test_nightly_build_is_never_deferred():
	var um = _manager("0.4.0-nightly.560+5be41df", {})
	assert_bool(um.updates_deferred_today()).is_false()

func test_localtest_build_is_deferred_on_its_install_day():
	var um = _manager("0.0.0-localtest.1", {"version": "0.0.0-localtest.1", "date": _date(0)})
	assert_bool(um.updates_deferred_today()).is_true()

func test_localtest_build_offers_the_update_next_day():
	var um = _manager("0.0.0-localtest.1", {"version": "0.0.0-localtest.1", "date": _date(-1)})
	assert_bool(um.updates_deferred_today()).is_false()

func test_release_test_build_is_deferred_too():
	var um = _manager("0.0.0-releasetest.999999999",
		{"version": "0.0.0-releasetest.999999999", "date": _date(0)})
	assert_bool(um.updates_deferred_today()).is_true()
