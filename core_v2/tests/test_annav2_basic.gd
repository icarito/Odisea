extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

func test_annav2_autoload_exists():
	assert_bool(ANNAV2 != null).is_true()
	assert_str(ANNAV2.name).is_equal("ANNAV2")

func test_annav2_player_id():
	var id = ANNAV2._player_id
	assert_str(id).is_not_empty()

func test_annav2_session_id():
	var id = ANNAV2._session_id
	assert_str(id).is_not_empty()

# Telemetry must go quiet while the player is away: backgrounded window or paused
# tree. The tree-paused branch is covered through _is_tree_paused (pausing the tree
# inside a test would freeze the runner).
func test_annav2_idle_when_unfocused():
	var prev_focused = ANNAV2._window_focused
	var prev_automated = ANNAV2._automated_run
	ANNAV2._automated_run = false

	ANNAV2._window_focused = true
	assert_bool(ANNAV2._is_idle()).is_equal(ANNAV2._is_tree_paused())

	ANNAV2._window_focused = false
	assert_bool(ANNAV2._is_idle()).is_true()

	ANNAV2._window_focused = prev_focused
	ANNAV2._automated_run = prev_automated

# Headless/RL runs have no window manager to give them focus; they must keep
# reporting or CI and eval sessions would vanish from telemetry.
func test_annav2_automated_run_never_idles():
	var prev_focused = ANNAV2._window_focused
	var prev_automated = ANNAV2._automated_run

	ANNAV2._automated_run = true
	ANNAV2._window_focused = false
	assert_bool(ANNAV2._is_idle()).is_false()

	ANNAV2._window_focused = prev_focused
	ANNAV2._automated_run = prev_automated
