extends Control

# MultiToolModeIndicator.gd
# UI for the Multi-Tool.

onready var _mode_label: Label = $ModeLabel
onready var _count_label: Label = $CountLabel

func update_info(mode: int, current_count: int, max_count: int):
	match mode:
		0: # LASER
			_mode_label.text = "MODE: LASER"
			_mode_label.add_color_override("font_color", Color.red)
			_count_label.visible = false
		1: # GLOO
			_mode_label.text = "MODE: GLOO"
			_mode_label.add_color_override("font_color", Color.cyan)
			_count_label.visible = true
			_count_label.text = "GLOO: %d/%d" % [current_count, max_count]
