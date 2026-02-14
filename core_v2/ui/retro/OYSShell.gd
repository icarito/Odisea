extends Control
class_name OYSShell

const MAX_RENDER_LINES := 5000
const OYSConsoleScript = preload("res://core_v2/ui/retro/OYS_Console.gd")
const FONT_SIZE_MIN := 12
const FONT_SIZE_MAX := 34

var _console = null
var _history_index := -1
var _font_size := 16
var _font_data: DynamicFontData = null
var _scroll_line_cursor := 0

onready var _output: RichTextLabel = $VBox/Output
onready var _prompt: Label = $VBox/CommandRow/Prompt
onready var _input: LineEdit = $VBox/CommandRow/CommandInput
onready var _status: Label = $VBox/Status

func _ready() -> void:
	_ensure_console_singleton()
	_connect_console()
	_init_font_scaling()
	connect("gui_input", self, "_on_shell_gui_input")
	_connect_focus_passthrough(self)
	if _input:
		_input.connect("text_entered", self, "_on_text_entered")
		_input.connect("gui_input", self, "_on_input_gui")
		focus_command_input()
	if _output:
		_output.scroll_following = true
	_render_full_output()
	set_process(true)

func _connect_focus_passthrough(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			var ctrl = child as Control
			if not ctrl.is_connected("gui_input", self, "_on_shell_gui_input"):
				ctrl.connect("gui_input", self, "_on_shell_gui_input")
		_connect_focus_passthrough(child)

func _process(_delta: float) -> void:
	if _console == null:
		_connect_console()
		if _console != null:
			_render_full_output()

func _connect_console() -> void:
	var root = get_tree().root
	if not root:
		return
	_console = root.get_node_or_null("OYS_Console")
	if not _console:
		_status.text = "Console not found"
		return
	if not _console.is_connected("log_added", self, "_on_log_added"):
		_console.connect("log_added", self, "_on_log_added")
	if not _console.is_connected("logs_cleared", self, "_on_logs_cleared"):
		_console.connect("logs_cleared", self, "_on_logs_cleared")
	if not _console.is_connected("command_executed", self, "_on_command_executed"):
		_console.connect("command_executed", self, "_on_command_executed")
	if _status and is_instance_valid(_status):
		_status.text = "READY"

func _exit_tree() -> void:
	if _console and is_instance_valid(_console):
		if _console.is_connected("log_added", self, "_on_log_added"):
			_console.disconnect("log_added", self, "_on_log_added")
		if _console.is_connected("logs_cleared", self, "_on_logs_cleared"):
			_console.disconnect("logs_cleared", self, "_on_logs_cleared")
		if _console.is_connected("command_executed", self, "_on_command_executed"):
			_console.disconnect("command_executed", self, "_on_command_executed")

func _ensure_console_singleton() -> void:
	var root = get_tree().root
	if not root:
		return
	var existing = root.get_node_or_null("OYS_Console")
	if existing:
		return
	var console = OYSConsoleScript.new()
	console.name = "OYS_Console"
	root.call_deferred("add_child", console)

func _on_text_entered(text: String) -> void:
	if not _console or (_input and not is_instance_valid(_input)):
		return
	var line = text.strip_edges()
	if line == "":
		return
	_append_line("SYS", ">_ " + line, "#00FF00") # High contrast green
	_console.enqueue_command(line)
	_history_index = -1
	_input.text = ""

func _on_input_gui(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if (key.control or key.command) and _is_zoom_in_key(key):
		accept_event()
		_change_font_size(1)
		return
	if (key.control or key.command) and _is_zoom_out_key(key):
		accept_event()
		_change_font_size(-1)
		return
	if key.shift and key.scancode == KEY_PAGEUP:
		accept_event()
		_scroll_by_page(-1)
		return
	if key.shift and key.scancode == KEY_PAGEDOWN:
		accept_event()
		_scroll_by_page(1)
		return
	if key.scancode == KEY_TAB:
		accept_event()
		_apply_autocomplete()
	elif key.scancode == KEY_UP:
		accept_event()
		_apply_history(-1)
	elif key.scancode == KEY_DOWN:
		accept_event()
		_apply_history(1)

func _on_shell_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
		focus_command_input()

func focus_command_input() -> void:
	if not _input:
		return
	_input.grab_focus()
	_input.caret_position = _input.text.length()

func _apply_autocomplete() -> void:
	if not _console or not _input or not is_instance_valid(_input):
		return
	var current = _input.text
	var candidates = _console.get_autocomplete_candidates(current)
	if candidates.empty():
		if _status and is_instance_valid(_status):
			_status.text = "No suggestions"
		return
	if candidates.size() == 1:
		_input.text = _replace_last_token(current, candidates[0])
		_input.caret_position = _input.text.length()
		if _status and is_instance_valid(_status):
			_status.text = "Autocomplete: " + candidates[0]
		return
	if _status and is_instance_valid(_status):
		_status.text = "%d suggestions" % candidates.size()
	_append_line("SYS", "Suggestions: " + ", ".join(candidates.slice(0, min(10, candidates.size()))), "#88CCFF")

func _apply_history(direction: int) -> void:
	if not _console:
		return
	var hist = _console.get_history()
	if hist.empty():
		return
	if _history_index == -1:
		_history_index = hist.size()
	_history_index = clamp(_history_index + direction, 0, hist.size())
	if _history_index == hist.size():
		_input.text = ""
	else:
		_input.text = hist[_history_index]
	_input.caret_position = _input.text.length()

func _replace_last_token(source: String, replacement: String) -> String:
	if source.strip_edges() == "":
		return replacement + " "
	var ends_with_space = source.ends_with(" ")
	if ends_with_space:
		return source + replacement + " "
	var idx = source.rfind(" ")
	if idx == -1:
		return replacement + " "
	return source.substr(0, idx + 1) + replacement + " "

func _render_full_output() -> void:
	if not _console or not _output or not is_instance_valid(_output):
		return
	_output.clear()
	for entry in _console.get_logs():
		_append_log_entry(entry)
	call_deferred("_scroll_output_to_end")

func _on_log_added(entry: Dictionary) -> void:
	if not _console or not _output or not is_instance_valid(_output):
		return
	if _console.get_filter_tag() != "" and entry.get("tag", "") != _console.get_filter_tag():
		return
	_append_log_entry(entry)

func _on_logs_cleared() -> void:
	if _output and is_instance_valid(_output):
		_output.clear()

func _on_command_executed(_command: String, success: bool, message: String) -> void:
	if _status and is_instance_valid(_status):
		_status.text = "OK" if success else "ERR: %s" % message

func _append_log_entry(entry: Dictionary) -> void:
	var tag = str(entry.get("tag", "SYS"))
	var text = _escape_bbcode(str(entry.get("text", "")))
	var color = str(entry.get("color", "#FFFFFF"))
	_append_line(tag, text, color)

func _append_line(tag: String, text: String, color: String) -> void:
	if not _output or not is_instance_valid(_output):
		return
	_output.append_bbcode("[color=%s][%s][/color] %s\n" % [color, tag, text])
	_scroll_output_to_end()
	var lc = _output.get_line_count()
	if lc > MAX_RENDER_LINES:
		_render_full_output()

func _escape_bbcode(text: String) -> String:
	return text.replace("[", "\\[").replace("]", "\\]")

func _scroll_output_to_end() -> void:
	if not _output or not is_instance_valid(_output):
		return
	var lc = _output.get_line_count()
	if lc > 0:
		_scroll_line_cursor = max(0, lc - 1)
		_output.scroll_to_line(_scroll_line_cursor)

func _scroll_by_page(direction: int) -> void:
	if not _output or not is_instance_valid(_output):
		return
	var lc = _output.get_line_count()
	if lc <= 0:
		return
	var page_size = 18
	_scroll_line_cursor = clamp(_scroll_line_cursor + (direction * page_size), 0, max(0, lc - 1))
	_output.scroll_to_line(_scroll_line_cursor)

func _is_zoom_in_key(key: InputEventKey) -> bool:
	if key.scancode == KEY_KP_ADD or key.scancode == KEY_EQUAL:
		return true
	var key_name = OS.get_scancode_string(key.scancode)
	return key_name == "+" or key_name.to_lower() == "plus"

func _is_zoom_out_key(key: InputEventKey) -> bool:
	return key.scancode == KEY_KP_SUBTRACT or key.scancode == KEY_MINUS

func _init_font_scaling() -> void:
	var base_font: Font = null
	if _input:
		base_font = _input.get_font("font")
	if base_font == null and _status:
		base_font = _status.get_font("font")
	if base_font is DynamicFont:
		var dyn = base_font as DynamicFont
		_font_size = int(dyn.size)
		_font_data = dyn.font_data
	_apply_font_overrides()

func _change_font_size(delta: int) -> void:
	_font_size = clamp(_font_size + delta, FONT_SIZE_MIN, FONT_SIZE_MAX)
	_apply_font_overrides()
	_status.text = "READY  FONT:%d" % _font_size

func _apply_font_overrides() -> void:
	if _font_data == null:
		return
	var f_label := DynamicFont.new()
	f_label.font_data = _font_data
	f_label.size = _font_size
	f_label.use_filter = true
	f_label.use_mipmaps = true

	var f_output := DynamicFont.new()
	f_output.font_data = _font_data
	f_output.size = max(FONT_SIZE_MIN, _font_size - 1)
	f_output.use_filter = true
	f_output.use_mipmaps = true

	if _prompt:
		_prompt.add_font_override("font", f_label)
	if _input:
		_input.add_font_override("font", f_label)
	if _status:
		_status.add_font_override("font", f_label)
	if _output:
		_output.add_font_override("normal_font", f_output)
