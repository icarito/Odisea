extends Node

# VideoExporter.gd
# Captures replay frames and muxes them with an audio capture.

var is_exporting := false
var export_name := ""
var frame_index := 0
var export_dir := ""
var replay_path := ""
var _capture_video_frames := false

var _audio_record_effect: AudioEffectRecord = null
var _audio_record_bus_idx := -1
var _audio_record_effect_idx := -1
var _monitor_silence_effect: AudioEffectAmplify = null
var _monitor_silence_effect_idx := -1
var _audio_capture_path := ""
var _audio_capture_saved := false

var _saved_follow_active_camera = null
var _saved_follow_only_cinematics = null

const EXPORT_FPS := 60

func _ready():
	name = "VideoExporter"
	pause_mode = Node.PAUSE_MODE_PROCESS

func start_export(path: String) -> void:
	if not has_node("/root/ScreenshotQueue"):
		printerr("[VideoExporter] ScreenshotQueue missing! Cannot export.")
		return

	# Force rendering even in --no-window mode.
	get_viewport().render_target_update_mode = Viewport.UPDATE_ALWAYS

	export_name = path.get_file().get_basename()
	replay_path = path
	is_exporting = true
	_capture_video_frames = true
	frame_index = 0

	export_dir = "user://export_" + export_name
	var dir = Directory.new()
	if dir.dir_exists(export_dir):
		dir.open(export_dir)
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and (file_name.ends_with(".png") or file_name.ends_with(".wav")):
				dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		dir.make_dir_recursive(export_dir)

	print("[VideoExporter] Starting export to: ", export_dir)

	var sm = get_node_or_null("/root/SessionManager")
	if sm:
		if not sm.is_connected("replay_finished", self , "_on_replay_finished"):
			sm.connect("replay_finished", self , "_on_replay_finished")

	_configure_audio_manager_for_export()
	_start_audio_capture()

func _process(_delta):
	if not is_exporting:
		return
	# Runtime policies can re-mute Master in headless/focus events.
	_unmute_audio_for_export()

func capture_frame(viewport: Viewport) -> void:
	if not is_exporting or not _capture_video_frames:
		return
	if not viewport:
		return

	var tex = viewport.get_texture()
	if not tex:
		return

	var img = tex.get_data()
	img.flip_y()

	var queue = get_node("/root/ScreenshotQueue")
	var save_path = export_dir + "/frame_%05d.png" % frame_index
	queue.enqueue_screenshot(img, save_path)
	frame_index += 1

func _on_replay_finished(_success, _drift, _frames):
	if not is_exporting:
		return

	print("[VideoExporter] Replay finished. Finalizing export...")
	_capture_video_frames = false
	call_deferred("_finalize_export")

func _finalize_export() -> void:
	# Let one frame pass so AudioEffectRecord flushes final mix blocks.
	yield (get_tree(), "idle_frame")
	_stop_audio_capture()

	var queue = get_node_or_null("/root/ScreenshotQueue")
	if queue and queue.has_method("wait_for_empty"):
		queue.wait_for_empty()

	_restore_audio_manager_after_export()
	is_exporting = false
	_compile_video()

func _compile_video():
	var abs_dir = ProjectSettings.globalize_path(export_dir)
	var out_file = abs_dir + "/../" + export_name + "_export.mp4"
	var input_pattern = abs_dir + "/frame_%05d.png"
	var audio_input_path = ProjectSettings.globalize_path(_audio_capture_path)

	var args = []
	if _audio_capture_saved:
		args = [
			"-y",
			"-framerate", str(EXPORT_FPS),
			"-i", input_pattern,
			"-i", audio_input_path,
			"-map", "0:v:0",
			"-map", "1:a:0",
			"-c:v", "libx264",
			"-preset", "fast",
			"-crf", "18",
			"-pix_fmt", "yuv420p",
			"-c:a", "aac",
			"-b:a", "192k",
			"-shortest",
			out_file
		]
	else:
		args = [
			"-y",
			"-framerate", str(EXPORT_FPS),
			"-i", input_pattern,
			"-c:v", "libx264",
			"-preset", "fast",
			"-crf", "18",
			"-pix_fmt", "yuv420p",
			out_file
		]

	print("[VideoExporter] Executing ffmpeg: ", args)
	var output = []
	var exit_code = OS.execute("ffmpeg", args, true, output)

	if exit_code == 0:
		var final_msg = "\n=======================================================\n"
		final_msg += "🎥 [VideoExporter] SUCCESS!\n"
		final_msg += "📂 Video available at: " + out_file + "\n"
		final_msg += "=======================================================\n"
		print(final_msg)
	else:
		printerr("[VideoExporter] FFMPEG Failed with exit code ", exit_code)
		for line in output:
			printerr(line)

	get_tree().quit(0)

func _start_audio_capture() -> void:
	_audio_capture_saved = false
	_audio_capture_path = export_dir + "/audio_capture.wav"
	_unmute_audio_for_export()

	_audio_record_bus_idx = AudioServer.get_bus_index("Master")
	if _audio_record_bus_idx < 0:
		_audio_record_bus_idx = 0

	_audio_record_effect = AudioEffectRecord.new()
	_audio_record_effect_idx = AudioServer.get_bus_effect_count(_audio_record_bus_idx)
	AudioServer.add_bus_effect(_audio_record_bus_idx, _audio_record_effect)
	_audio_record_effect.set_recording_active(true)
	_apply_monitor_silence_if_requested()
	print("[VideoExporter] Audio capture started on bus index ", _audio_record_bus_idx)

func _stop_audio_capture() -> void:
	if _audio_record_effect and is_instance_valid(_audio_record_effect):
		_audio_record_effect.set_recording_active(false)
		var recording = _audio_record_effect.get_recording()
		if recording and recording.has_method("save_to_wav"):
			var err = recording.save_to_wav(_audio_capture_path)
			if err == OK:
				_audio_capture_saved = true
				print("[VideoExporter] Audio capture saved to: ", _audio_capture_path)
			else:
				printerr("[VideoExporter] Failed to save audio capture: ", _audio_capture_path, " err=", err)
		else:
			printerr("[VideoExporter] No audio recording data available.")

	_remove_monitor_silence_effect()
	_remove_audio_capture_effect()

func _remove_audio_capture_effect() -> void:
	if _audio_record_bus_idx < 0:
		_audio_record_effect = null
		_audio_record_effect_idx = -1
		return

	var bus_count = AudioServer.get_bus_effect_count(_audio_record_bus_idx)
	var removed := false
	if _audio_record_effect_idx >= 0 and _audio_record_effect_idx < bus_count:
		if AudioServer.get_bus_effect(_audio_record_bus_idx, _audio_record_effect_idx) == _audio_record_effect:
			AudioServer.remove_bus_effect(_audio_record_bus_idx, _audio_record_effect_idx)
			removed = true
	if not removed:
		for i in range(bus_count):
			if AudioServer.get_bus_effect(_audio_record_bus_idx, i) == _audio_record_effect:
				AudioServer.remove_bus_effect(_audio_record_bus_idx, i)
				break

	_audio_record_effect = null
	_audio_record_bus_idx = -1
	_audio_record_effect_idx = -1

func _apply_monitor_silence_if_requested() -> void:
	if not _should_silence_monitor_output():
		return
	if _audio_record_bus_idx < 0:
		return
	_monitor_silence_effect = AudioEffectAmplify.new()
	_monitor_silence_effect.volume_db = -80.0
	_monitor_silence_effect_idx = AudioServer.get_bus_effect_count(_audio_record_bus_idx)
	AudioServer.add_bus_effect(_audio_record_bus_idx, _monitor_silence_effect)

func _remove_monitor_silence_effect() -> void:
	if _audio_record_bus_idx < 0:
		_monitor_silence_effect = null
		_monitor_silence_effect_idx = -1
		return
	if not (_monitor_silence_effect and is_instance_valid(_monitor_silence_effect)):
		_monitor_silence_effect = null
		_monitor_silence_effect_idx = -1
		return

	var bus_count = AudioServer.get_bus_effect_count(_audio_record_bus_idx)
	var removed := false
	if _monitor_silence_effect_idx >= 0 and _monitor_silence_effect_idx < bus_count:
		if AudioServer.get_bus_effect(_audio_record_bus_idx, _monitor_silence_effect_idx) == _monitor_silence_effect:
			AudioServer.remove_bus_effect(_audio_record_bus_idx, _monitor_silence_effect_idx)
			removed = true
	if not removed:
		for i in range(bus_count):
			if AudioServer.get_bus_effect(_audio_record_bus_idx, i) == _monitor_silence_effect:
				AudioServer.remove_bus_effect(_audio_record_bus_idx, i)
				break

	_monitor_silence_effect = null
	_monitor_silence_effect_idx = -1

func _should_silence_monitor_output() -> bool:
	# Disabled: muting monitor output via bus effects can nullify AudioEffectRecord capture.
	return false

func _configure_audio_manager_for_export() -> void:
	var audio_manager = get_node_or_null("/root/AudioManager")
	if not (audio_manager and is_instance_valid(audio_manager)):
		return

	if _saved_follow_active_camera == null and "follow_active_camera_for_spatial_sfx" in audio_manager:
		_saved_follow_active_camera = audio_manager.follow_active_camera_for_spatial_sfx
	if _saved_follow_only_cinematics == null and "follow_active_camera_only_during_cinematics" in audio_manager:
		_saved_follow_only_cinematics = audio_manager.follow_active_camera_only_during_cinematics

	if "follow_active_camera_for_spatial_sfx" in audio_manager:
		audio_manager.follow_active_camera_for_spatial_sfx = true
	if "follow_active_camera_only_during_cinematics" in audio_manager:
		audio_manager.follow_active_camera_only_during_cinematics = false
	if audio_manager.has_method("_update_spatial_listener_for_cinematics"):
		audio_manager.call("_update_spatial_listener_for_cinematics")

func _restore_audio_manager_after_export() -> void:
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager and is_instance_valid(audio_manager):
		if _saved_follow_active_camera != null and "follow_active_camera_for_spatial_sfx" in audio_manager:
			audio_manager.follow_active_camera_for_spatial_sfx = bool(_saved_follow_active_camera)
		if _saved_follow_only_cinematics != null and "follow_active_camera_only_during_cinematics" in audio_manager:
			audio_manager.follow_active_camera_only_during_cinematics = bool(_saved_follow_only_cinematics)
		if audio_manager.has_method("_update_spatial_listener_for_cinematics"):
			audio_manager.call("_update_spatial_listener_for_cinematics")

	_saved_follow_active_camera = null
	_saved_follow_only_cinematics = null

func _unmute_audio_for_export() -> void:
	var master_idx = AudioServer.get_bus_index("Master")
	if master_idx < 0:
		master_idx = 0
	AudioServer.set_bus_mute(master_idx, false)

	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager and is_instance_valid(audio_manager):
		if audio_manager.has_method("_apply_headless_audio_mute"):
			audio_manager.call("_apply_headless_audio_mute", false)
		if audio_manager.has_method("_set_focus_audio_muted"):
			audio_manager.call("_set_focus_audio_muted", false)
