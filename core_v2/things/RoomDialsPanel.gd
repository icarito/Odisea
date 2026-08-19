extends Control
class_name RoomDialsPanel

# RoomDialsPanel.gd - Control drawing live temperature, pressure, and toxicity dials from a Room3D node (FD-270).

export(NodePath) var room_path: NodePath

var _room: Node = null


func _ready() -> void:
	if rect_min_size == Vector2.ZERO:
		rect_min_size = Vector2(300, 120)

	_room = get_node_or_null(room_path)
	if _room != null:
		if _room.has_signal("temperature_changed"):
			_room.connect("temperature_changed", self, "_on_room_value_changed")
		if _room.has_signal("pressure_changed"):
			_room.connect("pressure_changed", self, "_on_room_value_changed")
		if _room.has_signal("contamination_changed"):
			_room.connect("contamination_changed", self, "_on_room_value_changed")

	update()


func _on_room_value_changed(_new_value = null) -> void:
	update()


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
	var font: Font = get_font("font")

	# Layout parameters for 3 dials horizontal layout (300x120 base)
	var panel_width: float = max(rect_size.x, 300.0)
	var section_w: float = panel_width / 3.0
	var radius: float = min(section_w * 0.32, 35.0)
	var center_y: float = 55.0

	var neutral_color := Color(0.4, 0.4, 0.45)

	# 1. Temperature Dial
	var temp_val := 20.0
	var min_temp := -25.0
	var max_temp := 40.0
	var temp_color := neutral_color
	var temp_str := "-- °C"

	if _room != null and is_instance_valid(_room):
		temp_val = float(_room.get("temperature")) if "temperature" in _room else 20.0
		var lethal_cold: float = float(_room.get("lethal_cold")) if "lethal_cold" in _room else -25.0
		var freezing_point: float = float(_room.get("freezing_point")) if "freezing_point" in _room else 0.0
		min_temp = lethal_cold
		max_temp = freezing_point + 40.0
		temp_str = "%.1f°C" % temp_val

		var is_lethal: bool = _room.call("is_lethal_cold") if _room.has_method("is_lethal_cold") else false
		var is_freezing: bool = _room.call("is_freezing") if _room.has_method("is_freezing") else false

		if is_lethal:
			temp_color = Color(1.0, 0.25, 0.15) # Red/Orange
		elif is_freezing:
			temp_color = Color(0.35, 0.8, 1.0) # Light Cyan
		else:
			temp_color = Color(0.2, 0.95, 0.4) # Green

	var temp_norm := _normalize_temperature(temp_val, min_temp, max_temp)
	_draw_dial(Vector2(section_w * 0.5, center_y), radius, temp_norm, temp_color, "TEMP", temp_str, font)

	# 2. Pressure Dial
	var pres_val := 1.0
	var max_pres := 2.88
	var pres_color := neutral_color
	var pres_str := "-- atm"

	if _room != null and is_instance_valid(_room):
		pres_val = float(_room.get("pressure")) if "pressure" in _room else 1.0
		var overpressure: float = float(_room.get("overpressure")) if "overpressure" in _room else 2.4
		max_pres = overpressure * 1.2
		pres_str = "%.2f atm" % pres_val

		var is_overpressured: bool = _room.call("is_overpressured") if _room.has_method("is_overpressured") else false
		if is_overpressured:
			pres_color = Color(1.0, 0.2, 0.2) # Red
		else:
			pres_color = Color(0.2, 0.95, 0.4) # Green

	var pres_norm := _normalize_pressure(pres_val, max_pres)
	_draw_dial(Vector2(section_w * 1.5, center_y), radius, pres_norm, pres_color, "PRES", pres_str, font)

	# 3. Contamination ("Toxicidad") Dial
	var cont_val := 0.0
	var cont_color := neutral_color
	var cont_str := "-- %"

	if _room != null and is_instance_valid(_room):
		cont_val = float(_room.get("contamination")) if "contamination" in _room else 0.0
		cont_str = "%d%%" % int(round(cont_val * 100.0))

		var is_hazard: bool = _room.call("is_hazard_active") if _room.has_method("is_hazard_active") else false
		var is_fog: bool = _room.call("is_fog_active") if _room.has_method("is_fog_active") else false

		if is_hazard:
			cont_color = Color(1.0, 0.2, 0.2) # Red
		elif is_fog:
			cont_color = Color(1.0, 0.8, 0.15) # Yellow
		else:
			cont_color = Color(0.2, 0.95, 0.4) # Green

	var cont_norm := _normalize_contamination(cont_val)
	_draw_dial(Vector2(section_w * 2.5, center_y), radius, cont_norm, cont_color, "TOX", cont_str, font)


func _draw_dial(center: Vector2, radius: float, value_norm: float, color: Color, title: String, val_str: String, font: Font) -> void:
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
		draw_string(font, title_pos, title, Color(0.7, 0.75, 0.8))

		# Value String (below dial)
		var val_size := font.get_string_size(val_str)
		var val_pos := Vector2(center.x - val_size.x * 0.5, center.y + radius + 16.0)
		draw_string(font, val_pos, val_str, Color.white)
