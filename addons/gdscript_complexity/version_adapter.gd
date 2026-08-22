# class_name VersionAdapter  # Commented out to avoid parse-time cascade
extends Object

# Handles version detection and feature flags (Godot 3.x only)

var godot_version: Dictionary = {}
var is_godot_3: bool = false
var major_version: int = 0
var minor_version: int = 0

var features: Dictionary = {}

func _init():
	godot_version = Engine.get_version_info()
	major_version = godot_version.get("major", 0)
	minor_version = godot_version.get("minor", 0)
	
	is_godot_3 = (major_version == 3)
	
	_detect_features()

func _detect_features():
	features = {
		"match_statement": true,
		"await_keyword": false,
		"yield_keyword": true,
		"class_name_declaration": true,
		"extends_declaration": true,
		"static_func": true,
		"signal": true,
		"editor_annotations": false,
		"script_editor_api": false,
		"confidence_cap_3x": true
	}

func get_version_string() -> String:
	return "%d.%d.%d" % [major_version, minor_version, godot_version.get("patch", 0)]

func supports_match_statements() -> bool:
	return features.get("match_statement", false)

func supports_await() -> bool:
	return features.get("await_keyword", false)

func supports_yield() -> bool:
	return features.get("yield_keyword", false)

func supports_editor_annotations() -> bool:
	return features.get("editor_annotations", false)

func get_confidence_cap() -> float:
	return 0.90

func get_parser_mode() -> String:
	return "heuristic"

func should_skip_match() -> bool:
	return not supports_match_statements()

func get_annotation_api() -> String:
	return "set_error"

func is_supported_version() -> bool:
	return major_version == 3

func get_version_info() -> Dictionary:
	return {
		"major": major_version,
		"minor": minor_version,
		"patch": godot_version.get("patch", 0),
		"is_3x": is_godot_3,
		"supported": is_supported_version(),
		"features": features.duplicate()
	}
