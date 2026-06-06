extends Node

const PlayerHintOverlayScene = preload("res://core_v2/ui/overlay/PlayerHintOverlay.tscn")
const OVERLAY_UI_PATH := "/root/OverlayUIManager"
const OVERLAY_SLOT_HUD := "HUD"
const MAX_HINT_DURATION := 30.0

var _overlay: Node = null
var _warned_unavailable := false
var _interaction_text := ""
var _manual_text := ""
var _status_text := ""
var _manual_expires_at := 0.0
var _status_expires_at := 0.0
var _explicit_interactive := true
var _refresh_timer: Timer = null

func _ready() -> void:
	_ensure_refresh_timer()
	_refresh_visible_hint()

func show_interaction_hint(text: String) -> void:
	_interaction_text = text.strip_edges()
	_refresh_visible_hint()

func clear_interaction_hint() -> void:
	if _interaction_text == "":
		return
	_interaction_text = ""
	_refresh_visible_hint()

func show_manual_hint(text: String, duration: float = MAX_HINT_DURATION) -> void:
	var clean_text := text.strip_edges()
	if clean_text == "":
		clear_manual_hint()
		return
	if not _is_runtime_interactive():
		return
	_manual_text = clean_text
	var clamped_duration := clamp(duration, 0.05, MAX_HINT_DURATION)
	_manual_expires_at = _now_sec() + clamped_duration
	_refresh_visible_hint()

func clear_manual_hint() -> void:
	if _manual_text == "":
		return
	_manual_text = ""
	_manual_expires_at = 0.0
	_refresh_visible_hint()

func show_status_hint(text: String, duration: float = 2.0) -> void:
	var clean_text := text.strip_edges()
	if clean_text == "":
		clear_status_hint()
		return
	if not _is_runtime_interactive():
		return
	_status_text = clean_text
	_status_expires_at = _now_sec() + clamp(duration, 0.05, MAX_HINT_DURATION)
	_refresh_visible_hint()

func clear_status_hint() -> void:
	if _status_text == "":
		return
	_status_text = ""
	_status_expires_at = 0.0
	_refresh_visible_hint()

func set_interactive(enabled: bool) -> void:
	_explicit_interactive = enabled
	_refresh_visible_hint()

func is_enabled() -> bool:
	var env = OS.get_environment("ODISEA_PLAYER_HINTS").strip_edges().to_lower()
	if env != "":
		if env in ["1", "true", "yes", "on"]:
			return true
		if env in ["0", "false", "no", "off"]:
			return false
	if OS.has_feature("Server"):
		return false
	return true

func get_visible_text() -> String:
	if not _is_runtime_interactive():
		return ""
	_prune_expired_manual()
	_prune_expired_status()
	if _status_text != "":
		return _status_text
	if _manual_text != "":
		return _manual_text
	return _interaction_text

func _refresh_visible_hint() -> void:
	_prune_expired_manual()
	_prune_expired_status()
	var text := get_visible_text()
	if text == "":
		if is_instance_valid(_overlay) and _overlay.has_method("clear_hint_text"):
			_overlay.clear_hint_text()
		return
	if not _ensure_overlay():
		_warn_unavailable_once("show_hint")
		return
	if _overlay and _overlay.has_method("set_hint_text"):
		var mode := "status" if _status_text != "" else "hint"
		if _overlay.has_method("set_hint_mode"):
			_overlay.set_hint_mode(mode)
		_overlay.set_hint_text(text)

func _prune_expired_manual() -> void:
	if _manual_text == "":
		return
	if _now_sec() >= _manual_expires_at:
		_manual_text = ""
		_manual_expires_at = 0.0

func _prune_expired_status() -> void:
	if _status_text == "":
		return
	if _now_sec() >= _status_expires_at:
		_status_text = ""
		_status_expires_at = 0.0

func _ensure_overlay() -> bool:
	if not is_enabled():
		return false
	if is_instance_valid(_overlay):
		return true
	if not get_tree() or not is_instance_valid(get_tree().root):
		return false
	var overlay_ui = get_node_or_null(OVERLAY_UI_PATH)
	if overlay_ui and overlay_ui.has_method("ensure_overlay"):
		_overlay = overlay_ui.ensure_overlay("PlayerHintOverlay", PlayerHintOverlayScene, OVERLAY_SLOT_HUD)
	else:
		_overlay = PlayerHintOverlayScene.instance()
		if is_instance_valid(_overlay):
			_overlay.name = "PlayerHintOverlay"
			get_tree().root.add_child(_overlay)
	return is_instance_valid(_overlay)

func _is_runtime_interactive() -> bool:
	if not _explicit_interactive:
		return false
	var screen_fx = get_node_or_null("/root/ScreenEffectsManager")
	if screen_fx:
		var depth = screen_fx.get("_script_cinematic_depth")
		if typeof(depth) == TYPE_INT and int(depth) > 0:
			return false
	var player = _find_player()
	if player and "input_provider" in player and is_instance_valid(player.input_provider):
		if not bool(player.input_provider.hardware_input_enabled):
			return false
	return true

func _find_player() -> Node:
	var session = get_node_or_null("/root/SessionManager")
	if session and "player" in session and is_instance_valid(session.player):
		return session.player
	if get_tree():
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			return players[0]
	return null

func _ensure_refresh_timer() -> void:
	if _refresh_timer:
		return
	_refresh_timer = Timer.new()
	_refresh_timer.name = "HintRefreshTimer"
	_refresh_timer.wait_time = 0.2
	_refresh_timer.one_shot = false
	_refresh_timer.autostart = true
	add_child(_refresh_timer)
	_refresh_timer.connect("timeout", self, "_on_refresh_timer_timeout")

func _on_refresh_timer_timeout() -> void:
	_refresh_visible_hint()

func _now_sec() -> float:
	return OS.get_ticks_msec() / 1000.0

func _warn_unavailable_once(context: String) -> void:
	if _warned_unavailable:
		return
	_warned_unavailable = true
	push_warning("[PlayerHintManager] unavailable in '%s'. Player hints disabled." % context)
