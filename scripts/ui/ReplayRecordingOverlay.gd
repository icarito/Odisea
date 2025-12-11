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

func _on_StopButton_pressed() -> void:
	if ReplayManager.mode == ReplayManager.ReplayMode.RECORDING:
		ReplayManager.stop_recording()
	elif ReplayManager.mode == ReplayManager.ReplayMode.PLAYBACK:
		ReplayManager.stop_playback()
