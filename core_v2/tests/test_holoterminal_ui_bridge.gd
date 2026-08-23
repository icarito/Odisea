extends GdUnitTestSuite

const HoloTerminalScene = preload("res://core_v2/props/controls/HoloTerminalV2.tscn")
const DebugOverlayScene = preload("res://core_v2/ui/retro/DebugOverlay.tscn")
const OYSShellScene = preload("res://core_v2/ui/retro/OYSShell.tscn")
const OYSConsole = preload("res://core_v2/ui/retro/OYS_Console.gd")

func _setup_scene_root() -> Node:
	var scene := Node.new()
	scene.name = "UITestRoot"
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	return scene

func _teardown_scene_root(scene: Node) -> void:
	if scene and is_instance_valid(scene):
		scene.queue_free()
	yield (get_tree(), "idle_frame")

func test_holoterminal_mounts_debugoverlay_in_viewport() -> void:
	var scene = _setup_scene_root()
	var holo = HoloTerminalScene.instance()
	scene.add_child(holo)
	yield (get_tree(), "idle_frame")

	holo.call("_on_terminal_debug_requested")
	yield (get_tree(), "idle_frame")

	var viewport = holo.get_node_or_null("Viewport")
	assert_object(viewport).is_not_null()
	var overlay = viewport.get_node_or_null("DebugOverlay")
	assert_object(overlay).is_not_null()
	var shell = overlay.find_node("OYSShell", true, false)
	assert_object(shell).is_not_null()

	yield (_teardown_scene_root(scene), "completed")

func test_holoterminal_can_be_focus_only_when_not_interactable() -> void:
	var scene = _setup_scene_root()
	var holo = HoloTerminalScene.instance()
	holo.is_interactable = false
	holo.allow_focus_mode = true
	scene.add_child(holo)
	yield (get_tree(), "idle_frame")

	assert_bool(holo.is_in_group("interactable")).is_false()
	assert_bool(holo.is_in_group("focusable")).is_true()
	assert_bool(holo.can_focus()).is_true()
	assert_str(holo.get_interaction_prompt()).is_equal("[Z] Focus Terminal")
	holo.set("_is_focused", true)
	assert_str(holo.get_interaction_prompt()).is_equal("[ESC] Exit Terminal")

	yield (_teardown_scene_root(scene), "completed")

func test_fastfetch_command_prints_odisea_summary() -> void:
	var scene = _setup_scene_root()
	var console = OYSConsole.new()
	console.name = "OYS_Console"
	scene.add_child(console)
	yield (get_tree(), "idle_frame")

	console.call("_execute_line", "fastfetch", 0)

	var logs = console.get_logs()
	var has_os_line := false
	var has_engine_line := false
	for entry in logs:
		var text = str(entry.get("text", ""))
		if text.find("OdiseaOS Workbench") != -1:
			has_os_line = true
		if text.find("Godot 3.6") != -1:
			has_engine_line = true
	assert_bool(has_os_line).is_true()
	assert_bool(has_engine_line).is_true()

	yield (_teardown_scene_root(scene), "completed")

func test_debugoverlay_ctrl_w_closes_focused_window() -> void:
	var scene = _setup_scene_root()
	var overlay = DebugOverlayScene.instance()
	overlay.play_boot_on_ready = false
	scene.add_child(overlay)
	yield (get_tree(), "idle_frame")
	yield (get_tree(), "idle_frame")

	var terminal = overlay.call("_get_terminal_window")
	assert_object(terminal).is_not_null()
	overlay.call("_focus_window", terminal)
	assert_bool(terminal.visible).is_true()

	var ev := InputEventKey.new()
	ev.pressed = true
	ev.scancode = KEY_W
	ev.control = true
	overlay.call("_input", ev)
	assert_bool(terminal.visible).is_false()

	yield (_teardown_scene_root(scene), "completed")

func test_shell_ctrl_plus_updates_font_status() -> void:
	var scene = _setup_scene_root()
	var shell = OYSShellScene.instance()
	scene.add_child(shell)
	yield (get_tree(), "idle_frame")

	var status = shell.get_node_or_null("VBox/Status")
	assert_object(status).is_not_null()

	var ev := InputEventKey.new()
	ev.pressed = true
	ev.scancode = KEY_EQUAL
	ev.control = true
	shell.call("_on_input_gui", ev)

	assert_bool(String(status.text).find("FONT:") != -1).is_true()

	yield (_teardown_scene_root(scene), "completed")

func test_console_quit_command_closes_holoterminal() -> void:
	var scene = _setup_scene_root()
	var holo = HoloTerminalScene.instance()
	scene.add_child(holo)
	yield (get_tree(), "idle_frame")

	holo.set_active(true, true)
	assert_bool(holo.is_active).is_true()

	var console = get_tree().root.get_node_or_null("OYS_Console")
	assert_object(console).is_not_null()
	console.call("_execute_line", "quit", 0)
	yield (get_tree(), "idle_frame")

	assert_bool(holo.is_active).is_false()

	yield (_teardown_scene_root(scene), "completed")

func test_holoterminal_player_occlusion_dither_when_active() -> void:
	var scene = _setup_scene_root()
	var holo = HoloTerminalScene.instance()
	scene.add_child(holo)
	yield (get_tree(), "idle_frame")

	# Inactive terminal should have 0 dither target
	holo.call("_update_player_screen_occlusion", 0.016)
	assert_float(holo.get("_current_player_dither")).is_equal(0.0)

	# Activated terminal without player/camera in line-of-sight should still stay at 0
	holo.set_active(true, true)
	holo.call("_update_player_screen_occlusion", 0.016)
	assert_float(holo.get("_current_player_dither")).is_equal(0.0)

	yield (_teardown_scene_root(scene), "completed")
