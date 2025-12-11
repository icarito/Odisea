extends CanvasLayer

onready var item_list: ItemList = find_node("ItemList", true, false)
onready var start_recording_button: Button = find_node("StartRecordingButton", true, false)
onready var load_button: Button = find_node("LoadReplayButton", true, false)
onready var reset_button: Button = find_node("ResetButton", true, false)
onready var pause_button: Button = find_node("PauseButton", true, false)
onready var resume_button: Button = find_node("ResumeButton", true, false)
onready var step_button: Button = find_node("StepButton", true, false)
onready var playback_controls: Control = find_node("PlaybackControls", true, false)

func _ready() -> void:
	visible = false
	if start_recording_button:
		start_recording_button.connect("pressed", self, "_on_StartRecordingButton_pressed")
	if load_button:
		load_button.connect("pressed", self, "_on_LoadReplayButton_pressed")
	if reset_button:
		reset_button.connect("pressed", self, "_on_ResetButton_pressed")
	if pause_button:
		pause_button.connect("pressed", self, "_on_PauseButton_pressed")
	if resume_button:
		resume_button.connect("pressed", self, "_on_ResumeButton_pressed")
	if step_button:
		step_button.connect("pressed", self, "_on_StepButton_pressed")
	ReplayManager.connect("mode_changed", self, "_on_mode_changed")
	_refresh_replay_list()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_menu"):
		if get_tree().current_scene.name != "Menu":
			visible = !visible
			ReplayManager.is_replay_debug_visible = visible
			get_node("/root/MouseCapture").show_cursor(visible)
			get_tree().set_input_as_handled()

func _refresh_replay_list() -> void:
	if item_list:
		item_list.clear()
		var replays = ReplayManager.get_available_replays()
		for replay in replays:
			item_list.add_item(replay)

func _on_mode_changed(new_mode: int) -> void:
	if new_mode == ReplayManager.ReplayMode.PLAYBACK or new_mode == ReplayManager.ReplayMode.RECORDING:
		if playback_controls:
			playback_controls.visible = (new_mode == ReplayManager.ReplayMode.PLAYBACK)
		# Panel stays visible if toggled, but controls update
	else:
		if playback_controls:
			playback_controls.visible = false

func _on_StartRecordingButton_pressed() -> void:
	ReplayManager.start_recording()

func _on_LoadReplayButton_pressed() -> void:
	if item_list:
		var selected = item_list.get_selected_items()
		if selected.size() > 0:
			var index = selected[0]
			if index < item_list.get_item_count():
				var replay_name = item_list.get_item_text(index)
				var path = "res://replays/" + replay_name
				ReplayManager.start_playback(path)

func _on_ResetButton_pressed() -> void:
	ReplayManager.reset_replay()  # Assuming we add this method

func _on_PauseButton_pressed() -> void:
	ReplayManager.playback_paused = true

func _on_ResumeButton_pressed() -> void:
	ReplayManager.playback_paused = false

func _on_StepButton_pressed() -> void:
	if ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		ReplayManager.playback_paused = true
		ReplayManager.step_frame()
