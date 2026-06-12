extends VBoxContainer
class_name OysStatus

signal status_closed()

var _reactor_label: Label
var _oxygen_label: Label
var _pressure_label: Label
var _temperature_label: Label

func _ready() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	rect_min_size = Vector2(240, 300)
	theme = preload("res://core_v2/ui/retro/RetroOS.tres")
	mouse_filter = MOUSE_FILTER_PASS

	# Top bar for "X" button as requested if no back mechanism
	var top_bar = HBoxContainer.new()
	top_bar.alignment = BoxContainer.ALIGN_END
	add_child(top_bar)

	var close_btn = Button.new()
	close_btn.text = " X "
	close_btn.flat = false
	close_btn.connect("pressed", self, "_on_close_pressed")
	top_bar.add_child(close_btn)

	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("0a120b")
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color("56755c")
	panel.add_stylebox_override("panel", style)
	add_child(panel)

	var v_box = VBoxContainer.new()
	v_box.set_indexed("custom_constants/separation", 10)
	panel.add_child(v_box)

	_reactor_label = _create_status_label("REACTOR: STANDBY", v_box)
	_oxygen_label = _create_status_label("OXYGEN: 100%", v_box)
	_pressure_label = _create_status_label("PRESSURE: 101.3 kPa", v_box)
	_temperature_label = _create_status_label("TEMP: 22.0 C", v_box)

func _create_status_label(initial_text: String, parent: Node) -> Label:
	var label = Label.new()
	label.text = initial_text
	label.align = Label.ALIGN_LEFT
	label.valign = Label.VALIGN_CENTER
	label.rect_min_size = Vector2(0, 30)
	label.add_color_override("font_color", Color("9bfa94")) # Green
	parent.add_child(label)
	return label

func update_status(data: Dictionary) -> void:
	if data.has("reactor"):
		_reactor_label.text = "REACTOR: " + str(data["reactor"]).to_upper()
	if data.has("oxygen"):
		_oxygen_label.text = "OXYGEN: " + str(data["oxygen"]) + "%"
	if data.has("pressure"):
		_pressure_label.text = "PRESSURE: " + str(data["pressure"]) + " kPa"
	if data.has("temperature"):
		_temperature_label.text = "TEMP: " + str(data["temperature"]) + " C"

func _on_close_pressed() -> void:
	emit_signal("status_closed")
	queue_free()
