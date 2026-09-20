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

# La fecha de referencia sale del MISMO reloj que UpdateManager._today_string() (hora local).
# Antes se armaba con get_unix_time() (UTC): en zonas detrás de UTC, cerca de medianoche el
# "ayer" en UTC caia en el mismo dia local y el test fallaba sin que el updater estuviera mal.
func _date(offset_days: int) -> String:
	var d: Dictionary = OS.get_datetime()
	var y := int(d.get("year", 0))
	var m := int(d.get("month", 0))
	var day := int(d.get("day", 0)) + offset_days
	if day < 1:
		m -= 1
		if m < 1:
			m = 12
			y -= 1
		day += _days_in_month(y, m)
	return "%04d-%02d-%02d" % [y, m, day]

func _days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12: return 31
		4, 6, 9, 11: return 30
		2: return 29 if (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)) else 28
	return 30

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
