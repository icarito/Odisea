extends CanvasLayer

const RetroWindowScene = preload("res://core_v2/ui/retro/RetroWindow.tscn")
const OYSShellScene = preload("res://core_v2/ui/retro/OYSShell.tscn")
const OYSConsoleScript = preload("res://core_v2/ui/retro/OYS_Console.gd")

export(Theme) var retro_theme
export(DynamicFontData) var pixel_font_data
export(int) var pixel_font_size := 16
export(bool) var play_boot_on_ready := true
export(float) var bios_line_delay := 0.16

var _clock_accum := 0.0
var _windows := []
var _console = null
var _terminal_count := 1
var _system_menu: PopupMenu = null
var _focused_window: RetroWindow = null

onready var _desktop: Control = $Desktop
onready var _desktop_contents: Control = $Desktop/DesktopContents
onready var _boot_screen: ColorRect = $Desktop/BootScreen
onready var _boot_text: RichTextLabel = $Desktop/BootScreen/BootMargin/BootVBox/BootText
onready var _boot_logo: Label = $Desktop/BootScreen/BootMargin/BootVBox/OdiseaLogo
onready var _boot_progress: ProgressBar = $Desktop/BootScreen/BootMargin/BootVBox/BootProgress
onready var _clock_label: Label = $Desktop/DesktopContents/TaskBar/TaskRow/Clock
onready var _window_area: Control = $Desktop/DesktopContents/WindowArea
onready var _active_tasks: HBoxContainer = $Desktop/DesktopContents/TaskBar/TaskRow/ActiveTasks
onready var _start_button: Button = $Desktop/DesktopContents/TaskBar/TaskRow/StartButton

func _ready() -> void:
	layer = 100
	_start_button.rect_min_size = Vector2(100, 32)
	_apply_theme()
	_setup_system_menu()
	_ensure_console_singleton()
	_seed_windows()
	_register_windows()
	_mount_terminal_app()
	_center_terminal_window()
	call_deferred("_center_terminal_window")
	_update_clock_label()
	set_process(true)
	
	if play_boot_on_ready:
		_start_boot_sequence()
	else:
		_show_desktop()

func _process(delta: float) -> void:
	_clock_accum += delta
	if _clock_accum >= 1.0:
		_clock_accum = 0.0
		_update_clock_label()

func _notification(what: int) -> void:
	if what == 1008: # NOTIFICATION_WM_SIZE_CHANGED in Godot 3.x
		call_deferred("_center_terminal_window")

func _apply_theme() -> void:
	if not retro_theme:
		return
	if pixel_font_data:
		var dynamic_font := DynamicFont.new()
		dynamic_font.font_data = pixel_font_data
		dynamic_font.size = pixel_font_size
		dynamic_font.use_filter = true
		dynamic_font.use_mipmaps = true
		var themed = retro_theme.duplicate(true)
		themed.default_font = dynamic_font
		_desktop.theme = themed
		return
	_desktop.theme = retro_theme

func _seed_windows() -> void:
	if _window_area.get_child_count() > 0:
		return
	var specs = [
		{"title": "OYS Shell", "pos": Vector2(140, 170), "size": Vector2(700, 390), "text": ">_ fastfetch\nReady."}
	]
	for spec in specs:
		var w = RetroWindowScene.instance()
		w.window_title = spec.title
		w.rect_position = spec.pos
		w.rect_size = spec.size
		var content = w.get_node("Content")
		var label := Label.new()
		label.text = spec.text
		label.autowrap = true
		content.add_child(label)
		_window_area.add_child(w)

func _register_windows() -> void:
	_windows.clear()
	for child in _window_area.get_children():
		if child is RetroWindow:
			var title = String(child.window_title)
			if title == "Node Explorer" or title == "Inspector":
				child.queue_free()
				continue
			_windows.append(child)
			child.connect("window_focused", self , "_on_window_focused")
			child.connect("close_requested", self , "_on_window_closed")
			child.connect("window_clicked", self , "_on_window_any_click")
	_refresh_task_buttons()
	_minimize_non_terminal_windows()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if (key.control or key.command) and key.scancode == KEY_W:
		if is_instance_valid(_focused_window):
			_focused_window.hide()
			_on_window_closed(_focused_window)
			_focus_first_visible_window()
			get_tree().set_input_as_handled()

func _refresh_task_buttons() -> void:
	for n in _active_tasks.get_children():
		n.queue_free()
	for w in _windows:
		if not is_instance_valid(w):
			continue
		var btn := Button.new()
		var is_minimized = not w.visible
		btn.text = ("[ ] " if is_minimized else "") + w.window_title
		btn.rect_min_size = Vector2(140, 32)
		btn.connect("pressed", self , "_on_task_button_pressed", [w])
		_active_tasks.add_child(btn)

func _on_task_button_pressed(window: RetroWindow) -> void:
	if not is_instance_valid(window):
		return
	if window.visible and window == _focused_window:
		window.hide()
		_focused_window = null
		_focus_first_visible_window()
		_refresh_task_buttons()
		return
	window.show()
	_focus_window(window)

func _on_window_focused(window: RetroWindow) -> void:
	_focus_window(window)
	_focus_shell_command_input(window)

func _on_window_closed(_window: RetroWindow) -> void:
	_refresh_task_buttons()

func _focus_window(target: RetroWindow) -> void:
	if not is_instance_valid(target):
		return
	_focused_window = target
	target.raise()
	target.show()
	for w in _windows:
		if is_instance_valid(w):
			w.set_focused(w == target)
	_focus_shell_command_input(target)
	_refresh_task_buttons()

func _on_window_any_click(window: RetroWindow, event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb = event as InputEventMouseButton
	if mb.button_index == BUTTON_LEFT and mb.pressed:
		_focus_shell_command_input(window)

func _focus_first_visible_window() -> void:
	for w in _windows:
		if is_instance_valid(w) and w.visible:
			_focus_window(w)
			return

func _focus_shell_command_input(window: RetroWindow) -> void:
	if not is_instance_valid(window):
		return
	var shell = window.find_node("OYSShell", true, false)
	if shell and shell.has_method("focus_command_input"):
		shell.call_deferred("focus_command_input")

func _setup_system_menu() -> void:
	_system_menu = PopupMenu.new()
	_system_menu.name = "SystemMenu"
	_system_menu.add_item("New Terminal", 1)
	_system_menu.add_item("Calculator", 4)
	_system_menu.add_item("Node Scanner", 5)
	_system_menu.add_separator()
	_system_menu.add_item("Exit", 3)
	_system_menu.connect("id_pressed", self , "_on_system_menu_pressed")
	add_child(_system_menu)
	_start_button.connect("pressed", self , "_on_system_button_pressed")

func _on_system_button_pressed() -> void:
	if not _system_menu:
		return
	var pos = _start_button.get_global_position()
	var height = _start_button.rect_size.y
	_system_menu.rect_position = Vector2(pos.x, max(0, pos.y - _system_menu.rect_size.y - height))
	_system_menu.popup()

func _on_system_menu_pressed(id: int) -> void:
	match id:
		1:
			_open_new_terminal()
		2:
			_open_about_window()
		3:
			get_tree().quit()
		4:
			_open_calc()
		5:
			_open_nodescan()

func _open_new_terminal() -> void:
	var w = RetroWindowScene.instance()
	_terminal_count += 1
	w.window_title = "OYS Shell %d" % _terminal_count
	w.rect_size = Vector2(700, 390)
	w.rect_position = Vector2(80 + (_terminal_count * 16) % 120, 70 + (_terminal_count * 20) % 120)
	_window_area.add_child(w)
	_windows.append(w)
	w.connect("window_focused", self , "_on_window_focused")
	w.connect("close_requested", self , "_on_window_closed")
	w.connect("window_clicked", self , "_on_window_any_click")
	var content = w.get_node_or_null("VBox/Content")
	if content:
		for child in content.get_children():
			child.queue_free()
		content.add_child(OYSShellScene.instance())
	w.show()
	_focus_window(w)
	_refresh_task_buttons()

func _open_about_window() -> void:
	var w = RetroWindowScene.instance()
	w.window_title = "About OdiseaOS"
	w.rect_size = Vector2(500, 280)
	w.rect_position = Vector2(200, 120)
	_window_area.add_child(w)
	_windows.append(w)
	w.connect("window_focused", self , "_on_window_focused")
	w.connect("close_requested", self , "_on_window_closed")
	w.connect("window_clicked", self , "_on_window_any_click")
	var content = w.get_node_or_null("VBox/Content")
	if content:
		for child in content.get_children():
			child.queue_free()
		var label := Label.new()
		label.autowrap = true
		label.text = "OdiseaOS Workbench\nGodot 3.6 Retro UI\n\nVirtual terminals and runtime tools for Core_v2."
		content.add_child(label)
	w.show()
	_focus_window(w)
	_refresh_task_buttons()

func _open_calc() -> void:
	var w = RetroWindowScene.instance()
	w.window_title = "OYS-CALC"
	w.rect_size = Vector2(200, 260)
	w.rect_position = Vector2(100, 100)
	_window_area.add_child(w)
	_windows.append(w)
	w.connect("window_focused", self , "_on_window_focused")
	w.connect("close_requested", self , "_on_window_closed")
	w.connect("window_clicked", self , "_on_window_any_click")
	var content = w.get_node_or_null("VBox/Content")
	if content:
		for child in content.get_children():
			child.queue_free()
		content.add_child(load("res://core_v2/ui/retro/OysCalc.gd").new())
	w.show()
	_focus_window(w)
	_refresh_task_buttons()

func _open_nodescan() -> void:
	var w = RetroWindowScene.instance()
	w.window_title = "NODE-SCAN"
	w.rect_size = Vector2(300, 400)
	w.rect_position = Vector2(350, 50)
	_window_area.add_child(w)
	_windows.append(w)
	w.connect("window_focused", self , "_on_window_focused")
	w.connect("close_requested", self , "_on_window_closed")
	w.connect("window_clicked", self , "_on_window_any_click")
	var content = w.get_node_or_null("VBox/Content")
	if content:
		for child in content.get_children():
			child.queue_free()
		content.add_child(load("res://core_v2/ui/retro/NodeScan.gd").new())
	w.show()
	_focus_window(w)
	_refresh_task_buttons()

func _update_clock_label() -> void:
	var now = OS.get_datetime()
	_clock_label.text = "%02d:%02d" % [now.hour, now.minute]

func _start_boot_sequence() -> void:
	_boot_screen.visible = true
	_boot_screen.modulate.a = 1.0
	_desktop_contents.visible = false
	_boot_text.clear()
	_boot_logo.visible = false
	_boot_progress.visible = false
	_boot_progress.value = 0
	call_deferred("_run_boot_sequence")

func _run_boot_sequence() -> void:
	var bios_lines = [
		"ODISEA SYSTEMS BIOS v2.0",
		"CHECKING MEMORY.................. 640K OK",
		"CHECKING CPU..................... 80486DX OK",
		"MOUNTING VOLUME: SECTOR_07....... OK",
		"VERIFYING TELEMETRY BUS.......... OK",
		"BOOT DEVICE: ODISEA_OS_CORE"
	]
	for line in bios_lines:
		_append_boot_line(line)
		yield (get_tree().create_timer(bios_line_delay), "timeout")
	_append_boot_line("")
	_append_boot_line("LOADING ODISEA OS...")
	_boot_logo.visible = true
	_boot_progress.visible = true
	for i in range(0, 101, 10):
		_boot_progress.value = i
		yield (get_tree().create_timer(0.08), "timeout")
	_append_boot_line("INITIALIZING USER: ELIAS...")
	yield (get_tree().create_timer(0.22), "timeout")
	_append_boot_line("ACCESS GRANTED")
	yield (get_tree().create_timer(0.25), "timeout")
	_fade_boot_to_desktop()

func _append_boot_line(text: String) -> void:
	_boot_text.append_bbcode(text + "\n")
	var lc = _boot_text.get_line_count()
	if lc > 0:
		# Godot 3 RichTextLabel can report a transient extra line during append.
		_boot_text.scroll_to_line(max(0, lc - 2))

func _fade_boot_to_desktop() -> void:
	var t := Tween.new()
	add_child(t)
	t.interpolate_property(_boot_screen, "modulate:a", 1.0, 0.0, 0.45, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	t.start()
	yield (t, "tween_all_completed")
	t.queue_free()
	_show_desktop()

func _show_desktop() -> void:
	_boot_screen.visible = false
	_boot_screen.modulate.a = 1.0
	_desktop_contents.visible = true
	_center_terminal_window()

func _ensure_console_singleton() -> void:
	var root = get_tree().root
	if not root:
		return
	_console = root.get_node_or_null("OYS_Console")
	if _console:
		return
	_console = OYSConsoleScript.new()
	_console.name = "OYS_Console"
	root.call_deferred("add_child", _console)

func _mount_terminal_app() -> void:
	var terminal_window = _get_terminal_window()
	if not terminal_window:
		return
	var content = terminal_window.get_node_or_null("VBox/Content")
	if not content:
		return
	for child in content.get_children():
		child.queue_free()
	var shell = OYSShellScene.instance()
	content.add_child(shell)

func _minimize_non_terminal_windows() -> void:
	var terminal_window = _get_terminal_window()
	for w in _windows:
		if not is_instance_valid(w):
			continue
		if w == terminal_window:
			w.show()
			_center_terminal_window()
			_focus_window(w)
		else:
			w.hide()
	_refresh_task_buttons()

func _get_terminal_window() -> RetroWindow:
	for w in _windows:
		if is_instance_valid(w) and String(w.window_title).findn("shell") != -1:
			return w
	return null

func _center_terminal_window() -> void:
	var terminal_window = _get_terminal_window()
	if not terminal_window:
		return
	var viewport_size = get_viewport().size
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return
	var taskbar_height = 38.0
	var available = Vector2(viewport_size.x, max(0.0, viewport_size.y - taskbar_height))
	var win_size = terminal_window.rect_size
	if win_size.x <= 0 or win_size.y <= 0:
		win_size = terminal_window.rect_min_size
	var centered = Vector2(
		(available.x - win_size.x) * 0.5,
		(available.y - win_size.y) * 0.5
	)
	terminal_window.rect_position = Vector2(max(0.0, centered.x), max(0.0, centered.y))
