extends Node

const SubtitlesOverlayScene = preload("res://core_v2/ui/retro/SubtitlesOverlay.tscn")

var _overlay: Control = null
var _warned_unavailable := false

func show_subtitle(text: String, color: Color = Color.white, duration: float = 2.5) -> void:
	if not _ensure_overlay():
		_warn_unavailable_once("show_subtitle")
		return
	if _overlay and _overlay.has_method("show_subtitle"):
		_overlay.show_subtitle(text, color, duration)

func clear_subtitles(immediate: bool = false) -> void:
	if not _ensure_overlay():
		_warn_unavailable_once("clear_subtitles")
		return
	if _overlay and _overlay.has_method("clear_subtitles"):
		_overlay.clear_subtitles(immediate)

func is_enabled() -> bool:
	var env = OS.get_environment("OYS_SUBTITLES").strip_edges().to_lower()
	if env != "":
		if env in ["1", "true", "yes", "on"]:
			return true
		if env in ["0", "false", "no", "off"]:
			return false
	if OS.has_feature("Server"):
		return false
	return true

func _ensure_overlay() -> bool:
	if not is_enabled():
		return false
	if is_instance_valid(_overlay):
		return true
	if not get_tree() or not is_instance_valid(get_tree().root):
		return false
	_overlay = SubtitlesOverlayScene.instance()
	if not is_instance_valid(_overlay):
		return false
	_overlay.name = "SubtitlesOverlay"
	get_tree().root.add_child(_overlay)
	return true

func _warn_unavailable_once(context: String) -> void:
	if _warned_unavailable:
		return
	_warned_unavailable = true
	push_warning("[SubtitlesOverlayManager] unavailable in '%s'. Subtitles disabled." % context)
