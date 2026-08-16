extends Control

# PressureGaugeUI.gd — manómetro de presión dibujado como UI radial (FD-258).
#
# Sigue el lenguaje del selector del ascensor (core_v2/ui/radial/RadialSelectorV2):
# se dibuja en 2D dentro de un Viewport y se proyecta como holograma sobre un quad, en vez
# de armarse con geometría. Un manómetro de CSG con agujas y aros era pesado de leer y
# caro de componer; acá el arco, la zona verde y el peligro se dibujan y se entienden.
#
# No tiene lógica propia: la estación le pasa los valores ya normalizados.

const ARC_START := deg2rad(135.0)   # abre abajo-izquierda
const ARC_SPAN := deg2rad(270.0)

export(Color) var color_track := Color(0.0, 0.83, 1.0, 0.22)
export(Color) var color_pressure := Color(0.0, 0.83, 1.0, 0.95)
export(Color) var color_danger := Color(1.0, 0.25, 0.15, 0.85)
export(Color) var color_target := Color(0.35, 1.0, 0.5, 0.9)
export(Color) var color_dial := Color(0.6, 1.0, 0.58, 1.0)
export(float) var danger_from := 0.75

# Todo esto lo escribe la estación en cada frame.
var pressure: float = 0.0 setget set_pressure
var dial_value: float = 0.0 setget set_dial_value
var dial_target: float = 0.62
var dial_tolerance: float = 0.08
var proximity: float = 0.0
var locked: bool = false
var alarm: bool = false


func set_pressure(v: float) -> void:
	pressure = clamp(v, 0.0, 1.0)
	update()


func set_dial_value(v: float) -> void:
	dial_value = clamp(v, 0.0, 1.0)
	update()


func set_state(p: float, dv: float, target: float, tolerance: float, prox: float, is_locked: bool, is_alarm: bool) -> void:
	pressure = clamp(p, 0.0, 1.0)
	dial_value = clamp(dv, 0.0, 1.0)
	dial_target = target
	dial_tolerance = tolerance
	proximity = prox
	locked = is_locked
	alarm = is_alarm
	update()


func _angle_for(value: float) -> float:
	return ARC_START + ARC_SPAN * clamp(value, 0.0, 1.0)


func _point_on(center: Vector2, radius: float, value: float) -> Vector2:
	var a: float = _angle_for(value)
	return center + Vector2(cos(a), sin(a)) * radius


func _draw() -> void:
	var center: Vector2 = rect_size * 0.5
	var radius: float = min(rect_size.x, rect_size.y) * 0.36

	# Pista completa: de dónde a dónde puede moverse la presión.
	draw_arc(center, radius, ARC_START, ARC_START + ARC_SPAN, 96, color_track, 26.0, true)

	# Franja de peligro: el tramo alto de la escala. Dice hacia dónde NO hay que llegar.
	draw_arc(center, radius, _angle_for(danger_from), ARC_START + ARC_SPAN, 48,
		color_danger, 26.0, true)

	# Zona verde: dónde tiene que quedar el ajuste para purgar. Late al acercarse.
	var band_color: Color = color_target
	band_color.a = 0.5 + 0.5 * proximity
	draw_arc(center, radius * 0.74, _angle_for(dial_target - dial_tolerance),
		_angle_for(dial_target + dial_tolerance), 24, band_color, 18.0, true)

	# Presión actual: el arco lleno desde el principio hasta donde está.
	draw_arc(center, radius, ARC_START, _angle_for(pressure), 64, color_pressure, 26.0, true)
	var tip: Vector2 = _point_on(center, radius, pressure)
	draw_circle(tip, 13.0, color_pressure)

	# Aguja de ajuste: lo único que el jugador mueve.
	var dial_inner: Vector2 = _point_on(center, radius * 0.44, dial_value)
	var dial_outer: Vector2 = _point_on(center, radius * 0.86, dial_value)
	var dial_color: Color = color_dial
	if locked:
		dial_color = Color(1.0, 1.0, 1.0, 1.0)
	draw_line(dial_inner, dial_outer, dial_color, 9.0, true)
	draw_circle(dial_outer, 11.0, dial_color)

	# Núcleo: parpadea sólo cuando la presión está subiendo.
	var hub: Color = color_pressure
	if alarm:
		hub = color_danger
	draw_circle(center, radius * 0.2, Color(hub.r, hub.g, hub.b, 0.18))
	draw_arc(center, radius * 0.2, 0.0, TAU, 32, hub, 5.0, true)
