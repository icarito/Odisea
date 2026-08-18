extends Control

# CoolantSystemStatusUI.gd - Displays live status of valves, tank supply, and pipe fissures (FD-264 §4).

# Preload explicito en vez de depender del class_name global: en export, el compilador de
# bytecode puede resolver el cache de clases globales en un orden distinto al del editor, y
# referenciar CoolantLeak.State sin esta dependencia declarada puede dejar un .gdc invalido
# para ESTE script en el PCK exportado (visto en el nightly build 402: "Loader poll failed"
# al cargar Dome_Intro.tscn, con el .gdc de este archivo sin poder decodificarse).
const CoolantLeak = preload("res://core_v2/systems/cryo/CoolantLeak.gd")

onready var _rows_container: VBoxContainer = get_node("Panel/CenterContainer/VBoxContainer/Rows")

const COLOR_OPEN := Color( 0.1, 1, 0.3 )
const COLOR_CLOSED := Color( 1, 0.15, 0.1 )
const COLOR_WARN := Color( 1, 0.8, 0.1 )

var _row_labels := {}  # valve -> Label
var _tank_label: Label = null
var _tank_labels := {}  # tank -> Label
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


# Una fila por tanque. Con FD-266 el nivel baja solo donde hay una fuga presurizada, asi
# que cada rama drena por su cuenta: mostrar unicamente sources[0] escondia justo el dato
# que le dice al jugador que rama se esta desangrando.
func _setup_tank_row() -> void:
	var sources := get_tree().get_nodes_in_group("coolant_source")
	sources.sort_custom(self, "_sort_by_floor_name")

	if sources.empty():
		_tank_label = _add_tank_row("NIVEL DE TANQUE")
	else:
		for tank in sources:
			var suffix := "" if sources.size() < 2 else " " + _floor_label(tank).replace("Tank", "").to_upper()
			var label := _add_tank_row("NIVEL DE TANQUE" + suffix)
			_tank_labels[tank] = label
			# _tank_label sigue apuntando al primero: es la referencia que ya usan los tests.
			if _tank_label == null:
				_tank_label = label

	_update_tank_display()


func _add_tank_row(title: String) -> Label:
	var tank_row := HBoxContainer.new()
	var title_label := Label.new()
	title_label.text = title
	tank_row.add_child(title_label)
	var value_label := Label.new()
	value_label.align = Label.ALIGN_RIGHT
	tank_row.add_child(value_label)
	_rows_container.add_child(tank_row)
	return value_label


func _update_tank_display() -> void:
	if _tank_labels.empty():
		if _tank_label != null and _tank_label.text != "100%":
			_tank_label.text = "100%"
			_tank_label.add_color_override("font_color", COLOR_OPEN)
			_request_redraw()
		return

	for tank in _tank_labels:
		var label: Label = _tank_labels[tank]
		if label == null or not is_instance_valid(tank):
			continue
		var level: float = float(tank.get("tank_level")) if "tank_level" in tank else 1.0
		var tank_text := "%d%%" % int(round(level * 100.0))
		if label.text != tank_text:
			label.text = tank_text
			_request_redraw()
		if level > 0.5:
			label.add_color_override("font_color", COLOR_OPEN)
		elif level > 0.15:
			label.add_color_override("font_color", COLOR_WARN)
		else:
			label.add_color_override("font_color", COLOR_CLOSED)


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
		name_label.text = "FISURA " + _floor_label(patch_point).replace("Floor_", "PISO ").replace("Leak", "").replace("_Patch", "").to_upper()
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
		var is_firm: bool = patch_point.call("is_firmly_patched") if patch_point.has_method("is_firmly_patched") else false
		var leak_node = patch_point.get("_leak") if "_leak" in patch_point else null
		var leak_state: int = CoolantLeak.State.HEALTHY
		if leak_node and is_instance_valid(leak_node) and leak_node.has_method("get_state"):
			leak_state = leak_node.call("get_state")

		# El estado manda, no la intensidad. Mirando solo get_leak_intensity() > 0, tanto la
		# condensacion previa (WARNING, intensidad 0) como un tramo despresurizado (la valvula
		# corto el caudal pero el cano SIGUE roto) caian en "SELLADA" en verde — justo la
		# confusion que FD-266 vino a eliminar, ahora en el tablero del jugador.
		var text := "SELLADA"
		var color := COLOR_OPEN
		if is_patched:
			text = "PARCHEADA" if is_firm else "PARCHE PROVISORIO"
			color = COLOR_OPEN if is_firm else COLOR_WARN
		else:
			match leak_state:
				CoolantLeak.State.WARNING:
					text = "CONDENSACION"
					color = COLOR_WARN
				CoolantLeak.State.LEAKING:
					text = "FUGA ACTIVA"
					color = COLOR_CLOSED
				CoolantLeak.State.DEPRESSURIZED:
					text = "ROTA - SIN PRESION"
					color = COLOR_WARN

		if label.text != text:
			label.text = text
			_request_redraw()
		label.add_color_override("font_color", color)


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
