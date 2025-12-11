extends CanvasLayer

onready var record_button: Button = $PanelContainer/Control/VBoxContainer/RecordButton
onready var stop_button: Button = $PanelContainer/Control/VBoxContainer/StopButton
onready var load_button: Button = $PanelContainer/Control/VBoxContainer/LoadButton
onready var pause_button: Button = $PanelContainer/Control/VBoxContainer/PlaybackControls/PauseButton
onready var resume_button: Button = $PanelContainer/Control/VBoxContainer/PlaybackControls/ResumeButton
onready var step_button: Button = $PanelContainer/Control/VBoxContainer/PlaybackControls/StepButton
onready var frame_label: Label = $PanelContainer/Control/VBoxContainer/FrameLabel
onready var file_dialog: FileDialog = $PanelContainer/FileDialog

func _ready() -> void:
	print("ReplayDebug: _ready called")
	print("record_button: ", record_button)
	print("stop_button: ", stop_button)
	print("load_button: ", load_button)
	print("pause_button: ", pause_button)
	print("resume_button: ", resume_button)
	print("step_button: ", step_button)
	print("frame_label: ", frame_label)
	print("file_dialog: ", file_dialog)
	
	if record_button:
		record_button.connect("pressed", self, "_on_RecordButton_pressed")
	if stop_button:
		stop_button.connect("pressed", self, "_on_StopButton_pressed")
	if load_button:
		load_button.connect("pressed", self, "_on_LoadButton_pressed")
	if pause_button:
		pause_button.connect("pressed", self, "_on_PauseButton_pressed")
	if resume_button:
		resume_button.connect("pressed", self, "_on_ResumeButton_pressed")
	if step_button:
		step_button.connect("pressed", self, "_on_StepButton_pressed")
	if file_dialog:
		file_dialog.connect("file_selected", self, "_on_FileDialog_file_selected")

	$PanelContainer.hide()

func _process(_delta: float) -> void:
	if ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		var total_frames = 0
		if ReplayManager.current_replay:
			total_frames = ReplayManager.current_replay.frames.size()
		frame_label.text = "Frame: %d / %d" % [ReplayManager.frame_index, total_frames]
	else:
		frame_label.text = ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		print("ReplayDebug: Mouse button pressed at ", event.position)

func _on_RecordButton_pressed() -> void:
	print("ReplayDebug: Record button pressed")
	ReplayManager.start_recording()

func _on_StopButton_pressed() -> void:
	print("ReplayDebug: Stop button pressed")
	if ReplayManager.mode == ReplayManager.ReplayMode.RECORDING:
		ReplayManager.stop_recording()
	elif ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		ReplayManager.stop_playback()

func _on_LoadButton_pressed() -> void:
	print("ReplayDebug: Load button pressed")
	file_dialog.popup_centered()

func _on_PauseButton_pressed() -> void:
	print("ReplayDebug: Pause button pressed")
	ReplayManager.playback_paused = true

func _on_ResumeButton_pressed() -> void:
	print("ReplayDebug: Resume button pressed")
	ReplayManager.playback_paused = false

func _on_StepButton_pressed() -> void:
	print("ReplayDebug: Step button pressed")
	if ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		ReplayManager.playback_paused = true
		ReplayManager.step_frame()

func _on_FileDialog_file_selected(path: String) -> void:
	ReplayManager.start_playback(path)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_menu"):
		print("ReplayDebug: Toggle action pressed, scene: ", get_tree().current_scene.name)
		if get_tree().current_scene.name != "Menu":
			print("ReplayDebug: Toggle pressed, visibility: ", not $PanelContainer.is_visible())
			$PanelContainer.set_visible(not $PanelContainer.is_visible())
			ReplayManager.is_replay_debug_visible = $PanelContainer.is_visible()
			get_node("/root/MouseCapture").show_cursor($PanelContainer.is_visible())
			get_tree().set_input_as_handled()
