extends CanvasLayer

onready var status_label: Label = find_node("StatusLabel", true, false)
onready var playback_controls: Container = find_node("PlaybackControls", true, false)
onready var recording_controls: Container = find_node("RecordingControls", true, false)
onready var stop_recording_button: Button = find_node("StopRecordingButton", true, false)
onready var pause_button: Button = find_node("PauseButton", true, false)
onready var play_resume_button: Button = find_node("PlayResumeButton", true, false)
onready var step_button: Button = find_node("StepButton", true, false)
onready var rewind_button: Button = find_node("RewindButton", true, false)
onready var step_back_button: Button = find_node("StepBackButton", true, false)
onready var eject_button: Button = find_node("EjectButton", true, false)
onready var frame_slider: HSlider = find_node("FrameSlider", true, false)

var _recording_just_stopped: bool = false
var playback_node: Node = null
var _auto_play_cli_replay := false
var _has_auto_played := false

func _ready() -> void:
	visible = false
	
	if ReplayManager:
		ReplayManager.connect("mode_changed", self, "_on_ReplayManager_mode_changed")
		ReplayManager.connect("recording_stopped", self, "_on_ReplayManager_recording_stopped")

	# Soporte para reproducción automática desde CLI
	var args = OS.get_cmdline_args()
	var replay_arg_idx = args.find("--replay")
	if replay_arg_idx != -1 and replay_arg_idx + 1 < args.size() and not GameGlobals.cli_replay_processed:
		GameGlobals.cli_replay_processed = true
		var replay_path = args[replay_arg_idx + 1]
		print("[ReplayRecordingOverlay] Reproduciendo replay desde CLI: ", replay_path)
		ReplayManager.start_playback(replay_path)
		# Marcar que es CLI para auto-play
		_auto_play_cli_replay = true

	if stop_recording_button:
		stop_recording_button.connect("pressed", self, "_on_StopRecordingButton_pressed")
	if pause_button:
		pause_button.connect("pressed", self, "_on_PauseButton_pressed")
	if play_resume_button:
		play_resume_button.connect("pressed", self, "_on_PlayResumeButton_pressed")
	if step_button:
		step_button.connect("pressed", self, "_on_StepButton_pressed")
	if rewind_button:
		rewind_button.connect("pressed", self, "_on_RewindButton_pressed")
	if step_back_button:
		step_back_button.connect("pressed", self, "_on_StepBackButton_pressed")
	if eject_button:
		eject_button.connect("pressed", self, "_on_EjectButton_pressed")
	if frame_slider:
		frame_slider.connect("value_changed", self, "_on_FrameSlider_value_changed")
		
	if status_label:
		status_label.text = ""
	
	_update_visibility()

func _on_ReplayManager_mode_changed(new_mode):
	_update_visibility()
       
	if new_mode == ReplayManager.ReplayMode.PLAYBACK:
		playback_node = ReplayManager.get_playback_node()
		if playback_node:
			playback_node.connect("frame_updated", self, "_on_frame_updated")
			playback_node.connect("playback_started", self, "_on_playback_started")
			# Si es CLI, iniciar reproducción automáticamente
			if _auto_play_cli_replay and not _has_auto_played:
				_has_auto_played = true
				_auto_play_cli_replay = false
				playback_node.start_loaded_playback()
	elif new_mode == ReplayManager.ReplayMode.NONE:
		if playback_node:
			if playback_node.is_connected("frame_updated", self, "_on_frame_updated"):
				playback_node.disconnect("frame_updated", self, "_on_frame_updated")
			if playback_node.is_connected("playback_started", self, "_on_playback_started"):
				playback_node.disconnect("playback_started", self, "_on_playback_started")
		playback_node = null

func _on_playback_started(total_frames):
	if frame_slider:
		frame_slider.max_value = total_frames - 1
		frame_slider.tick_count = total_frames / 10 # Optional: show some ticks

func _on_frame_updated(frame, _total_frames):
	if status_label:
		status_label.text = "Playback: Frame %d / %d" % [frame, frame_slider.max_value]
	if frame_slider and not frame_slider.has_focus(): 
		frame_slider.value = frame


func _on_FrameSlider_value_changed(value):
	if playback_node:
		playback_node.seek(value)


func _on_ReplayManager_recording_stopped(frame_count):
	if status_label:
		status_label.text = "Recording finished. %d frames." % frame_count
	_recording_just_stopped = true
	var timer = get_tree().create_timer(3.0)
	timer.connect("timeout", self, "_on_status_clear_timeout")

func _on_status_clear_timeout():
	if status_label:
		status_label.text = ""
	_recording_just_stopped = false
	_update_visibility()

func _update_visibility():
	if _recording_just_stopped:
		if not visible:
			UIManager.notify_overlay_shown()
		visible = true
		playback_controls.visible = false
		recording_controls.visible = false
		frame_slider.visible = false
		return

	var mode = ReplayManager.mode
	
	var should_be_visible = (mode != ReplayManager.ReplayMode.NONE)
	if should_be_visible != visible:
		if should_be_visible:
			UIManager.notify_overlay_shown()
		else:
			UIManager.notify_overlay_hidden()
	
	visible = should_be_visible

	if visible:
		match mode:
			ReplayManager.ReplayMode.RECORDING:
				recording_controls.visible = true
				playback_controls.visible = false
				frame_slider.visible = false
				if status_label:
					status_label.text = "Recording..."
				if recording_controls: recording_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ReplayManager.ReplayMode.PLAYBACK:
				recording_controls.visible = false
				playback_controls.visible = true
				frame_slider.visible = true
				if status_label:
					status_label.text = "Playback Mode"
				if playback_controls: playback_controls.mouse_filter = Control.MOUSE_FILTER_STOP
			ReplayManager.ReplayMode.STOPPED:
				recording_controls.visible = false
				playback_controls.visible = true
				frame_slider.visible = true
				if status_label:
					status_label.text = "Playback Stopped"
				if playback_controls: playback_controls.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		recording_controls.visible = false
		playback_controls.visible = false
		frame_slider.visible = false
		if status_label:
			status_label.text = ""


func _on_StopRecordingButton_pressed() -> void:
	ReplayManager.stop_recording()

func _on_PauseButton_pressed() -> void:
	if playback_node:
		playback_node.pause_playback()

func _on_StepButton_pressed() -> void:
	if playback_node:
		playback_node.step_frame()

func _on_RewindButton_pressed() -> void:
	if playback_node:
		playback_node.rewind_playback()

func _on_StepBackButton_pressed() -> void:
	if playback_node:
		playback_node.step_back_frame()

func _on_EjectButton_pressed() -> void:
	visible = false
	UIManager.notify_overlay_hidden() # Manually notify since we are hiding
	ReplayManager.eject_playback()

func _on_PlayResumeButton_pressed() -> void:
	if not playback_node:
		return
		
	if playback_node.playback_paused:
		playback_node.resume_playback()
	else:
		playback_node.start_loaded_playback()
