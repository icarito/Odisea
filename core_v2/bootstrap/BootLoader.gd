extends Node

export(String, FILE, "*.tscn,*.scn") var startup_scene_path := "res://core_v2/levels/BaseTerrace.tscn"
export(String) var loading_message := "Abriendo BaseTerrace..."
export(bool) var show_progress := true
export(int, 0, 60) var scene_manager_wait_frames := 12

var _started := false
var _fallback_started := false

func _ready() -> void:
	if Engine.editor_hint:
		return
	_mark_trace("boot_scene_ready", {"target_scene": startup_scene_path})
	var skip_reason := _get_skip_reason()
	if skip_reason != "":
		_mark_trace("boot_scene_autoload_skipped", {"reason": skip_reason})
		return
	call_deferred("_start_boot_transition")

func _start_boot_transition() -> void:
	if _started:
		return
	_started = true
	if startup_scene_path.strip_edges() == "":
		printerr("[BootLoader] startup_scene_path is empty.")
		return

	var scene_manager = get_node_or_null("/root/SceneManager")
	var wait_frames := max(0, scene_manager_wait_frames)
	while (scene_manager == null or not scene_manager.has_method("goto_scene")) and wait_frames > 0:
		wait_frames -= 1
		yield(get_tree(), "idle_frame")
		scene_manager = get_node_or_null("/root/SceneManager")
	_mark_trace("boot_loader_scene_request", {"path": startup_scene_path})
	if scene_manager and scene_manager.has_method("goto_scene"):
		if not scene_manager.is_connected("transition_failed", self, "_on_transition_failed"):
			scene_manager.connect("transition_failed", self, "_on_transition_failed")
		var state = scene_manager.goto_scene(startup_scene_path, {
			"transition": "loading",
			"show_loading": true,
			"show_progress": show_progress,
			"loading_message": loading_message,
			"fade_out": 0.0,
			"fade_in": 0.0,
			"audio_fade_out": 0.0,
			"audio_fade_in": 0.0,
			"preserve_player_state": false
		})
		if state is GDScriptFunctionState:
			yield(state, "completed")
		_notify_player_released()
		return

	_mark_trace("boot_loader_scene_request_fallback", {"path": startup_scene_path})
	_start_direct_scene_fallback("scene_manager_missing")

func _on_transition_failed(path: String, reason: String) -> void:
	if String(path) != startup_scene_path:
		return
	if _fallback_started:
		return
	printerr("[BootLoader] Interactive startup transition failed (%s). Falling back to direct change_scene." % reason)
	_mark_trace("boot_loader_transition_failed", {
		"path": path,
		"reason": reason
	})
	call_deferred("_start_direct_scene_fallback", reason)

func _start_direct_scene_fallback(reason: String = "") -> void:
	if _fallback_started:
		return
	_fallback_started = true
	_mark_trace("boot_loader_direct_fallback", {
		"path": startup_scene_path,
		"reason": reason
	})
	var err := get_tree().change_scene(startup_scene_path)
	if err != OK:
		printerr("[BootLoader] change_scene failed for %s (err=%d)" % [startup_scene_path, err])
	else:
		_notify_player_released()

# Tell the HTML shell (web exports) that the boot transition finished and
# the player is in control, so it can report total load time to the bridge.
func _notify_player_released() -> void:
	if not OS.has_feature("JavaScript"):
		return
	JavaScript.eval("window.OdiseaShell && window.OdiseaShell.playerReleased && window.OdiseaShell.playerReleased();", true)

func _get_skip_reason() -> String:
	if _is_test_suite():
		return "test_suite"
	if OS.get_environment("OYS_AUTO_RUN") != "":
		return "auto_run_script"

	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg = String(args[i])
		if arg == "--replay":
			return "cli_replay"
		if arg == "--run-script":
			return "cli_script"
		if arg == "--video-export" or arg == "--export-video":
			if i + 1 < args.size():
				var next = String(args[i + 1])
				if not next.begins_with("--") and (next.ends_with(".json") or next.ends_with(".oys")):
					return "video_export_replay"
	return ""

func _mark_trace(name: String, data: Dictionary = {}) -> void:
	var startup_trace = get_node_or_null("/root/StartupTrace")
	if startup_trace and startup_trace.has_method("mark"):
		startup_trace.mark(name, data)

func _is_test_suite() -> bool:
	if Engine.has_singleton("GdUnit3"):
		return Engine.get_singleton("GdUnit3").is_test_suite()
	return false
