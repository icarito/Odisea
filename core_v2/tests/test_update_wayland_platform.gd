extends GdUnitTestSuite

# test_update_wayland_platform.gd - El build experimental Wayland (runtime FRT/SDL2
# del fork) se marca con build_meta variant=wayland y debe consultar SU propio
# manifest (linux_wayland). Si bajara el .pck del build x11 perderia la marca
# (build_meta viaja dentro del .pck) y dejaria de ser wayland tras el update.

const UpdateManagerScript = preload("res://core_v2/update/UpdateManager.gd")

# Sin add_child: _ready() hace I/O sobre user://updates.
func _manager(build_meta: Dictionary) -> Node:
	var um = auto_free(UpdateManagerScript.new())
	um._build_meta_cache = build_meta
	return um

func _runs_on_linux() -> bool:
	return OS.get_name() != "Windows" and OS.get_name() != "OSX" \
		and OS.get_name() != "Android" and OS.get_name() != "iOS" \
		and OS.get_name() != "HTML5"

func test_wayland_variant_resolves_to_its_own_platform():
	if not _runs_on_linux():
		return
	var um = _manager({"channel": "nightly", "variant": "wayland"})
	assert_str(um._resolve_platform()).is_equal("linux_wayland")

func test_plain_linux_build_stays_on_the_linux_platform():
	if not _runs_on_linux():
		return
	var um = _manager({"channel": "nightly"})
	assert_str(um._resolve_platform()).is_equal("linux")
