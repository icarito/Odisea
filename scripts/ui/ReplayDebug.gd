extends PanelContainer

onready var record_button: Button = $CanvasLayer/VBoxContainer/RecordButton
onready var stop_button: Button = $CanvasLayer/VBoxContainer/StopButton
onready var load_button: Button = $CanvasLayer/VBoxContainer/LoadButton
onready var pause_button: Button = $CanvasLayer/VBoxContainer/PlaybackControls/PauseButton
onready var resume_button: Button = $CanvasLayer/VBoxContainer/PlaybackControls/ResumeButton
onready var step_button: Button = $CanvasLayer/VBoxContainer/PlaybackControls/StepButton
onready var frame_label: Label = $CanvasLayer/VBoxContainer/FrameLabel
onready var file_dialog: FileDialog = $CanvasLayer/FileDialog

func _ready() -> void:
	record_button.connect("pressed", self, "_on_RecordButton_pressed")
	stop_button.connect("pressed", self, "_on_StopButton_pressed")
	load_button.connect("pressed", self, "_on_LoadButton_pressed")
	pause_button.connect("pressed", self, "_on_PauseButton_pressed")
	resume_button.connect("pressed", self, "_on_ResumeButton_pressed")
	step_button.connect("pressed", self, "_on_StepButton_pressed")
	file_dialog.connect("file_selected", self, "_on_FileDialog_file_selected")

	hide()

func _process(_delta: float) -> void:
	if ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		var total_frames = 0
		if ReplayManager.current_replay:
			total_frames = ReplayManager.current_replay.frames.size()
		frame_label.text = "Frame: %d / %d" % [ReplayManager.frame_index, total_frames]
	else:
		frame_label.text = ""

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_replay_menu"):
		set_visible(not is_visible())
		get_tree().set_input_as_handled()

func _on_RecordButton_pressed() -> void:
	ReplayManager.start_recording()

func _on_StopButton_pressed() -> void:
	if ReplayManager.mode == ReplayManager.ReplayMode.RECORDING:
		ReplayManager.stop_recording()
	elif ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		ReplayManager.stop_playback()

func _on_LoadButton_pressed() -> void:
	file_dialog.popup_centered()

func _on_PauseButton_pressed() -> void:
	ReplayManager.playback_paused = true

func _on_ResumeButton_pressed() -> void:
	ReplayManager.playback_paused = false

func _on_StepButton_pressed() -> void:
	if ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		ReplayManager.playback_paused = true
		ReplayManager.step_frame()

func _on_FileDialog_file_selected(path: String) -> void:
	ReplayManager.start_playback(path)
