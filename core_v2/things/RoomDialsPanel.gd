extends Control
class_name RoomDialsPanel

# RoomDialsPanel.gd - Control drawing live temperature, pressure, and toxicity dials from a Room3D node (FD-270).

export(NodePath) var room_path: NodePath
# La textura del HangingDisplay se ve desde varios metros: las lecturas necesitan más
# peso que las etiquetas decorativas. Se puede afinar por instancia desde Inspector.
export(float, 0.75, 2.0) var dial_title_scale: float = 1.12
export(float, 0.75, 2.0) var dial_value_scale: float = 1.35

# Inset de la card respecto al borde de su columna: mismo criterio visual que
# CoolantSystemStatusUI.tscn (margen 24) y CoolantSchematicPanel (CARD_MARGIN).
const CARD_MARGIN := 24.0

var _room: Node = null
var _draw_content_origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	if rect_min_size == Vector2.ZERO:
		rect_min_size = Vector2(160, 420)

	_room = get_node_or_null(room_path)
	if _room != null:
		if _room.has_signal("temperature_changed"):
			_room.connect("temperature_changed", self, "_on_room_value_changed")
		if _room.has_signal("pressure_changed"):
			_room.connect("pressure_changed", self, "_on_room_value_changed")
		if _room.has_signal("contamination_changed"):
			_room.connect("contamination_changed", self, "_on_room_value_changed")

	update()
	# Este panel vive dentro de un HoloTerminalV2 con static_content=true (Viewport en
	# UPDATE_DISABLED): sin este pedido explicito, el primer contenido nunca llega a
	# pintarse si Room3D no emite ningun cambio despues del arranque (temperatura/presion
	# ya estables en su default). Mismo patron que CoolantSystemStatusUI/CoolantSchematicPanel.
	_request_redraw()


func _on_room_value_changed(_new_value = null) -> void:
	update()
	_request_redraw()


# --- PURE NORMALIZATION HELPERS ---

func _normalize_temperature(temp: float, min_temp: float = -25.0, max_temp: float = 40.0) -> float:
	if is_equal_approx(min_temp, max_temp):
		return 0.0
	return clamp((temp - min_temp) / (max_temp - min_temp), 0.0, 1.0)


func _normalize_pressure(press: float, max_press: float = 2.88) -> float:
	if max_press <= 0.0:
		return 0.0
	return clamp(press / max_press, 0.0, 1.0)


func _normalize_contamination(cont: float) -> float:
	return clamp(cont, 0.0, 1.0)


# --- DRAWING ---

func _draw() -> void:
	# Mismo theme "ship OS" que el resto de terminales (retro_scifi.tres, Panel/styles/panel):
	# este Control dibuja a mano, no es un Panel, asi que el fondo/borde holografico hay que
	# pedirselo al theme heredado y pintarlo nosotros mismos.
	# La card ocupa el rect propio MENOS un respiro CARD_MARGIN en cada borde: si se pinta el
	# rect completo, tres columnas vecinas se ven como un solo bloque de color pegado, no
	# como tres cards separadas.
	var panel_style: StyleBox = get_stylebox("panel", "Panel")
	var half_gap := CARD_MARGIN * 0.5
	if panel_style != null:
		var inset := Rect2(Vector2(half_gap, half_gap), rect_size - Vector2(CARD_MARGIN, CARD_MARGIN))
		panel_style.draw(get_canvas_item(), inset)

	var font: Font = get_font("font")

	# El resto del dibujo va desplazado adentro del borde de la card (mismo half_gap que el
	# fondo, mas un respiro de contenido), en vez de pegado al filo que acaba de pintar
	# panel_style.
	var content_offset: float = half_gap + 16.0
	_draw_content_origin = Vector2(content_offset, content_offset)
	draw_set_transform(_draw_content_origin, 0.0, Vector2.ONE)

	# Layout de 3 dials apilados en vertical: la columna del HangingDisplay es angosta y
	# alta, en fila horizontal los 3 dials quedaban apretados contra un ancho chico en vez
	# de aprovechar el largo disponible.
	var panel_width: float = max(rect_size.x - content_offset * 2.0, 120.0)
	var panel_height: float = max(rect_size.y - content_offset * 2.0, 300.0)
	var section_h: float = panel_height / 3.0
	var radius: float = min(min(panel_width * 0.35, section_h * 0.32), 55.0)
	var center_x: float = panel_width * 0.5

	var neutral_color := Color(0.4, 0.4, 0.45)

	# 1. Temperature Dial
	var temp_val := 20.0
	var min_temp := -25.0
	var max_temp := 40.0
	var temp_color := neutral_color
	var temp_str := "-- °C"
	var temp_safe_norm := -1.0

	if _room != null and is_instance_valid(_room):
		temp_val = float(_room.get("temperature")) if "temperature" in _room else 20.0
		var lethal_cold: float = float(_room.get("lethal_cold")) if "lethal_cold" in _room else -25.0
		var freezing_point: float = float(_room.get("freezing_point")) if "freezing_point" in _room else 0.0
		min_temp = lethal_cold
		max_temp = freezing_point + 40.0
		temp_str = "%.1f°C" % temp_val
		# El limite seguro es donde empieza a congelar, no el frio letal (ese es el extremo
		# 0.0 de la escala, una marca ahi pegada al borde no aporta nada).
		temp_safe_norm = _normalize_temperature(freezing_point, min_temp, max_temp)

		var is_lethal: bool = _room.call("is_lethal_cold") if _room.has_method("is_lethal_cold") else false
		var is_freezing: bool = _room.call("is_freezing") if _room.has_method("is_freezing") else false

		if is_lethal:
			temp_color = Color(1.0, 0.25, 0.15) # Red/Orange
		elif is_freezing:
			temp_color = Color(0.35, 0.8, 1.0) # Light Cyan
		else:
			temp_color = Color(0.2, 0.95, 0.4) # Green

	var temp_norm := _normalize_temperature(temp_val, min_temp, max_temp)
	_draw_dial(Vector2(center_x, section_h * 0.5), radius, temp_norm, temp_color, "TEMP", temp_str, font, temp_safe_norm)

	# 2. Pressure Dial
	var pres_val := 1.0
	var max_pres := 2.88
	var pres_color := neutral_color
	var pres_str := "-- atm"
	var pres_safe_norm := -1.0

	if _room != null and is_instance_valid(_room):
		pres_val = float(_room.get("pressure")) if "pressure" in _room else 1.0
		var overpressure: float = float(_room.get("overpressure")) if "overpressure" in _room else 2.4
		max_pres = overpressure * 1.2
		pres_str = "%.2f atm" % pres_val
		pres_safe_norm = _normalize_pressure(overpressure, max_pres)

		var is_overpressured: bool = _room.call("is_overpressured") if _room.has_method("is_overpressured") else false
		if is_overpressured:
			pres_color = Color(1.0, 0.2, 0.2) # Red
		else:
			pres_color = Color(0.2, 0.95, 0.4) # Green

	var pres_norm := _normalize_pressure(pres_val, max_pres)
	_draw_dial(Vector2(center_x, section_h * 1.5), radius, pres_norm, pres_color, "PRES", pres_str, font, pres_safe_norm)

	# 3. Contamination ("Toxicidad") Dial
	var cont_val := 0.0
	var cont_color := neutral_color
	var cont_str := "-- %"
	var cont_safe_norm := -1.0

	if _room != null and is_instance_valid(_room):
		cont_val = float(_room.get("contamination")) if "contamination" in _room else 0.0
		cont_str = "%d%%" % int(round(cont_val * 100.0))
		var hazard_threshold: float = float(_room.get("hazard_threshold")) if "hazard_threshold" in _room else 0.7
		cont_safe_norm = _normalize_contamination(hazard_threshold)

		var is_hazard: bool = _room.call("is_hazard_active") if _room.has_method("is_hazard_active") else false
		var is_fog: bool = _room.call("is_fog_active") if _room.has_method("is_fog_active") else false

		if is_hazard:
			cont_color = Color(1.0, 0.2, 0.2) # Red
		elif is_fog:
			cont_color = Color(1.0, 0.8, 0.15) # Yellow
		else:
			cont_color = Color(0.2, 0.95, 0.4) # Green

	var cont_norm := _normalize_contamination(cont_val)
	_draw_dial(Vector2(center_x, section_h * 2.5), radius, cont_norm, cont_color, "TOX", cont_str, font, cont_safe_norm)


func _draw_dial(center: Vector2, radius: float, value_norm: float, color: Color, title: String, val_str: String, font: Font, safe_threshold_norm: float = -1.0) -> void:
	var start_angle := deg2rad(135.0)
	var total_sweep := deg2rad(270.0)
	var end_angle := start_angle + total_sweep
	var bg_color := Color(0.2, 0.22, 0.25, 0.8)
	var arc_width := 6.0

	# Background Arc
	draw_arc(center, radius, start_angle, end_angle, 32, bg_color, arc_width)

	# Foreground Arc
	if value_norm > 0.001:
		var val_end_angle := start_angle + value_norm * total_sweep
		draw_arc(center, radius, start_angle, val_end_angle, 32, color, arc_width + 1.0)

	# Marca de "nivel seguro": tick radial en el umbral de peligro (hazard/overpressure/etc)
	# de este dial, para leer a simple vista cuanto margen queda antes de la zona de riesgo.
	if safe_threshold_norm >= 0.0:
		var tick_angle: float = start_angle + clamp(safe_threshold_norm, 0.0, 1.0) * total_sweep
		var tick_dir := Vector2(cos(tick_angle), sin(tick_angle))
		draw_line(center + tick_dir * (radius - 6.0), center + tick_dir * (radius + 6.0), Color(0.9, 0.9, 0.95, 0.9), 2.0)

	# Needle
	var needle_angle := start_angle + value_norm * total_sweep
	var needle_dir := Vector2(cos(needle_angle), sin(needle_angle))
	var needle_len := radius - 4.0
	draw_line(center, center + needle_dir * needle_len, color, 2.0)
	draw_circle(center, 3.0, Color.white)

	# Title Label (above dial)
	if font != null:
		var title_size := font.get_string_size(title)
		var title_pos := Vector2(center.x - title_size.x * 0.5, center.y - radius - 8.0)
		_draw_scaled_text(font, title, title_pos, Color(0.7, 0.75, 0.8), dial_title_scale)

		# Value String (below dial)
		var val_size := font.get_string_size(val_str)
		var val_pos := Vector2(center.x - val_size.x * 0.5, center.y + radius + 16.0)
		_draw_scaled_text(font, val_str, val_pos, Color.white, dial_value_scale)


func _draw_scaled_text(font: Font, text: String, position: Vector2, color: Color, scale: float) -> void:
	# draw_set_transform reemplaza el transform actual; restauramos el origen de la card
	# enseguida para que las líneas y diales siguientes sigan en coordenadas locales.
	draw_set_transform(_draw_content_origin + position, 0.0, Vector2.ONE * scale)
	draw_string(font, Vector2.ZERO, text, color)
	draw_set_transform(_draw_content_origin, 0.0, Vector2.ONE)


# Este panel vive dentro del Viewport de un HoloTerminalV2 con static_content=true (ver
# HangingDisplay en Dome_Intro.tscn): ese viewport se queda en UPDATE_DISABLED y solo
# redibuja cuando se lo pide. Sin esto, el dial cambiaria pero la textura nunca se
# actualizaria hasta el proximo evento que si dispare un redraw.
func _request_redraw() -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("request_redraw"):
			node.request_redraw()
			return
		node = node.get_parent()
