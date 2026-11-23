extends Control

# FD-325 T3 — sub-controles de dibujo del HUD superior (<200 líneas).
# Separado de ArkRunTopBarView.gd para mantener ambos cortos. Cada clase pinta una
# única región fija de la franja superior: sólo _draw(), sin _process ni estado de
# simulación. Los helpers de layout se duplican por clase (parámetros ya validados
# por librería) y NO tocan estado: son deterministas.

const BG := Color(0.02, 0.05, 0.08, 0.62)
const TEXT := Color(0.74, 0.94, 1.0, 1.0)
const DIM := Color(0.45, 0.62, 0.72, 1.0)
const BRIDGE_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const ENGINE_ORANGE := Color(1.0, 0.4, 0.15, 1.0)
const CORE_TICK := Color(0.85, 0.92, 1.0, 0.9)
const PILOT_CYAN := Color(0.35, 1.0, 0.75, 1.0)
const GHOST_COLOR := Color(0.7, 0.85, 1.0, 0.45)
const GRAV_DOWN := Color(0.35, 1.0, 0.75, 1.0)
const GRAV_PULSE := Color(1.0, 0.5, 0.2, 0.95)
const CHIP_ON := Color(1.0, 0.82, 0.3, 1.0)
const CHIP_OFF := Color(0.36, 0.46, 0.54, 1.0)
const RADIAL_PROFILE := [8.0, 240.0, 340.0]
const G_REF := 9.8


class CenterBar extends Control:
	var phase := ""
	var timer_text := ""
	var best_text := ""
	var z_norm := 0.0
	var ghost_z_norm := 0.0
	var ghost_visible := false

	func point_x(right: float, t: float) -> float:
		return lerp(0.0, right, clamp((1.0 - t) * 0.5, 0.0, 1.0))

	func text_line(canvas: CanvasItem, pos: Vector2, text: String, size: int,
			color: Color) -> void:
		var font: Font = canvas.get_font("font", "Label")
		if font == null:
			return
		canvas.draw_string(font, pos + Vector2(1.0, 1.0), text, Color(0, 0, 0, 0.8))
		canvas.draw_string(font, pos, text, color)

	func _draw() -> void:
		var right: float = max(rect_size.x, 1.0)
		var bar_y: float = 58.0
		text_line(self, Vector2(0.0, 18.0), phase, 15, TEXT)
		text_line(self, Vector2(right - 150.0, 16.0), timer_text, 20, TEXT)
		text_line(self, Vector2(right - 150.0, 38.0), best_text, 12, DIM)
		draw_line(Vector2(0.0, bar_y), Vector2(right, bar_y), DIM, 2.0)
		draw_line(Vector2(0.0, bar_y - 6.0), Vector2(0.0, bar_y + 6.0), BRIDGE_GOLD, 3.0)
		draw_line(Vector2(right, bar_y - 6.0), Vector2(right, bar_y + 6.0), ENGINE_ORANGE, 3.0)
		var core_x: float = point_x(right, 0.0)
		draw_line(Vector2(core_x, bar_y - 9.0), Vector2(core_x, bar_y + 9.0), CORE_TICK, 2.0)
		if ghost_visible:
			draw_circle(Vector2(point_x(right, ghost_z_norm), bar_y), 5.0, GHOST_COLOR)
		draw_circle(Vector2(point_x(right, z_norm), bar_y), 5.0, PILOT_CYAN)
		text_line(self, Vector2(0.0, bar_y + 22.0), "PUENTE", 11, BRIDGE_GOLD)
		text_line(self, Vector2(right - 70.0, bar_y + 22.0), "MOTOR", 11, ENGINE_ORANGE)


class RadialPanel extends Control:
	var radial_ratio := 0.0
	var g_mag := 0.0
	var a_axial := 0.0

	func text_line(canvas: CanvasItem, pos: Vector2, text: String, size: int,
			color: Color) -> void:
		var font: Font = canvas.get_font("font", "Label")
		if font == null:
			return
		canvas.draw_string(font, pos + Vector2(1.0, 1.0), text, Color(0, 0, 0, 0.8))
		canvas.draw_string(font, pos, text, color)

	func _draw() -> void:
		var right: float = max(rect_size.x - 4.0, 1.0)
		var line_y: float = 50.0
		text_line(self, Vector2(0.0, line_y - 24.0), "HUB · TERRAZA · CASCO", 11, DIM)
		draw_line(Vector2(0.0, line_y), Vector2(right, line_y), DIM, 2.0)
		for ratio in [0.0, 240.0 / 340.0, 1.0]:
			var x: float = lerp(0.0, right, ratio)
			draw_line(Vector2(x, line_y - 5.0), Vector2(x, line_y + 5.0), CORE_TICK, 2.0)
		draw_circle(Vector2(lerp(0.0, right, radial_ratio), line_y), 4.0, PILOT_CYAN)
		text_line(self, Vector2(0.0, line_y + 22.0), "%.1f g" % (g_mag / 9.8), 14, TEXT)
		var origin := Vector2(right - 18.0, line_y + 16.0)
		var arrow: Vector2 = Vector2(0.0, 1.0)
		if abs(a_axial) >= 0.000001 and g_mag > 0.000001:
			var angle: float = atan2(abs(a_axial), 9.8)
			arrow = Vector2(sin(angle), cos(angle)).normalized()
		var color: Color = GRAV_PULSE if abs(a_axial) > 0.000001 else GRAV_DOWN
		var tip: Vector2 = origin + arrow * 18.0
		draw_line(origin, tip, color, 2.5)
		var side: Vector2 = Vector2(-arrow.y, arrow.x) * 4.5
		draw_line(tip, tip - arrow * 6.0 + side, color, 2.0)
		draw_line(tip, tip - arrow * 6.0 - side, color, 2.0)


class ChipsPanel extends Control:
	var flashlight_on := false
	var autonav_active := false

	func _draw() -> void:
		_chip(0.0, "L1 LINTERNA", flashlight_on)
		_chip(28.0, "R1 AUTONAV", autonav_active)

	func _chip(y: float, text: String, active: bool) -> void:
		var color: Color = CHIP_ON if active else CHIP_OFF
		var rect := Rect2(0.0, y, max(rect_size.x, 1.0), 22.0)
		draw_rect(rect, BG, true)
		draw_rect(rect, color, false, 1.5)
		var font: Font = get_font("font", "Label")
		if font != null:
			draw_string(font, Vector2(8.0, y + 15.0), text, color)
