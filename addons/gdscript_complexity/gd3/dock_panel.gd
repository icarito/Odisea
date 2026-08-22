tool
extends Control
const _VERBOSE_TRACE = false
class_name ComplexityDockPanel

# Displays complexity analysis results and controls (Godot 3.x version)
# Motto: Know what to fix before you hate the project.

signal analyze_requested
signal export_requested(format)
signal config_requested
signal cancel_requested
signal open_requested(script_path, line)

const MOTTO = "Know what to fix before you hate the project."
const EMPTY_HINT = "Click Find what to fix — then open the red items first."

var analyze_button: Button = null
var cancel_button: Button = null
var progress_bar: ProgressBar = null
var top_fixes_tree: Tree = null
var god_scripts_tree: Tree = null
var results_tree: Tree = null
var config_button: Button = null
var export_button: MenuButton = null
var open_button: Button = null
var help_button: Button = null
var help_dialog = null
var motto_label: Label = null
var status_label: Label = null
var trend_label: Label = null
var explain_label: Label = null

var tree_root: TreeItem = null
var top_fixes_root: TreeItem = null
var god_scripts_root: TreeItem = null
var version_adapter = null
var _score_explainer = null

var _status_width = 90
var _cc_width = 45
var _cog_width = 55
var _confidence_width = 70
var _nest_width = 45
var _params_width = 55
var _loc_width = 45

var _cc_warn = 10
var _cc_fail = 20
var _cog_warn = 15
var _cog_fail = 30

func _ready():
	version_adapter = preload("res://addons/gdscript_complexity/version_adapter.gd").new()
	_setup_ui()

func _setup_ui():
	rect_min_size = Vector2(300, 0)

	var vbox = VBoxContainer.new()
	add_child(vbox)
	vbox.set_anchors_and_margins_preset(15)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	motto_label = Label.new()
	motto_label.text = MOTTO
	motto_label.autowrap = true
	vbox.add_child(motto_label)

	var button_row = HBoxContainer.new()
	vbox.add_child(button_row)

	analyze_button = Button.new()
	analyze_button.text = "Find what to fix"
	analyze_button.hint_tooltip = MOTTO
	analyze_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	analyze_button.connect("pressed", self, "_on_analyze_pressed")
	button_row.add_child(analyze_button)

	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel_button.connect("pressed", self, "_on_cancel_pressed")
	cancel_button.disabled = true
	button_row.add_child(cancel_button)

	config_button = Button.new()
	config_button.text = "Config"
	config_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	config_button.connect("pressed", self, "_on_config_pressed")
	button_row.add_child(config_button)

	export_button = MenuButton.new()
	export_button.text = "Export"
	export_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var popup = export_button.get_popup()
	popup.add_item("Export JSON")
	popup.add_item("Export CSV")
	popup.add_item("Export HTML")
	popup.connect("id_pressed", self, "_on_export_menu_selected")
	button_row.add_child(export_button)

	open_button = Button.new()
	open_button.text = "Open"
	open_button.hint_tooltip = "Open selected file/function in the script editor"
	open_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	open_button.connect("pressed", self, "_on_open_pressed")
	button_row.add_child(open_button)

	help_button = Button.new()
	help_button.text = "Help"
	help_button.hint_tooltip = "What CC, C-COG, confidence, and status labels mean"
	help_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	help_button.connect("pressed", self, "_on_help_pressed")
	button_row.add_child(help_button)

	help_dialog = load("res://addons/gdscript_complexity/gd3/help_dialog.gd").new()
	add_child(help_dialog)

	progress_bar = ProgressBar.new()
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.visible = false
	vbox.add_child(progress_bar)

	status_label = Label.new()
	status_label.text = EMPTY_HINT
	status_label.autowrap = true
	vbox.add_child(status_label)

	trend_label = Label.new()
	trend_label.text = ""
	trend_label.autowrap = true
	trend_label.visible = false
	vbox.add_child(trend_label)

	explain_label = Label.new()
	explain_label.text = "Select a function to see why it scored that way."
	explain_label.autowrap = true
	vbox.add_child(explain_label)

	var top_label = Label.new()
	top_label.text = "Top fixes (open these first)"
	vbox.add_child(top_label)

	top_fixes_tree = Tree.new()
	top_fixes_tree.rect_min_size = Vector2(0, 120)
	top_fixes_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_fixes_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_fixes_tree.size_flags_stretch_ratio = 0.35
	top_fixes_tree.columns = 4
	top_fixes_tree.set_column_titles_visible(true)
	top_fixes_tree.set_column_title(0, "What")
	top_fixes_tree.set_column_title(1, "Status")
	top_fixes_tree.set_column_title(2, "CC")
	top_fixes_tree.set_column_title(3, "C-COG")
	top_fixes_tree.set_column_expand(0, true)
	top_fixes_tree.set_column_expand(1, false)
	top_fixes_tree.set_column_expand(2, false)
	top_fixes_tree.set_column_expand(3, false)
	top_fixes_tree.set_column_min_width(0, 180)
	top_fixes_tree.set_column_min_width(1, 90)
	top_fixes_tree.set_column_min_width(2, 45)
	top_fixes_tree.set_column_min_width(3, 55)
	top_fixes_tree.connect("item_activated", self, "_on_top_fix_activated")
	top_fixes_tree.connect("item_selected", self, "_on_item_selected")
	vbox.add_child(top_fixes_tree)

	var god_label = Label.new()
	god_label.text = "Big scary files"
	vbox.add_child(god_label)

	god_scripts_tree = Tree.new()
	god_scripts_tree.rect_min_size = Vector2(0, 90)
	god_scripts_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	god_scripts_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	god_scripts_tree.size_flags_stretch_ratio = 0.25
	god_scripts_tree.columns = 5
	god_scripts_tree.set_column_titles_visible(true)
	god_scripts_tree.set_column_title(0, "File")
	god_scripts_tree.set_column_title(1, "Status")
	god_scripts_tree.set_column_title(2, "CC")
	god_scripts_tree.set_column_title(3, "C-COG")
	god_scripts_tree.set_column_title(4, "LOC")
	god_scripts_tree.set_column_expand(0, true)
	for col in range(1, 5):
		god_scripts_tree.set_column_expand(col, false)
	god_scripts_tree.set_column_min_width(0, 160)
	god_scripts_tree.set_column_min_width(1, 90)
	god_scripts_tree.set_column_min_width(2, 45)
	god_scripts_tree.set_column_min_width(3, 55)
	god_scripts_tree.set_column_min_width(4, 45)
	god_scripts_tree.connect("item_activated", self, "_on_god_script_activated")
	god_scripts_tree.connect("item_selected", self, "_on_item_selected")
	vbox.add_child(god_scripts_tree)

	var all_label = Label.new()
	all_label.text = "All results"
	vbox.add_child(all_label)

	results_tree = Tree.new()
	results_tree.set_anchors_and_margins_preset(15)
	results_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_tree.size_flags_stretch_ratio = 0.65
	results_tree.columns = 8
	results_tree.set_column_titles_visible(true)
	results_tree.set_column_title(0, "File/Function")
	results_tree.set_column_title(1, "Status")
	results_tree.set_column_title(2, "CC")
	results_tree.set_column_title(3, "C-COG")
	results_tree.set_column_title(4, "Confidence")
	results_tree.set_column_title(5, "Nest")
	results_tree.set_column_title(6, "Params")
	results_tree.set_column_title(7, "LOC")
	results_tree.set_column_expand(0, true)
	for col in range(1, 8):
		results_tree.set_column_expand(col, false)
	results_tree.set_column_min_width(0, 200)
	results_tree.set_column_min_width(1, _status_width)
	results_tree.set_column_min_width(2, _cc_width)
	results_tree.set_column_min_width(3, _cog_width)
	results_tree.set_column_min_width(4, _confidence_width)
	results_tree.set_column_min_width(5, _nest_width)
	results_tree.set_column_min_width(6, _params_width)
	results_tree.set_column_min_width(7, _loc_width)
	results_tree.connect("item_activated", self, "_on_item_activated")
	results_tree.connect("item_selected", self, "_on_item_selected")
	results_tree.connect("resized", self, "_on_tree_resized")
	vbox.add_child(results_tree)

	_score_explainer = load("res://addons/gdscript_complexity/src/core/score_explainer.gd").new()
	_clear_top_fixes_placeholder()
	_clear_god_scripts_placeholder()
	_apply_editor_theme()
	_update_column_widths()

func set_thresholds(cc_warn: int, cc_fail: int, cog_warn: int, cog_fail: int) -> void:
	_cc_warn = cc_warn
	_cc_fail = cc_fail
	_cog_warn = cog_warn
	_cog_fail = cog_fail

func readability_label(cc: int, cog: int) -> String:
	if cog >= _cog_fail or cc >= _cc_fail:
		return "Fix soon"
	if cog >= _cog_warn or cc >= _cc_warn:
		return "Hard to read"
	return "OK"

func _apply_editor_theme():
	if not Engine.is_editor_hint():
		return
	pass

func _on_analyze_pressed():
	if _VERBOSE_TRACE: print("[DockPanel] Analyze button pressed")
	emit_signal("analyze_requested")
	if _VERBOSE_TRACE: print("[DockPanel] Signal emitted")

func _on_cancel_pressed():
	emit_signal("cancel_requested")

func _on_config_pressed():
	emit_signal("config_requested")

func _on_export_menu_selected(id: int):
	var format = "json"
	if id == 1:
		format = "csv"
	elif id == 2:
		format = "html"
	emit_signal("export_requested", format)

func _on_open_pressed():
	var target = _get_selected_target()
	if target != null:
		emit_signal("open_requested", target["script_path"], target["line"])

func _on_help_pressed():
	if help_dialog == null:
		return
	if help_dialog.has_method("set_editor_theme"):
		var t = theme
		if t != null:
			help_dialog.set_editor_theme(t)
		else:
			help_dialog.set_editor_theme(Theme.new())
	if help_dialog.has_method("popup_help"):
		help_dialog.popup_help()
	else:
		help_dialog.popup_centered(Vector2(540, 500))

func _on_item_activated():
	var target = _get_selected_target_from(results_tree)
	if target != null:
		emit_signal("open_requested", target["script_path"], target["line"])

func _on_god_script_activated():
	var target = _get_selected_target_from(god_scripts_tree)
	if target != null:
		emit_signal("open_requested", target["script_path"], target["line"])

func _on_top_fix_activated():
	var target = _get_selected_target_from(top_fixes_tree)
	if target != null:
		emit_signal("open_requested", target["script_path"], target["line"])

func _on_item_selected():
	_set_open_button_enabled(_get_selected_target() != null)
	_update_explain_from_selection()

func set_explain(text: String) -> void:
	if explain_label == null:
		return
	if text == "":
		explain_label.text = "Select a function to see why it scored that way."
	else:
		explain_label.text = text

func _update_explain_from_selection() -> void:
	var target = _get_selected_target()
	if target == null:
		set_explain("")
		return
	if target.has("why") and str(target["why"]) != "":
		set_explain(str(target["why"]))
		return
	var cc = int(target.get("cc", 0))
	var cog = int(target.get("cog", 0))
	var cc_bd = target.get("cc_breakdown", {})
	var cog_bd = target.get("cog_breakdown", {})
	if typeof(cc_bd) != TYPE_DICTIONARY:
		cc_bd = {}
	if typeof(cog_bd) != TYPE_DICTIONARY:
		cog_bd = {}
	if _score_explainer != null and (cc_bd.size() > 0 or cog_bd.size() > 0):
		set_explain(_score_explainer.explain_function(cc, cog, cc_bd, cog_bd))
	else:
		set_explain("CC %d / C-COG %d — run analysis again for a full breakdown." % [cc, cog])

func _on_tree_resized():
	_update_column_widths()

func set_status(text: String):
	if status_label != null:
		status_label.text = text

func set_trend(text: String):
	if trend_label == null:
		return
	if text == "":
		trend_label.text = ""
		trend_label.visible = false
		return
	trend_label.text = text
	trend_label.visible = true

func set_progress(value: float, max_value: float = 100.0):
	if progress_bar != null:
		progress_bar.max_value = max_value
		progress_bar.value = value
		progress_bar.visible = (value > 0.0 and value < max_value)

func show_progress(show: bool):
	if progress_bar != null:
		progress_bar.visible = show

func clear_results():
	if results_tree != null:
		results_tree.clear()
		tree_root = null
	_clear_top_fixes_placeholder()
	_clear_god_scripts_placeholder()
	set_trend("")
	set_explain("")

func _clear_top_fixes_placeholder() -> void:
	if top_fixes_tree == null:
		return
	top_fixes_tree.clear()
	top_fixes_root = top_fixes_tree.create_item()
	top_fixes_root.set_text(0, "(Run Find what to fix)")
	top_fixes_root.set_selectable(0, false)

func _clear_god_scripts_placeholder() -> void:
	if god_scripts_tree == null:
		return
	god_scripts_tree.clear()
	god_scripts_root = god_scripts_tree.create_item()
	god_scripts_root.set_text(0, "(Run Find what to fix)")
	god_scripts_root.set_selectable(0, false)

func show_god_scripts(entries: Array) -> void:
	if god_scripts_tree == null:
		return
	god_scripts_tree.clear()
	god_scripts_root = god_scripts_tree.create_item()
	god_scripts_root.set_text(0, "Big scary files")
	god_scripts_root.set_selectable(0, false)

	if entries.empty():
		var none_item = god_scripts_tree.create_item(god_scripts_root)
		none_item.set_text(0, "No god-scripts spotted")
		none_item.set_text(1, "OK")
		none_item.set_selectable(0, false)
		return

	for entry in entries:
		var item = god_scripts_tree.create_item(god_scripts_root)
		var path = str(entry.get("script_path", ""))
		var label_text = str(entry.get("label", "Hard to read"))
		var cc = int(entry.get("cc", 0))
		var cog = int(entry.get("cog", 0))
		var loc = int(entry.get("loc_code", 0))
		var line = int(entry.get("line", 1))
		var reason = str(entry.get("reason_text", ""))
		item.set_text(0, path.get_file())
		item.set_text(1, label_text)
		item.set_text(2, str(cc))
		item.set_text(3, str(cog))
		item.set_text(4, str(loc))
		item.set_metadata(0, {
			"script_path": path,
			"line": max(line, 1),
			"cc": cc,
			"cog": cog,
			"why": reason
		})
		_tint_status(item, 1, label_text)
		item.set_selectable(0, true)
	god_scripts_root.set_collapsed(false)

func show_top_fixes(entries: Array) -> void:
	if top_fixes_tree == null:
		return
	top_fixes_tree.clear()
	top_fixes_root = top_fixes_tree.create_item()
	top_fixes_root.set_text(0, "Top fixes")
	top_fixes_root.set_selectable(0, false)

	if entries.empty():
		var none_item = top_fixes_tree.create_item(top_fixes_root)
		none_item.set_text(0, "Nothing urgent — keep going")
		none_item.set_text(1, "OK")
		none_item.set_selectable(0, false)
		return

	for entry in entries:
		var item = top_fixes_tree.create_item(top_fixes_root)
		var path = str(entry.get("script_path", ""))
		var func_name = str(entry.get("function", ""))
		var label_text = str(entry.get("label", "Fix soon"))
		var cc = int(entry.get("cc", 0))
		var cog = int(entry.get("cog", 0))
		var line = int(entry.get("line", 1))
		var display = "%s — %s()" % [path.get_file(), func_name]
		if func_name == "" or func_name == "(file)":
			display = path.get_file()
		item.set_text(0, display)
		item.set_text(1, label_text)
		item.set_text(2, str(cc))
		item.set_text(3, str(cog))
		item.set_metadata(0, {
			"script_path": path,
			"line": max(line, 1),
			"cc": cc,
			"cog": cog,
			"cc_breakdown": entry.get("cc_breakdown", {}),
			"cog_breakdown": entry.get("cog_breakdown", {}),
			"why": str(entry.get("why", ""))
		})
		_tint_status(item, 1, label_text)
		item.set_selectable(0, true)
	top_fixes_root.set_collapsed(false)

func add_file_result(
	file_path: String,
	cc: int,
	cog: int,
	confidence: float,
	nesting: int = 0,
	params: int = 0,
	loc: int = 0,
	cc_breakdown: Dictionary = {},
	cog_breakdown: Dictionary = {},
	why: String = ""
):
	if results_tree == null:
		return null

	if tree_root == null:
		tree_root = results_tree.create_item()
		tree_root.set_text(0, "Project Results")
		tree_root.set_selectable(0, false)

	var label_text = readability_label(cc, cog)
	var file_item = results_tree.create_item(tree_root)
	file_item.set_text(0, file_path.get_file())
	file_item.set_text(1, label_text)
	file_item.set_text(2, str(cc))
	file_item.set_text(3, str(cog))
	file_item.set_text(4, "%.2f" % confidence)
	file_item.set_text(5, str(nesting))
	file_item.set_text(6, str(params))
	file_item.set_text(7, str(loc))
	file_item.set_metadata(0, {
		"script_path": file_path,
		"line": 1,
		"cc": cc,
		"cog": cog,
		"cc_breakdown": cc_breakdown,
		"cog_breakdown": cog_breakdown,
		"why": why
	})
	_align_numeric_columns(file_item)
	_tint_status(file_item, 1, label_text)
	file_item.set_selectable(0, true)

	return file_item

func add_function_result(
	parent_item: TreeItem,
	func_name: String,
	cc: int,
	cog: int,
	script_path: String,
	line: int,
	cc_breakdown: Dictionary = {},
	cog_breakdown: Dictionary = {},
	why: String = "",
	status_override: String = ""
):
	if results_tree == null or parent_item == null:
		return null

	var label_text = status_override if status_override != "" else readability_label(cc, cog)
	var func_item = results_tree.create_item(parent_item)
	func_item.set_text(0, "  %s()" % func_name)
	func_item.set_text(1, label_text)
	func_item.set_text(2, str(cc))
	func_item.set_text(3, str(cog))
	func_item.set_text(4, "-")
	func_item.set_text(5, "-")
	func_item.set_text(6, "-")
	func_item.set_text(7, "-")
	var why_text = why
	if status_override == "Ignored" and why_text == "":
		why_text = "Ignored via # gdmetrics:ignore — still scored, hidden from Top fixes."
	elif status_override == "Pinned" and why_text != "":
		why_text = "Pinned. " + why_text
	func_item.set_metadata(0, {
		"script_path": script_path,
		"line": max(line, 1),
		"cc": cc,
		"cog": cog,
		"cc_breakdown": cc_breakdown,
		"cog_breakdown": cog_breakdown,
		"why": why_text
	})
	_align_numeric_columns(func_item)
	_tint_status(func_item, 1, label_text)
	func_item.set_selectable(0, true)

	return func_item

func _tint_status(item, col: int, label_text: String) -> void:
	if item == null:
		return
	var color = Color(0.45, 0.75, 0.45)
	if label_text == "Hard to read":
		color = Color(0.9, 0.75, 0.3)
	elif label_text == "Fix soon":
		color = Color(0.95, 0.4, 0.35)
	elif label_text == "Ignored":
		color = Color(0.55, 0.55, 0.55)
	elif label_text == "Pinned":
		color = Color(0.4, 0.55, 0.85)
	elif label_text == "Hot":
		color = Color(0.95, 0.55, 0.25)
	if item.has_method("set_custom_color"):
		item.call("set_custom_color", col, color)

func _get_selected_target():
	var from_top = _get_selected_target_from(top_fixes_tree)
	if from_top != null:
		return from_top
	var from_gods = _get_selected_target_from(god_scripts_tree)
	if from_gods != null:
		return from_gods
	return _get_selected_target_from(results_tree)

func _get_selected_target_from(tree):
	if tree == null:
		return null
	var item = tree.get_selected()
	if item == null:
		return null
	var data = item.get_metadata(0)
	if typeof(data) == TYPE_DICTIONARY and data.has("script_path"):
		return data
	return null

func _align_numeric_columns(item):
	if item == null:
		return
	if item.has_method("set_text_align"):
		for col in range(2, 8):
			item.call("set_text_align", col, HALIGN_CENTER)

func _set_open_button_enabled(enabled: bool):
	if open_button != null:
		open_button.disabled = not enabled

func _update_column_widths():
	if results_tree == null:
		return
	var total_width = results_tree.get_size().x
	if total_width <= 0:
		return
	var fixed_width = _status_width + _cc_width + _cog_width + _confidence_width + _nest_width + _params_width + _loc_width + 20
	var name_width = max(200, int(total_width - fixed_width))
	results_tree.set_column_min_width(0, name_width)
	results_tree.set_column_min_width(1, _status_width)
	results_tree.set_column_min_width(2, _cc_width)
	results_tree.set_column_min_width(3, _cog_width)
	results_tree.set_column_min_width(4, _confidence_width)
	results_tree.set_column_min_width(5, _nest_width)
	results_tree.set_column_min_width(6, _params_width)
	results_tree.set_column_min_width(7, _loc_width)

func set_analyze_button_enabled(enabled: bool):
	if analyze_button != null:
		analyze_button.disabled = not enabled

func set_cancel_button_enabled(enabled: bool):
	if cancel_button != null:
		cancel_button.disabled = not enabled
