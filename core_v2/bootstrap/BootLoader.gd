extends Node

export(String, FILE, "*.tscn,*.scn") var startup_scene_path := "res://core_v2/levels/BaseTerrace.tscn"
export(String) var loading_message := "Abriendo BaseTerrace..."
export(bool) var show_progress := true

var _started := false

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
	_mark_trace("boot_loader_scene_request", {"path": startup_scene_path})
	if scene_manager and scene_manager.has_method("goto_scene"):
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
		return

	_mark_trace("boot_loader_scene_request_fallback", {"path": startup_scene_path})
	var err := get_tree().change_scene(startup_scene_path)
	if err != OK:
		printerr("[BootLoader] change_scene failed for %s (err=%d)" % [startup_scene_path, err])

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
