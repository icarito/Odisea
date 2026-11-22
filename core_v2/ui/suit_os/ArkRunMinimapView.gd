extends Control

# FD-324 F4 — mini mapa diegético del cilindro.
#
# Dibuja el corte radial (círculo con el punto de Elías por atan2(y, x) y
# |r_perp|/R_hull), la barra proa↔popa normalizada y la flecha de gravedad
# efectiva. Sólo redi-buja cuando llega un snapshot (el host limita a 10 Hz):
# no corre _process ni toca la simulación.

var snapshot: Dictionary = {}


func set_nav_snapshot(snap: Dictionary) -> void:
	snapshot = snap
	update()


func _draw() -> void:
	if snapshot.empty():
		return
	var area: Vector2 = rect_size
	var radius: float = min(area.x * 0.24, area.y * 0.5) - 4.0
	if radius <= 2.0:
		return
	var center := Vector2(area.x * 0.28, area.y * 0.5)
	var grid := Color(0.24, 0.55, 0.65, 0.55)
	draw_arc(center, radius, 0.0, TAU, 32, grid, 1.0, true)
	draw_line(center - Vector2(radius, 0.0), center + Vector2(radius, 0.0), grid, 1.0)
	draw_line(center - Vector2(0.0, radius), center + Vector2(0.0, radius), grid, 1.0)

	# Punto de Elías: ángulo radial y radio normalizado.
	var map: Dictionary = snapshot.get("map", {})
	var ratio: float = clamp(float(map.get("radius_ratio", 0.0)), 0.0, 1.0)
	var angle: float = float(map.get("angle", 0.0))
	var point := center + Vector2(cos(angle), -sin(angle)) * radius * ratio
	draw_circle(point, 3.0, Color(0.18, 0.88, 0.78, 1.0))

	# Destino propuesto: misma proyección radial.
	var destination_map: Dictionary = snapshot.get("destination_map", {})
	if not destination_map.empty():
		var dest_ratio: float = clamp(float(destination_map.get("radius_ratio", 0.0)), 0.0, 1.0)
		var dest_angle: float = float(destination_map.get("angle", 0.0))
		var dest_point := center + Vector2(cos(dest_angle), -sin(dest_angle)) \
			* radius * dest_ratio
		var dest_color := Color(1.0, 0.82, 0.35, 1.0)
		draw_line(dest_point - Vector2(3.0, 0.0), dest_point + Vector2(3.0, 0.0), dest_color, 1.0)
		draw_line(dest_point - Vector2(0.0, 3.0), dest_point + Vector2(0.0, 3.0), dest_color, 1.0)

	# Barra proa↔popa: popa -Z a la izquierda, proa +Z a la derecha.
	var bar_left: float = area.x * 0.58
	var bar_right: float = area.x - 8.0
	var bar_y: float = area.y * 0.72
	var bar_mid: float = (bar_left + bar_right) * 0.5
	draw_line(Vector2(bar_left, bar_y), Vector2(bar_right, bar_y), grid, 1.0)
	var axial: float = clamp(float(map.get("axial_ratio", 0.0)), -1.0, 1.0)
	var marker_x: float = bar_mid + axial * (bar_right - bar_left) * 0.5
	draw_line(Vector2(marker_x, bar_y - 4.0), Vector2(marker_x, bar_y + 4.0),
		Color(1.0, 0.82, 0.35, 1.0), 2.0)

	# Flecha de gravedad efectiva: +X = popa (-Z), +Y = radial.
	var gravity: Dictionary = snapshot.get("gravity", {})
	var arrow_data: Array = gravity.get("arrow", [0.0, 1.0])
	var arrow := Vector2(float(arrow_data[0]), -float(arrow_data[1]))
	var origin := Vector2(area.x * 0.76, area.y * 0.30)
	var tip := origin + arrow * 12.0
	var arrow_color := Color(1.0, 0.45, 0.35, 1.0)
	draw_line(origin, tip, arrow_color, 2.0)
	draw_circle(tip, 2.0, arrow_color)
