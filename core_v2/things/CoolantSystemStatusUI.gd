extends Control

# CoolantSystemStatusUI.gd - Displays live status of valves, tank supply, and pipe fissures (FD-264 §4).

onready var _rows_container: VBoxContainer = get_node("Panel/CenterContainer/VBoxContainer/Rows")

const COLOR_OPEN := Color( 0.1, 1, 0.3 )
const COLOR_CLOSED := Color( 1, 0.15, 0.1 )
const COLOR_WARN := Color( 1, 0.8, 0.1 )

var _row_labels := {}  # valve -> Label
var _tank_label: Label = null
var _fissure_labels := {} # patch_point -> Label


func _ready() -> void:
	_setup_tank_row()
	_setup_valve_rows()
	_setup_fissure_rows()


func _physics_process(_delta: float) -> void:
	if Engine.editor_hint:
		return
	_update_tank_display()
	_update_fissure_displays()


func _setup_tank_row() -> void:
	var tank_row := HBoxContainer.new()
	var title_label := Label.new()
	title_label.text = "NIVEL DE TANQUE"
	tank_row.add_child(title_label)
	_tank_label = Label.new()
	_tank_label.align = Label.ALIGN_RIGHT
	tank_row.add_child(_tank_label)
	_rows_container.add_child(tank_row)
	_update_tank_display()


func _update_tank_display() -> void:
	if _tank_label == null:
		return
	var sources := get_tree().get_nodes_in_group("coolant_source")
	if sources.size() > 0:
		var tank = sources[0]
		var level: float = float(tank.get("tank_level")) if "tank_level" in tank else 1.0
		var pct := int(round(level * 100.0))
		_tank_label.text = "%d%%" % pct
		if level > 0.5:
			_tank_label.add_color_override("font_color", COLOR_OPEN)
		elif level > 0.15:
			_tank_label.add_color_override("font_color", COLOR_WARN)
		else:
			_tank_label.add_color_override("font_color", COLOR_CLOSED)
	else:
		_tank_label.text = "100%"
		_tank_label.add_color_override("font_color", COLOR_OPEN)


func _setup_valve_rows() -> void:
	var valves := get_tree().get_nodes_in_group("coolant_valve")
	valves.sort_custom(self, "_sort_by_floor_name")
	for valve in valves:
		var row := _make_row(valve)
		_rows_container.add_child(row)
		if not valve.is_connected("valve_state_changed", self, "_on_valve_state_changed"):
			valve.connect("valve_state_changed", self, "_on_valve_state_changed", [valve])
		_update_row(valve, valve.is_active)


func _setup_fissure_rows() -> void:
	var patch_points := get_tree().get_nodes_in_group("gloo_patchable")
	patch_points.sort_custom(self, "_sort_by_floor_name")
	for patch_point in patch_points:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = "FISURA " + _floor_label(patch_point).replace("Floor_", "PISO ")
		row.add_child(name_label)
		var state_label := Label.new()
		state_label.align = Label.ALIGN_RIGHT
		row.add_child(state_label)
		_fissure_labels[patch_point] = state_label
		_rows_container.add_child(row)
	_update_fissure_displays()


func _update_fissure_displays() -> void:
	for patch_point in _fissure_labels:
		var label: Label = _fissure_labels[patch_point]
		if label == null or not is_instance_valid(patch_point):
			continue
		var is_patched: bool = patch_point.call("is_patched") if patch_point.has_method("is_patched") else false
		var leak_node = patch_point.get("_leak") if "_leak" in patch_point else null
		var is_leaking := false
		if leak_node and is_instance_valid(leak_node) and leak_node.has_method("get_leak_intensity"):
			is_leaking = leak_node.call("get_leak_intensity") > 0.0

		if is_patched:
			label.text = "PARCHEADA"
			label.add_color_override("font_color", COLOR_WARN)
		elif is_leaking:
			label.text = "FUGA ACTIVA"
			label.add_color_override("font_color", COLOR_CLOSED)
		else:
			label.text = "SELLADA"
			label.add_color_override("font_color", COLOR_OPEN)


func _sort_by_floor_name(a: Node, b: Node) -> bool:
	return _floor_label(a) < _floor_label(b)


func _floor_label(node: Node) -> String:
	# En el dome cada valvula cuelga de su Floor_N y el piso es el que la identifica.
	# Fuera de esa jerarquia (CoolantLab, estaciones sueltas) el padre es el nodo raiz
	# y todas las filas saldrian con el mismo nombre: ahi manda el nombre propio.
	var parent := node.get_parent()
	if parent != null and parent.name.begins_with("Floor_"):
		return parent.name
	return node.name


func _make_row(valve: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = _floor_label(valve).replace("Floor_", "PISO ")
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
	label.text = "VALVULA ABIERTA" if is_open else "VALVULA CERRADA"
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
