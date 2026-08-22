tool
extends Reference
class_name AnnotationManager

# Complexity findings for Godot 3.x (no script gutter API — console fallback only).

var script_editor: Object = null
var has_annotation_support: bool = false
var annotation_api: String = "none"
var version_adapter = null
var _supported_severities = ["error", "warning", "info"]

func _init(adapter = null):
	version_adapter = adapter
	_detect_annotation_support()

func _detect_annotation_support():
	has_annotation_support = false
	annotation_api = "none"
	if Engine.is_editor_hint():
		print("[ComplexityAnalyzer] Editor annotations not available in Godot 3.x")

func add_complexity_annotation(script_path: String, line: int, message: String, severity: String = "warning"):
	severity = _normalize_severity(severity)
	if script_path == "" or line < 1:
		_fallback_log(script_path, line, "Invalid annotation target", "warning")
		return
	_fallback_log(script_path, line, message, severity)

func add_cc_annotation(script_path: String, line: int, cc_value: int, threshold: int, severity: String = "warning"):
	var message = "High Cyclomatic Complexity: %d (threshold_fail: %d)" % [cc_value, threshold]
	add_complexity_annotation(script_path, line, message, severity)

func add_cog_annotation(script_path: String, line: int, cog_value: int, threshold: int, severity: String = "warning"):
	var message = "High Cognitive Complexity: %d (threshold_fail: %d)" % [cog_value, threshold]
	add_complexity_annotation(script_path, line, message, severity)

func add_cc_warning(script_path: String, line: int, cc_value: int, threshold: int):
	add_cc_annotation(script_path, line, cc_value, threshold, "warning")

func add_cog_warning(script_path: String, line: int, cog_value: int, threshold: int):
	add_cog_annotation(script_path, line, cog_value, threshold, "warning")

## Annotate functions that meet or exceed threshold_fail (same contract as gd4).
func annotate_file_results(file_result, cc_fail: int, cog_fail: int):
	if not file_result.success:
		return

	var script_path = file_result.file_path
	var annotated_any = false
	var scanner = load("res://addons/gdscript_complexity/src/core/directive_scanner.gd").new()
	var directives = file_result.per_function_directives
	if typeof(directives) != TYPE_DICTIONARY:
		directives = {}
	for func_info in file_result.functions:
		if scanner.is_ignored(func_info, directives):
			continue
		var fname = func_info.name
		var line = func_info.start_line
		if line < 1:
			line = 1
		if file_result.per_function_cc.has(fname):
			var cc = int(file_result.per_function_cc[fname])
			if cc >= cc_fail:
				add_cc_annotation(script_path, line, cc, cc_fail, "warning")
				annotated_any = true
		if file_result.per_function_cog.has(fname):
			var cog = int(file_result.per_function_cog[fname])
			if cog >= cog_fail:
				add_cog_annotation(script_path, line, cog, cog_fail, "warning")
				annotated_any = true
	scanner = null

	if not annotated_any and file_result.functions.size() == 0:
		if int(file_result.cc) >= cc_fail:
			add_cc_annotation(script_path, 1, int(file_result.cc), cc_fail, "warning")
		if int(file_result.cog) >= cog_fail:
			add_cog_annotation(script_path, 1, int(file_result.cog), cog_fail, "warning")

func clear_annotations(_script_path: String):
	pass

func clear_all_annotations():
	pass

func _fallback_log(script_path: String, line: int, message: String, severity: String):
	var log_message = "[ComplexityAnalyzer] %s:%d - %s: %s" % [script_path, line, severity.to_upper(), message]
	if severity == "error" or severity == "warning":
		push_warning(log_message)
	else:
		print(log_message)

func is_supported() -> bool:
	return has_annotation_support

func get_annotation_api() -> String:
	return annotation_api

func _normalize_severity(severity: String) -> String:
	if _supported_severities.has(severity):
		return severity
	return "warning"
