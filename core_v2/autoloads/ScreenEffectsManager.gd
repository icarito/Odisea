extends Node

const ScreenEffectsOverlayScene = preload("res://core_v2/ui/overlay/ScreenEffectsOverlay.tscn")
const OVERLAY_UI_PATH := "/root/OverlayUIManager"

var _overlay: Node = null
var _warned_unavailable := false
var _script_cinematic_depth := 0

func show_script_cinematic_bars(immediate: bool = false) -> void:
	_script_cinematic_depth += 1
	_set_script_cinematic_visible(true, immediate)

func hide_script_cinematic_bars(immediate: bool = false) -> void:
	_script_cinematic_depth = max(0, _script_cinematic_depth - 1)
	_set_script_cinematic_visible(_script_cinematic_depth > 0, immediate)

func begin_death_cover(params: Dictionary = {}):
	if not _ensure_overlay():
		_warn_unavailable_once("begin_death_cover")
		return null
	_script_cinematic_depth = 0
	if _overlay.has_method("set_cinematic_bars_enabled"):
		_overlay.set_cinematic_bars_enabled(false, true)
	if _overlay.has_method("begin_death_cover"):
		return _overlay.begin_death_cover(params)
	return null

func end_death_cover(params: Dictionary = {}):
	if not _ensure_overlay():
		_warn_unavailable_once("end_death_cover")
		return null
	if _overlay.has_method("end_death_cover"):
		return _overlay.end_death_cover(params)
	return null

func reset(immediate: bool = true) -> void:
	_script_cinematic_depth = 0
	if not _ensure_overlay():
		return
	if _overlay.has_method("reset_effects"):
		_overlay.reset_effects(immediate)

func is_enabled() -> bool:
	var env = OS.get_environment("OYS_SCREEN_EFFECTS").strip_edges().to_lower()
	if env != "":
		if env in ["1", "true", "yes", "on"]:
			return true
		if env in ["0", "false", "no", "off"]:
			return false
	if OS.has_feature("Server"):
		return false
	return true

func _set_script_cinematic_visible(enabled: bool, immediate: bool) -> void:
	if not _ensure_overlay():
		_warn_unavailable_once("script_cinematic")
		return
	if _overlay.has_method("set_cinematic_bars_enabled"):
		_overlay.set_cinematic_bars_enabled(enabled, immediate)

func _ensure_overlay() -> bool:
	if not is_enabled():
		return false
	if is_instance_valid(_overlay):
		return true
	if not get_tree() or not is_instance_valid(get_tree().root):
		return false
	var overlay_ui = get_node_or_null(OVERLAY_UI_PATH)
	if overlay_ui and overlay_ui.has_method("ensure_overlay"):
		_overlay = overlay_ui.ensure_overlay("ScreenEffectsOverlay", ScreenEffectsOverlayScene, "Passive")
	else:
		_overlay = ScreenEffectsOverlayScene.instance()
		if is_instance_valid(_overlay):
			_overlay.name = "ScreenEffectsOverlay"
			get_tree().root.add_child(_overlay)
	return is_instance_valid(_overlay)

func _warn_unavailable_once(context: String) -> void:
	if _warned_unavailable:
		return
	_warned_unavailable = true
	push_warning("[ScreenEffectsManager] unavailable in '%s'. Screen effects disabled." % context)
