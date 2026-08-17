extends GdUnitTestSuite

const DebugConsoleHUDScene = preload("res://core_v2/props/decor/DebugConsoleHUD.tscn")
const DebugConsoleManagerScript = preload("res://core_v2/autoloads/DebugConsoleManager.gd")

func test_debug_console_mounts_oys_shell_in_viewport() -> void:
	var hud = DebugConsoleHUDScene.instance()
	get_tree().root.add_child(hud)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	var viewport = hud.get_node_or_null("Viewport")
	assert_object(viewport).is_not_null()
	var shell = viewport.get_node_or_null("OYSShell")
	assert_object(shell).is_not_null()

	hud.queue_free()
	yield(get_tree(), "idle_frame")

func test_debug_console_is_not_interactable_nor_replay_synced() -> void:
	var hud = DebugConsoleHUDScene.instance()
	get_tree().root.add_child(hud)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	assert_bool(hud.is_in_group("interactable")).is_false()
	assert_bool(hud.is_in_group("focusable")).is_false()
	assert_bool(hud.is_in_group("replay_sync")).is_false()

	hud.queue_free()
	yield(get_tree(), "idle_frame")

func test_debug_console_open_applies_debug_gating() -> void:
	var hud = DebugConsoleHUDScene.instance()
	get_tree().root.add_child(hud)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	hud.open_console()
	assert_bool(hud.is_active).is_true()

	var console = get_tree().root.get_node_or_null("OYS_Console")
	assert_object(console).is_not_null()
	assert_bool(bool(console.allow_cheats)).is_true()
	assert_bool(bool(console.read_only)).is_false()

	hud.close_console()
	assert_bool(hud.is_active).is_false()

	hud.queue_free()
	yield(get_tree(), "idle_frame")

func test_debug_console_toggle_opens_and_closes() -> void:
	var hud = DebugConsoleHUDScene.instance()
	get_tree().root.add_child(hud)
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")

	hud.toggle_console()
	assert_bool(hud.is_active).is_true()
	hud.toggle_console()
	assert_bool(hud.is_active).is_false()

	hud.queue_free()
	yield(get_tree(), "idle_frame")

func test_manager_toggles_debug_console() -> void:
	var manager = DebugConsoleManagerScript.new()
	get_tree().root.add_child(manager)
	yield(get_tree(), "idle_frame")

	manager.toggle_console()
	var hud = manager._get_or_spawn_hud()
	assert_object(hud).is_not_null()
	assert_bool(bool(hud.get("is_active"))).is_true()

	manager.toggle_console()
	assert_bool(bool(hud.get("is_active"))).is_false()

	manager.queue_free()
	if hud and is_instance_valid(hud):
		hud.queue_free()
	yield(get_tree(), "idle_frame")

