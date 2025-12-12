extends CanvasLayer

onready var status_label: Label = find_node("StatusLabel", true, false)
onready var stop_button: Button = find_node("StopButton", true, false)
onready var current_replay_label: Label = find_node("CurrentReplayLabel", true, false)
onready var playback_controls: Control = find_node("PlaybackControls", true, false)
onready var pause_button: Button = find_node("PauseButton", true, false)
onready var play_resume_button: Button = find_node("PlayResumeButton", true, false)
onready var step_button: Button = find_node("StepButton", true, false)
onready var rewind_button: Button = find_node("RewindButton", true, false)

var _recording_just_stopped: bool = false

func _ready() -> void:
	visible = false
	if stop_button:
		stop_button.connect("pressed", self, "_on_StopButton_pressed")
	if pause_button:
		pause_button.connect("pressed", self, "_on_PauseButton_pressed")
	if play_resume_button:
		play_resume_button.connect("pressed", self, "_on_PlayResumeButton_pressed")
	if step_button:
		step_button.connect("pressed", self, "_on_StepButton_pressed")
	if rewind_button:
		rewind_button.connect("pressed", self, "_on_RewindButton_pressed")
		
	if status_label:
		status_label.text = ""
	if current_replay_label:
		current_replay_label.text = ""
		
	ReplayManager.connect("mode_changed", self, "_on_mode_changed")
	ReplayManager.connect("recording_stopped", self, "_on_recording_stopped")

func _on_recording_stopped(frame_count: int) -> void:
	_recording_just_stopped = true
	if status_label:
		status_label.text = "Stopped. Recorded %d frames." % frame_count
		status_label.modulate = Color(1, 1, 1) # White
	if stop_button:
		stop_button.visible = false # Hide stop button, as it's stopped.
	if playback_controls:
		playback_controls.visible = false

func _on_mode_changed(new_mode: int) -> void:
	if new_mode == ReplayManager.ReplayMode.RECORDING:
		_recording_just_stopped = false
		visible = true
		if status_label:
			status_label.text = "Recording..."
			status_label.modulate = Color(1, 0, 0)  # Red
		if stop_button:
			stop_button.visible = true
		if current_replay_label:
			current_replay_label.visible = false
		if playback_controls:
			playback_controls.visible = false
			
	elif new_mode == ReplayManager.ReplayMode.PLAYBACK:
		_recording_just_stopped = false
		visible = true
		if status_label:
			status_label.text = "Playing..."
			status_label.modulate = Color(0, 1, 0)  # Green
		if stop_button:
			stop_button.visible = true
		if current_replay_label:
			current_replay_label.text = ReplayManager.current_replay_filename.get_basename()
			current_replay_label.visible = true
		if playback_controls:
			playback_controls.visible = true
			
	elif new_mode == ReplayManager.ReplayMode.PAUSED:
		_recording_just_stopped = false
		visible = true
		if status_label:
			status_label.text = "Paused..."
			status_label.modulate = Color(1, 1, 0)  # Yellow
		if stop_button:
			stop_button.visible = true
		if current_replay_label:
			current_replay_label.text = ReplayManager.current_replay_filename.get_basename()
			current_replay_label.visible = true
		if playback_controls:
			playback_controls.visible = true
			
	elif new_mode == ReplayManager.ReplayMode.LOADED:
		_recording_just_stopped = false
		visible = true
		if status_label:
			status_label.text = "Stopped. Ready to play"
			status_label.modulate = Color(0, 1, 1)  # Cyan
		if stop_button:
			stop_button.visible = true
		if current_replay_label:
			current_replay_label.text = ReplayManager.current_replay_filename.get_basename()
			current_replay_label.visible = true
		if playback_controls:
			playback_controls.visible = true
			
	else: # ReplayMode.NONE
		if _recording_just_stopped:
			_recording_just_stopped = false # Reset flag
			# Keep visible, but hide playback controls
			if playback_controls:
				playback_controls.visible = false
		else:
			visible = false

func _process(_delta: float) -> void:
	if not visible:
		return

	if ReplayManager.mode == ReplayManager.ReplayMode.RECORDING and not ReplayManager.recording_paused:
		if status_label and ReplayManager.current_replay:
			status_label.text = "Recording... %d" % len(ReplayManager.current_replay.frames)
	elif ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK and not ReplayManager.playback_paused:
		if status_label and ReplayManager.current_replay:
			var total_frames = len(ReplayManager.current_replay.frames)
			status_label.text = "Playing... %d / %d" % [ReplayManager.frame_index, total_frames]
	elif ReplayManager.mode == ReplayManager.ReplayMode.PAUSED:
		if status_label and ReplayManager.current_replay:
			var total_frames = len(ReplayManager.current_replay.frames)
			status_label.text = "Paused... %d / %d" % [ReplayManager.frame_index, total_frames]
	elif ReplayManager.mode == ReplayManager.ReplayMode.LOADED:
		if status_label:
			status_label.text = "Stopped. Ready to play"

func _on_StopButton_pressed() -> void:
	if ReplayManager.mode == ReplayManager.ReplayMode.RECORDING:
		ReplayManager.stop_recording()
	elif ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK or ReplayManager.mode == ReplayManager.ReplayMode.PAUSED:
		ReplayManager.stop_playback()

func _on_PauseButton_pressed() -> void:
	ReplayManager.pause_playback()

func _on_StepButton_pressed() -> void:
	if ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		ReplayManager.playback_paused = true
		ReplayManager.step_frame()

func _on_RewindButton_pressed() -> void:
	ReplayManager.rewind_playback()

func _on_PlayResumeButton_pressed() -> void:
	if ReplayManager.mode == ReplayManager.ReplayMode.LOADED:
		ReplayManager.start_loaded_playback()
	elif ReplayManager.mode == ReplayManager.ReplayMode.PAUSED:
		ReplayManager.resume_playback()
