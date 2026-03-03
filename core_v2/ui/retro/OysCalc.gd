extends VBoxContainer
class_name OysCalc

const BTN_W = 40
const BTN_H = 40

var _output_label: Label
var _current_input: String = "0"
var _previous_input: String = ""
var _operator: String = ""
var _new_number_expected: bool = false
var _buttons = []

func _ready() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	rect_min_size = Vector2(200, 260)
	theme = preload("res://core_v2/ui/retro/RetroOS.tres")
	mouse_filter = MOUSE_FILTER_PASS


	var style = StyleBoxFlat.new()
	style.bg_color = Color("0a120b")
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("56755c")

	var panel = PanelContainer.new()
	panel.add_stylebox_override("panel", style)
	add_child(panel)

	_output_label = Label.new()
	_output_label.text = "0"
	_output_label.align = Label.ALIGN_RIGHT
	_output_label.valign = Label.VALIGN_CENTER
	_output_label.rect_min_size = Vector2(0, 40)
	_output_label.add_color_override("font_color", Color("9bfa94")) # Green
	panel.add_child(_output_label)

	var spacer = Control.new()
	spacer.rect_min_size = Vector2(0, 10)
	add_child(spacer)

	var grid = GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(grid)


	var btn_layout = [
		["7", "8", "9", "/"],
		["4", "5", "6", "*"],
		["1", "2", "3", "-"],
		["C", "0", "=", "+"]
	]

	for row in range(4):
		for col in range(4):
			var text = btn_layout[row][col]
			var btn = Button.new()
			btn.text = text
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
			btn.connect("pressed", self , "_on_button_pressed", [text])
			btn.add_color_override("font_color", Color("9bfa94")) # Green
			btn.add_color_override("font_color_focus", Color("e0af41")) # Amber
			btn.add_color_override("font_color_hover", Color("e0af41")) # Amber
			grid.add_child(btn)
			_buttons.append(btn)

	_setup_focus()

func _setup_focus() -> void:
	for row in range(4):
		for col in range(4):
			var idx = row * 4 + col
			var btn = _buttons[idx]

			var up_idx = (row - 1) * 4 + col if row > 0 else 3 * 4 + col
			var down_idx = (row + 1) * 4 + col if row < 3 else 0 * 4 + col
			var left_idx = row * 4 + (col - 1) if col > 0 else row * 4 + 3
			var right_idx = row * 4 + (col + 1) if col < 3 else row * 4 + 0

			btn.focus_neighbour_top = btn.get_path_to(_buttons[up_idx])
			btn.focus_neighbour_bottom = btn.get_path_to(_buttons[down_idx])
			btn.focus_neighbour_left = btn.get_path_to(_buttons[left_idx])
			btn.focus_neighbour_right = btn.get_path_to(_buttons[right_idx])
			btn.focus_mode = Control.FOCUS_ALL

func _on_button_pressed(text: String) -> void:
	if text == "C":
		_current_input = "0"
		_previous_input = ""
		_operator = ""
		_new_number_expected = false
	elif text in ["+", "-", "*", "/"]:
		if _operator != "" and not _new_number_expected:
			_calculate()
		_previous_input = _current_input
		_operator = text
		_new_number_expected = true
	elif text == "=":
		if _operator != "":
			_calculate()
			_operator = ""
			_new_number_expected = true
	else: # Digits
		if _new_number_expected:
			_current_input = text
			_new_number_expected = false
		else:
			if _current_input == "0":
				_current_input = text
			else:
				_current_input += text

	_update_display()

func _calculate() -> void:
	var a = float(_previous_input)
	var b = float(_current_input)
	var result = 0.0

	if _operator == "+":
		result = a + b
	elif _operator == "-":
		result = a - b
	elif _operator == "*":
		result = a * b
	elif _operator == "/":
		if b != 0:
			result = a / b
		else:
			_current_input = "ERR"
			return

	var res_str = str(result)
	if res_str.ends_with(".0"):
		res_str = res_str.substr(0, res_str.length() - 2)
	_current_input = res_str

func _update_display() -> void:
	_output_label.text = _current_input
