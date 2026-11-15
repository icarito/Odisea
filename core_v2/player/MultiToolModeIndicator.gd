extends Control

# MultiToolModeIndicator.gd
# UI for the Multi-Tool.

onready var _mode_label: Label = $ModeLabel
onready var _count_label: Label = $CountLabel

# equipped sigue el enum Equipped de MultiToolV2: 0=NONE, 1=LASER, 2=GLOO.
func update_info(equipped: int, current_count: int, max_count: int):
	match equipped:
		1: # LASER
			_mode_label.text = "MODE: LASER"
			_mode_label.add_color_override("font_color", Color.red)
			_count_label.visible = false
		2: # GLOO
			_mode_label.text = "MODE: GLOO"
			_mode_label.add_color_override("font_color", Color.cyan)
			_count_label.visible = true
			_count_label.text = "GLOO: %d/%d" % [current_count, max_count]
		_: # NONE
			_mode_label.text = "MODE: NONE"
			_mode_label.add_color_override("font_color", Color(0.45, 0.45, 0.48))
			_count_label.visible = false
