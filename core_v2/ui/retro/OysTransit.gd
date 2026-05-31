extends VBoxContainer
class_name OysTransit

# OysTransit.gd
# OdiseaOS App for selecting transit destinations.
# Follows the pattern of OysCalc.gd

signal destination_selected(destination_id, destination_name)

var _buttons = []
var _destinations = [
	{"id": "spiral_center", "name": "Centro de la Espiral"},
	{"id": "engineering_bay", "name": "Bahía de Ingeniería"},
	{"id": "north_dome", "name": "Domo Norte"}
]

func _ready() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	rect_min_size = Vector2(240, 300)
	theme = preload("res://core_v2/ui/retro/RetroOS.tres")
	mouse_filter = MOUSE_FILTER_PASS

	var title_label = Label.new()
	title_label.text = "SISTEMA DE TRÁNSITO"
	title_label.align = Label.ALIGN_CENTER
	title_label.add_color_override("font_color", Color("e0af41")) # Amber
	add_child(title_label)

	var spacer = Control.new()
	spacer.rect_min_size = Vector2(0, 10)
	add_child(spacer)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(scroll)

	var list = VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)

	for dest in _destinations:
		var btn = Button.new()
		btn.text = dest["name"]
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.rect_min_size = Vector2(0, 40)
		btn.connect("pressed", self , "_on_destination_pressed", [dest["id"], dest["name"]])
		btn.add_color_override("font_color", Color("9bfa94")) # Green
		btn.add_color_override("font_color_focus", Color("e0af41")) # Amber
		btn.add_color_override("font_color_hover", Color("e0af41")) # Amber
		list.add_child(btn)
		_buttons.append(btn)

	_setup_focus()

func _setup_focus() -> void:
	for i in range(_buttons.size()):
		var btn = _buttons[i]
		var up_idx = (i - 1) if i > 0 else _buttons.size() - 1
		var down_idx = (i + 1) if i < _buttons.size() - 1 else 0

		btn.focus_neighbour_top = btn.get_path_to(_buttons[up_idx])
		btn.focus_neighbour_bottom = btn.get_path_to(_buttons[down_idx])
		btn.focus_mode = Control.FOCUS_ALL

	if _buttons.size() > 0:
		_buttons[0].grab_focus()

func _on_destination_pressed(id: String, name: String) -> void:
	emit_signal("destination_selected", id, name)
	if Engine.has_singleton("TransitSystem") or has_node("/root/TransitSystem"):
		var ts = get_node("/root/TransitSystem")
		if ts.has_method("request_travel"):
			ts.request_travel(id, name)
