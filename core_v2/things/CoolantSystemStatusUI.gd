extends Control

# CoolantSystemStatusUI.gd - Displays live status of tank supply (FD-264 §4, FD-270).
# Valvulas y fisuras se retiraron de esta tabla: ambos estados ya se leen en el diagrama
# esquematico (CoolantSchematicPanel) y listarlos ademas en texto era doble informacion.

const COLOR_OPEN := Color( 0.1, 1, 0.3 )
const COLOR_CLOSED := Color( 1, 0.15, 0.1 )
const COLOR_WARN := Color( 1, 0.8, 0.1 )

# Umbrales de nivel de tanque: por debajo de WARN entra en amarillo, por debajo de CRITICAL
# en rojo. Mismos valores que ya decidian el color del texto, ahora tambien marcados en el
# gauge como referencia visual de "nivel seguro".
const TANK_LEVEL_WARN := 0.5
const TANK_LEVEL_CRITICAL := 0.15

# Arco de nivel de tanque, mismo lenguaje visual que RoomDialsPanel._draw_dial(): reemplaza
# el "80%" suelto por una lectura de un vistazo, la etiqueta de texto se mantiene al lado.
class TankGauge extends Control:
	var level: float = 1.0
	var value_label: Label = null

	func _draw() -> void:
		var radius: float = min(rect_size.x, rect_size.y) * 0.5 - 4.0
		var center: Vector2 = rect_size * 0.5
		var start_angle := deg2rad(135.0)
		var total_sweep := deg2rad(270.0)
		var color: Color = COLOR_OPEN if level > TANK_LEVEL_WARN else (COLOR_WARN if level > TANK_LEVEL_CRITICAL else COLOR_CLOSED)

		draw_arc(center, radius, start_angle, start_angle + total_sweep, 32, Color(0.2, 0.22, 0.25, 0.8), 7.0)
		if level > 0.001:
			draw_arc(center, radius, start_angle, start_angle + level * total_sweep, 32, color, 8.0)

		# Marca de "nivel seguro": tick radial en el umbral bajo el cual el tanque pasa a
		# advertencia, para leer a simple vista cuanto margen queda antes de la zona amarilla.
		_draw_threshold_tick(center, radius, start_angle, total_sweep, TANK_LEVEL_WARN, Color(0.9, 0.9, 0.95, 0.9))

	func _draw_threshold_tick(center: Vector2, radius: float, start_angle: float, total_sweep: float, threshold: float, tick_color: Color) -> void:
		var angle: float = start_angle + threshold * total_sweep
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(center + dir * (radius - 7.0), center + dir * (radius + 7.0), tick_color, 2.0)

onready var _cards_container: VBoxContainer = get_node("Rows")

var _tank_label: Label = null
var _tank_gauges := {}  # tank -> TankGauge


func _ready() -> void:
	_setup_tank_card()
	# Sin _physics_process el panel ya no tiene un primer frame "gratis" que dispare
	# request_redraw() por su cuenta. _update_gauge() en _setup_tank_card() no lo llama si
	# el nivel inicial coincide con el default del gauge (100%, el caso comun al arrancar
	# con los tanques llenos) — sin este pedido explicito el Viewport padre (UPDATE_DISABLED,
	# static_content) nunca pinta su primer frame.
	_request_redraw()


func _make_card(title: String) -> VBoxContainer:
	# El fondo/borde de la columna ya lo pinta el nodo "Background" de la escena (mismo
	# theme retro_scifi.tres heredado): anidar otro Panel con estilo propio aca adentro se
	# veia como una card vacia flotando encima del contenido real.
	var inner := VBoxContainer.new()
	inner.name = "Body"
	inner.add_constant_override("separation", 10)
	inner.size_flags_horizontal = SIZE_EXPAND_FILL

	var title_label := Label.new()
	title_label.text = title
	title_label.align = Label.ALIGN_CENTER
	title_label.size_flags_horizontal = SIZE_EXPAND_FILL
	inner.add_child(title_label)

	_cards_container.add_child(inner)
	return inner


# Una fila por tanque. Con FD-266 el nivel baja solo donde hay una fuga presurizada, asi
# que cada rama drena por su cuenta: mostrar unicamente sources[0] escondia justo el dato
# que le dice al jugador que rama se esta desangrando.
func _setup_tank_card() -> void:
	var sources := get_tree().get_nodes_in_group("coolant_source")
	sources.sort_custom(self, "_sort_by_floor_name")

	var body := _make_card("NIVEL DE TANQUES")

	if sources.empty():
		var gauge := _add_tank_row(body, "TANQUE")
		_tank_label = gauge.value_label
		_update_gauge(gauge, 1.0)
	else:
		for tank in sources:
			var suffix := "" if sources.size() < 2 else (" ESTE" if "east" in tank.name.to_lower() else " OESTE")
			var gauge := _add_tank_row(body, "TANQUE" + suffix)
			_tank_gauges[tank] = gauge
			# _tank_label sigue apuntando al primero: es la referencia que ya usan los tests.
			if _tank_label == null:
				_tank_label = gauge.value_label

			var level: float = float(tank.get("tank_level")) if "tank_level" in tank else 1.0
			_update_gauge(gauge, level)
			# El display es static_content dentro de un HoloTerminalV2 (Viewport en
			# UPDATE_DISABLED): sin esto, cada tanque poleaba su nivel a 60Hz por frame de
			# fisica para un dato que cambia unas pocas veces por partida. CoolantTank ya
			# emite level_changed — conectarse ahi deja el panel en reposo (0 costo de CPU)
			# salvo cuando el nivel realmente cambia.
			if tank.has_signal("level_changed") and not tank.is_connected("level_changed", self, "_on_tank_level_changed"):
				tank.connect("level_changed", self, "_on_tank_level_changed", [tank])


# Mismo lenguaje visual que RoomDialsPanel._draw_dial(): titulo arriba, arco grande centrado,
# valor debajo -- en vez de una fila angosta, para que el gauge use el mismo tamano que los
# dials de temperatura/presion/toxicidad de la columna vecina.
func _add_tank_row(body: VBoxContainer, title: String) -> Node:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGN_CENTER
	col.add_constant_override("separation", 6)

	var title_label := Label.new()
	title_label.text = title
	title_label.align = Label.ALIGN_CENTER
	col.add_child(title_label)

	var gauge := TankGauge.new()
	gauge.rect_min_size = Vector2(110, 110)
	gauge.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(gauge)

	var value_label := Label.new()
	value_label.align = Label.ALIGN_CENTER
	col.add_child(value_label)
	gauge.value_label = value_label

	body.add_child(col)
	return gauge


func _on_tank_level_changed(new_level: float, tank: Node) -> void:
	var gauge: Node = _tank_gauges.get(tank)
	if gauge != null:
		_update_gauge(gauge, new_level)


func _update_gauge(gauge: Node, level: float) -> void:
	if not is_equal_approx(gauge.level, level):
		gauge.level = level
		gauge.update()
		_request_redraw()

	var label: Label = gauge.value_label
	var tank_text := "%d%%" % int(round(level * 100.0))
	if label.text != tank_text:
		label.text = tank_text
		_request_redraw()
	if level > TANK_LEVEL_WARN:
		label.add_color_override("font_color", COLOR_OPEN)
	elif level > TANK_LEVEL_CRITICAL:
		label.add_color_override("font_color", COLOR_WARN)
	else:
		label.add_color_override("font_color", COLOR_CLOSED)


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
