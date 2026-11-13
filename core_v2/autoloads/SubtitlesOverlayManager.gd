extends Node

const SubtitlesOverlayScene = preload("res://core_v2/ui/retro/SubtitlesOverlay.tscn")
const OVERLAY_UI_PATH := "/root/OverlayUIManager"
const OVERLAY_SLOT_SUBTITLES := "HUD"

var _overlay: Node = null
var _warned_unavailable := false

func show_subtitle(text: String, color: Color = Color.white, duration: float = 2.5) -> void:
	if not _ensure_overlay():
		_warn_unavailable_once("show_subtitle")
		return
	if _overlay and _overlay.has_method("show_subtitle"):
		_overlay.show_subtitle(text, color, duration)

func show_hint(text: String, color: Color = Color(0.85, 1.0, 0.95), duration: float = 1.75) -> void:
	if not _ensure_overlay():
		_warn_unavailable_once("show_hint")
		return
	if _overlay and _overlay.has_method("show_hint"):
		_overlay.show_hint(text, color, duration)
	elif _overlay and _overlay.has_method("show_subtitle"):
		_overlay.show_subtitle(text, color, duration)

func clear_subtitles(immediate: bool = false) -> void:
	if not _ensure_overlay():
		_warn_unavailable_once("clear_subtitles")
		return
	if _overlay and _overlay.has_method("clear_subtitles"):
		_overlay.clear_subtitles(immediate)

# Read-only: rect del stack actual de subtitulos para que el HUD no lo tape.
# No crea el overlay si todavia no existe.
func get_stack_rect() -> Rect2:
	if not is_instance_valid(_overlay) or not _overlay.has_method("get_visible_stack_rect"):
		return Rect2()
	var rect = _overlay.call("get_visible_stack_rect")
	return rect if rect is Rect2 else Rect2()

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
	var overlay_ui = get_node_or_null(OVERLAY_UI_PATH)
	if overlay_ui and overlay_ui.has_method("ensure_overlay"):
		# Keep subtitles above passive post effects (cinematic/death bars).
		_overlay = overlay_ui.ensure_overlay("SubtitlesOverlay", SubtitlesOverlayScene, OVERLAY_SLOT_SUBTITLES)
	else:
		_overlay = SubtitlesOverlayScene.instance()
		if is_instance_valid(_overlay):
			_overlay.name = "SubtitlesOverlay"
			get_tree().root.add_child(_overlay)
	return is_instance_valid(_overlay)

func _warn_unavailable_once(context: String) -> void:
	if _warned_unavailable:
		return
	_warned_unavailable = true
	push_warning("[SubtitlesOverlayManager] unavailable in '%s'. Subtitles disabled." % context)
