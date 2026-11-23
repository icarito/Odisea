extends Control

# FD-325 T3 — perfil del Arca para el Suit OS (ship:ark_nav).
#
# Reemplaza el corte circular plano por el mismo lenguaje longitudinal + radial
# del HUD superior: barra +Z(Puente)/0(encendido)/-Z(Motor) con Elías y destino,
# perfil HUB/TERRAZA/CASCO y flecha de gravedad efectiva (abajo en centrífuga
# normal, ~45° hacia popa al encender). Sólo re-dibuja al recibir snapshot; no
# corre _process ni toca la simulación.

const TopBarScript = preload("res://core_v2/ui/suit_os/ArkRunTopBarView.gd")
const RADIAL_PROFILE := [8.0, 240.0, 340.0]
const G_REF := 9.8
const GRID := Color(0.24, 0.55, 0.65, 0.55)
const PAD := Color(1.0, 0.82, 0.35, 1.0)
const PILOT := Color(0.18, 0.88, 0.78, 1.0)
const DEST := Color(1.0, 0.82, 0.35, 1.0)
const GRAV := Color(1.0, 0.45, 0.35, 1.0)

var snapshot: Dictionary = {}


func set_nav_snapshot(snap: Dictionary) -> void:
	snapshot = snap
	update()


func _draw() -> void:
	if snapshot.empty():
		return
	var area: Vector2 = rect_size
	if area.x < 8.0 or area.y < 8.0:
		return
	_draw_longitudinal(area)
	_draw_radial(area)


# Barra proa(z=+Z, derecha) <-> popa(Motor, z=-Z, izquierda) con Elías y destino.
func _draw_longitudinal(area: Vector2) -> void:
	var left: float = 4.0
	var right: float = area.x - 4.0
	var bar_y: float = area.y * 0.42
	draw_line(Vector2(left, bar_y), Vector2(right, bar_y), GRID, 1.0)
	var core_x: float = lerp(left, right, 0.5)
	draw_line(Vector2(core_x, bar_y - 4.0), Vector2(core_x, bar_y + 4.0), GRID, 1.0)
	var map: Dictionary = snapshot.get("map", {})
	var axial: float = clamp(float(map.get("axial_ratio", 0.0)), -1.0, 1.0)
	draw_circle(Vector2(TopBarScript.z_point_x(left, right, axial), bar_y), 3.0, PILOT)
	var dest_map: Dictionary = snapshot.get("destination_map", {})
	if not dest_map.empty():
		var dest_axial: float = clamp(float(dest_map.get("axial_ratio", 0.0)), -1.0, 1.0)
		var dx: float = TopBarScript.z_point_x(left, right, dest_axial)
		draw_line(Vector2(dx, bar_y - 4.0), Vector2(dx, bar_y + 4.0), DEST, 2.0)
	_draw_arrow(Vector2(area.x - 16.0, area.y * 0.16))


# Perfil HUB(0)/TERRAZA(240/340)/CASCO(1) con el punto radial de Elías.
func _draw_radial(area: Vector2) -> void:
	var left: float = 4.0
	var right: float = area.x * 0.5
	var line_y: float = area.y * 0.74
	draw_line(Vector2(left, line_y), Vector2(right, line_y), GRID, 1.0)
	for ratio in [0.0, RADIAL_PROFILE[1] / RADIAL_PROFILE[2], 1.0]:
		var x: float = lerp(left, right, ratio)
		draw_line(Vector2(x, line_y - 3.0), Vector2(x, line_y + 3.0), GRID, 1.0)
	var map: Dictionary = snapshot.get("map", {})
	var ratio: float = clamp(float(map.get("radius_ratio", 0.0)), 0.0, 1.0)
	draw_circle(Vector2(lerp(left, right, ratio), line_y), 3.0, PILOT)


# Flecha de gravedad efectiva: (0,+1) abajo en centrífuga; gira hacia popa al encender.
# `arrow` ya viene en convención pantalla (+X popa, +Y radial/abajo).
func _draw_arrow(origin: Vector2) -> void:
	var gravity: Dictionary = snapshot.get("gravity", {})
	var arrow_data: Array = gravity.get("arrow", [0.0, 1.0])
	var dir := Vector2(float(arrow_data[0]), float(arrow_data[1]))
	if dir.length_squared() < 0.000001:
		dir = Vector2(0.0, 1.0)
	dir = dir.normalized()
	var tip: Vector2 = origin + dir * 12.0
	draw_line(origin, tip, GRAV, 2.0)
	draw_circle(tip, 2.0, GRAV)
