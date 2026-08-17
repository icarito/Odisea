extends Control

# Muestra el estado en vivo de las valvulas de emergencia del circuito de frio.
# Cada valvula se agrega al grupo "coolant_valve" (ver Dome_Intro.tscn); esta UI
# no conoce paths fijos, solo lee ese grupo y ordena por el nombre del piso
# padre (Floor_1..Floor_5).

onready var _rows_container: VBoxContainer = get_node("Panel/CenterContainer/VBoxContainer/Rows")

const COLOR_OPEN := Color( 0.1, 1, 0.3 )
const COLOR_CLOSED := Color( 1, 0.15, 0.1 )

var _row_labels := {}  # valve -> Label


func _ready() -> void:
	var valves := get_tree().get_nodes_in_group("coolant_valve")
	valves.sort_custom(self, "_sort_by_floor_name")
	for valve in valves:
		var row := _make_row(valve)
		_rows_container.add_child(row)
		if not valve.is_connected("valve_state_changed", self, "_on_valve_state_changed"):
			valve.connect("valve_state_changed", self, "_on_valve_state_changed", [valve])
		_update_row(valve, valve.is_active)


func _sort_by_floor_name(a: Node, b: Node) -> bool:
	return _floor_label(a) < _floor_label(b)


func _floor_label(valve: Node) -> String:
	var parent := valve.get_parent()
	return parent.name if parent else valve.name


func _make_row(valve: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = _floor_label(valve).replace("Floor_", "PISO ")
	# name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(name_label)
	var state_label := Label.new()
	state_label.align = Label.ALIGN_RIGHT
	row.add_child(state_label)
	_row_labels[valve] = state_label
	return row


func _on_valve_state_changed(is_open: bool, valve: Node) -> void:
	_update_row(valve, is_open)
	_request_redraw()


func _update_row(valve: Node, is_open: bool) -> void:
	var label: Label = _row_labels.get(valve)
	if label == null:
		return
	label.text = "ABIERTA" if is_open else "CERRADA"
	label.add_color_override("font_color", COLOR_OPEN if is_open else COLOR_CLOSED)


# Este panel vive dentro del Viewport de un HoloTerminalV2 con static_content=true (ver
# HangingDisplay en Dome_Intro.tscn): ese viewport se queda en UPDATE_DISABLED y solo
# redibuja cuando se lo pide. Sin esto, el texto de arriba cambiaria pero la textura
# nunca se actualizaria hasta el proximo evento que si dispare un redraw.
func _request_redraw() -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("request_redraw"):
			node.request_redraw()
			return
		node = node.get_parent()
