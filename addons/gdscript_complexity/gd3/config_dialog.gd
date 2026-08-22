tool
extends WindowDialog
class_name ConfigDialog

const ADDON_ROOT := "res://addons/gdscript_complexity"
const SRC_ROOT := ADDON_ROOT + "/src"

# Godot 3 config UI. Must NOT inherit the project's game theme
# (e.g. Ball2Box theme.tres) or fonts/buttons explode.

signal config_saved

var config_manager = null
var config_path: String = "res://complexity_config.json"
var _editor_theme: Theme = null

var cc_warn_spin: SpinBox = null
var cc_fail_spin: SpinBox = null
var cog_warn_spin: SpinBox = null
var cog_fail_spin: SpinBox = null
var include_edit: TextEdit = null
var exclude_edit: TextEdit = null
var parser_mode_option: OptionButton = null

func _init():
	window_title = "Complexity Analyzer Configuration"
	resizable = true
	rect_min_size = Vector2(540, 500)

func _ready():
	_setup_ui()
	_apply_safe_theme()
	call_deferred("_load_config")

func set_editor_theme(editor_theme: Theme) -> void:
	_editor_theme = editor_theme
	_apply_safe_theme()

func _apply_safe_theme() -> void:
	# Prefer editor theme; otherwise a blank Theme so project theme/custom is ignored.
	if _editor_theme != null:
		theme = _editor_theme
	else:
		theme = Theme.new()

func popup_config(size: Vector2 = Vector2(540, 500)) -> void:
	_apply_safe_theme()
	if size.x < 400:
		size = Vector2(540, 500)
	popup_centered(size)

func _setup_ui():
	var existing = find_node("ConfigRoot", true, false)
	if existing != null:
		existing.free()

	var root = MarginContainer.new()
	root.name = "ConfigRoot"
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.margin_left = 12
	root.margin_right = -12
	root.margin_top = 12
	root.margin_bottom = -12
	add_child(root)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_constant_override("separation", 8)
	root.add_child(vbox)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.rect_min_size = Vector2(500, 320)
	vbox.add_child(scroll)

	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.rect_min_size = Vector2(480, 0)
	content.add_constant_override("separation", 10)
	scroll.add_child(content)

	var cc_group = _create_group("Cyclomatic Complexity")
	content.add_child(cc_group)
	var cc_warn_row = _create_label_spin_row("Warning Threshold:", 10)
	cc_group.add_child(cc_warn_row)
	cc_warn_spin = cc_warn_row.get_node("Spin")
	var cc_fail_row = _create_label_spin_row("Fail Threshold:", 20)
	cc_group.add_child(cc_fail_row)
	cc_fail_spin = cc_fail_row.get_node("Spin")

	var cog_group = _create_group("Cognitive Complexity")
	content.add_child(cog_group)
	var cog_warn_row = _create_label_spin_row("Warning Threshold:", 15)
	cog_group.add_child(cog_warn_row)
	cog_warn_spin = cog_warn_row.get_node("Spin")
	var cog_fail_row = _create_label_spin_row("Fail Threshold:", 30)
	cog_group.add_child(cog_fail_row)
	cog_fail_spin = cog_fail_row.get_node("Spin")

	var parser_group = _create_group("Parser Settings")
	content.add_child(parser_group)
	var parser_row = HBoxContainer.new()
	parser_row.add_constant_override("separation", 8)
	parser_group.add_child(parser_row)
	var parser_label = Label.new()
	parser_label.text = "Parser Mode:"
	parser_label.rect_min_size.x = 160
	parser_label.valign = Label.VALIGN_CENTER
	parser_row.add_child(parser_label)
	parser_mode_option = OptionButton.new()
	parser_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parser_mode_option.add_item("fast")
	parser_mode_option.add_item("balanced")
	parser_mode_option.add_item("thorough")
	parser_row.add_child(parser_mode_option)

	var include_group = _create_group("Include Patterns (one per line)")
	content.add_child(include_group)
	include_edit = TextEdit.new()
	include_edit.rect_min_size = Vector2(0, 72)
	include_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	include_edit.wrap_enabled = false
	include_group.add_child(include_edit)

	var exclude_group = _create_group("Exclude Patterns (one per line)")
	content.add_child(exclude_group)
	exclude_edit = TextEdit.new()
	exclude_edit.rect_min_size = Vector2(0, 72)
	exclude_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exclude_edit.wrap_enabled = false
	exclude_group.add_child(exclude_edit)

	var button_row = HBoxContainer.new()
	button_row.add_constant_override("separation", 8)
	button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(button_row)

	var reset_button = Button.new()
	reset_button.text = "Reset to Defaults"
	reset_button.connect("pressed", self, "_on_reset_pressed")
	button_row.add_child(reset_button)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_child(spacer)

	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.connect("pressed", self, "_on_cancel_pressed")
	button_row.add_child(cancel_button)

	var ok_button = Button.new()
	ok_button.text = "OK"
	ok_button.connect("pressed", self, "_on_ok_pressed")
	button_row.add_child(ok_button)

func _create_group(title: String) -> VBoxContainer:
	var group = VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_constant_override("separation", 4)

	var label = Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(label)

	return group

func _create_label_spin_row(label_text: String, default_value: int) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_constant_override("separation", 8)

	var label = Label.new()
	label.text = label_text
	label.rect_min_size.x = 160
	label.valign = Label.VALIGN_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var spin = SpinBox.new()
	spin.name = "Spin"
	spin.min_value = 0
	spin.max_value = 1000
	spin.value = default_value
	spin.rect_min_size.x = 120
	spin.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.add_child(spin)

	return row

func _load_config():
	if config_manager == null:
		return

	var config = config_manager.get_config()

	if cc_warn_spin != null:
		cc_warn_spin.value = config.cc_config["threshold_warn"]
	if cc_fail_spin != null:
		cc_fail_spin.value = config.cc_config["threshold_fail"]
	if cog_warn_spin != null:
		cog_warn_spin.value = config.cog_config["threshold_warn"]
	if cog_fail_spin != null:
		cog_fail_spin.value = config.cog_config["threshold_fail"]

	if parser_mode_option != null:
		var mode = config.parser_config["parser_mode"]
		if mode == "fast":
			parser_mode_option.selected = 0
		elif mode == "balanced":
			parser_mode_option.selected = 1
		elif mode == "thorough":
			parser_mode_option.selected = 2

	if include_edit != null:
		var include_text = ""
		for pattern in config.include_patterns:
			include_text += pattern + "\n"
		include_edit.text = include_text.strip_edges()

	if exclude_edit != null:
		var exclude_text = ""
		for pattern in config.exclude_patterns:
			exclude_text += pattern + "\n"
		exclude_edit.text = exclude_text.strip_edges()

func _save_config() -> bool:
	if config_manager == null:
		return false

	var config = config_manager.get_config()

	config.cc_config["threshold_warn"] = int(cc_warn_spin.value)
	config.cc_config["threshold_fail"] = int(cc_fail_spin.value)
	config.cog_config["threshold_warn"] = int(cog_warn_spin.value)
	config.cog_config["threshold_fail"] = int(cog_fail_spin.value)

	var mode_index = parser_mode_option.selected
	if mode_index == 0:
		config.parser_config["parser_mode"] = "fast"
	elif mode_index == 1:
		config.parser_config["parser_mode"] = "balanced"
	else:
		config.parser_config["parser_mode"] = "thorough"

	var include_patterns = []
	for line in include_edit.text.split("\n"):
		line = line.strip_edges()
		if line != "":
			include_patterns.append(line)
	config.include_patterns = include_patterns

	var exclude_patterns = []
	for line in exclude_edit.text.split("\n"):
		line = line.strip_edges()
		if line != "":
			exclude_patterns.append(line)
	config.exclude_patterns = exclude_patterns

	if not _validate_config(config):
		return false

	return _write_config_file(config)

func _validate_config(config) -> bool:
	if config.cc_config["threshold_warn"] < 0 or config.cc_config["threshold_fail"] < 0:
		OS.alert("CC thresholds must be >= 0", "Validation Error")
		return false

	if config.cog_config["threshold_warn"] < 0 or config.cog_config["threshold_fail"] < 0:
		OS.alert("C-COG thresholds must be >= 0", "Validation Error")
		return false

	if config.include_patterns.size() == 0:
		OS.alert("At least one include pattern is required", "Validation Error")
		return false

	return true

func _prettify_json(value, indent: String = "\t", current_indent: String = "") -> String:
	var result = ""

	if value is Dictionary:
		if value.empty():
			return "{}"
		result = "{\n"
		var keys = value.keys()
		for i in range(keys.size()):
			var key = keys[i]
			result += current_indent + indent + '"' + str(key).replace('"', '\\"') + '": '
			result += _prettify_json(value[key], indent, current_indent + indent)
			if i < keys.size() - 1:
				result += ","
			result += "\n"
		result += current_indent + "}"
	elif value is Array:
		if value.empty():
			return "[]"
		result = "[\n"
		for i in range(value.size()):
			result += current_indent + indent
			result += _prettify_json(value[i], indent, current_indent + indent)
			if i < value.size() - 1:
				result += ","
			result += "\n"
		result += current_indent + "]"
	elif value is String:
		result = '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
	elif value is bool:
		result = "true" if value else "false"
	elif value == null:
		result = "null"
	else:
		result = str(value)

	return result

func _write_config_file(config) -> bool:
	var config_dict = {
		"include": config.include_patterns,
		"exclude": config.exclude_patterns,
		"cc": {
			"threshold_warn": config.cc_config["threshold_warn"],
			"threshold_fail": config.cc_config["threshold_fail"]
		},
		"cog": {
			"threshold_warn": config.cog_config["threshold_warn"],
			"threshold_fail": config.cog_config["threshold_fail"]
		},
		"parser": {
			"parser_mode": config.parser_config["parser_mode"]
		}
	}

	var json_string = _prettify_json(config_dict)

	var file = File.new()
	if file.open(config_path, File.WRITE) != OK:
		OS.alert("Failed to write config file: %s" % config_path, "Error")
		return false

	file.store_string(json_string)
	file.close()

	config_manager.load_config(config_path)
	emit_signal("config_saved")
	return true

func _on_reset_pressed():
	if config_manager == null:
		return
	config_manager = load(SRC_ROOT + "/config_manager.gd").new()
	_load_config()

func _on_ok_pressed():
	if _save_config():
		hide()

func _on_cancel_pressed():
	hide()

func set_config_manager(manager):
	config_manager = manager
	if is_inside_tree():
		_load_config()

func set_config_path(path: String):
	config_path = path
