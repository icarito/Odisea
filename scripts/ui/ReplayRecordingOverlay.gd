extends CanvasLayer

onready var status_label: Label = find_node("StatusLabel", true, false)
onready var stop_button: Button = find_node("StopButton", true, false)

func _ready() -> void:
	visible = false
	if stop_button:
		stop_button.connect("pressed", self, "_on_StopButton_pressed")
	if status_label:
		status_label.text = ""
	ReplayManager.connect("mode_changed", self, "_on_mode_changed")

func _on_mode_changed(new_mode: int) -> void:
	if new_mode == ReplayManager.ReplayMode.RECORDING:
		visible = true
		if status_label:
			status_label.text = "Recording..."
			status_label.modulate = Color(1, 0, 0)  # Red
		if stop_button:
			stop_button.visible = true
	elif new_mode == ReplayManager.ReplayMode.PLAYBACK:
		visible = true
		if status_label:
			status_label.text = "Playing..."
			status_label.modulate = Color(0, 1, 0)  # Green
		if stop_button:
			stop_button.visible = true
	else:
		visible = false

func _process(_delta: float) -> void:
	if not visible:
		return

	if ReplayManager.mode == ReplayManager.ReplayMode.RECORDING:
		if status_label and ReplayManager.current_replay:
			status_label.text = "Recording... %d" % len(ReplayManager.current_replay.frames)
	elif ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		if status_label and ReplayManager.current_replay:
			var total_frames = len(ReplayManager.current_replay.frames)
			status_label.text = "Playing... %d / %d" % [ReplayManager.frame_index, total_frames]

func _on_StopButton_pressed() -> void:
	if ReplayManager.mode == ReplayManager.ReplayMode.RECORDING:
		ReplayManager.stop_recording()
	elif ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		ReplayManager.stop_playback()
