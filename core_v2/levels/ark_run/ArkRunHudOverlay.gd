extends CanvasLayer

# FD-324 F7 — HUD diegético mínimo del vertical slice (<200 líneas).
# CanvasLayer + Controls/Labels/Line2D: fase y objetivo en una línea, cronómetro
# y mejor tiempo, minimapa del cilindro (corte radial + barra z), gravedad local
# con flecha, barra de Δv y la línea compacta de controles. No toca física ni
# estado de juego; sólo lee el snapshot que le pasa ArkRunSliceWiring a 10 Hz.

const PANEL_BG := Color(0.02, 0.05, 0.08, 0.72)
const TEXT := Color(0.72, 0.94, 1.0, 1.0)
const DIM := Color(0.45, 0.62, 0.72, 1.0)
const BRIDGE_COLOR := Color(1.0, 0.85, 0.25, 1.0)
const ENGINE_COLOR := Color(1.0, 0.38, 0.15, 1.0)
const PILOT_COLOR := Color(0.35, 1.0, 0.75, 1.0)
const DV_BASE := Color(0.25, 0.65, 1.0, 0.9)
const DV_ACTIVE := Color(1.0, 0.75, 0.2, 1.0)

var _phase_label: Label = null
var _timer_label: Label = null
var _best_label: Label = null
var _stats_label: Label = null
var _controls_label: Label = null
var _circle: Line2D = null
var _z_bar: ColorRect = null
var _bridge_mark: ColorRect = null
var _engine_mark: ColorRect = null
var _pilot_mark: ColorRect = null
var _gravity_arrow: Line2D = null
var _dv_fill: ColorRect = null
var _panel: ColorRect = null

const MAP_SIZE := 168.0; const MAP_RADIUS := 62.0

func _ready() -> void:
	layer = 20
	_build()

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_color_override("font_color", color)
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.8))
	label.add_constant_override("shadow_offset_x", 1)
	label.add_constant_override("shadow_offset_y", 1)
	return label

func _rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	return rect

func _build() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_phase_label = _label("NÚCLEO ZERO-G", 22, TEXT)
	_phase_label.set_position(Vector2(28, 18))
	root.add_child(_phase_label)

	_timer_label = _label("00:00.00", 26, TEXT)
	_timer_label.set_anchors_and_margins_preset(Control.PRESET_TOP_RIGHT)
	_timer_label.set_position(Vector2(-228, 14))
	_timer_label.set_size(Vector2(200, 32))
	_timer_label.align = Label.ALIGN_RIGHT
	root.add_child(_timer_label)

	_best_label = _label("MEJOR --:--.--", 15, DIM)
	_best_label.set_anchors_and_margins_preset(Control.PRESET_TOP_RIGHT)
	_best_label.set_position(Vector2(-228, 48))
	_best_label.set_size(Vector2(200, 20))
	_best_label.align = Label.ALIGN_RIGHT
	root.add_child(_best_label)

	_stats_label = _label("g 0.0 · Δv 0%", 15, TEXT)
	_stats_label.set_anchors_and_margins_preset(Control.PRESET_BOTTOM_LEFT)
	_stats_label.set_position(Vector2(28, -104))
	_stats_label.set_size(Vector2(360, 20))
	root.add_child(_stats_label)

	_controls_label = _label(
		"WASD mover · Espacio saltar · F/LT propulsor · E/RT cuerda · TAB/R1 autonav · Backspace reiniciar",
		13, DIM
	)
	_controls_label.set_anchors_and_margins_preset(Control.PRESET_BOTTOM_LEFT)
	_controls_label.set_position(Vector2(28, -34))
	_controls_label.set_size(Vector2(1100, 20))
	root.add_child(_controls_label)

	_panel = _rect(PANEL_BG)
	_panel.set_anchors_and_margins_preset(Control.PRESET_TOP_RIGHT)
	_panel.set_position(Vector2(-208, 78))
	_panel.set_size(Vector2(MAP_SIZE + 24.0, MAP_SIZE + 24.0))
	root.add_child(_panel)

	var map := Control.new()
	map.name = "Minimap"
	map.set_anchors_and_margins_preset(Control.PRESET_TOP_RIGHT)
	map.set_position(Vector2(-196, 90))
	map.set_size(Vector2(MAP_SIZE, MAP_SIZE))
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(map)

	_circle = Line2D.new()
	_circle.width = 1.5
	_circle.default_color = DIM
	var center := Vector2(MAP_RADIUS + 8.0, MAP_RADIUS + 8.0)
	for i in range(33):
		var angle: float = TAU * float(i) / 32.0
		_circle.add_point(center + Vector2(cos(angle), sin(angle)) * MAP_RADIUS)
	map.add_child(_circle)

	_z_bar = _rect(Color(0.16, 0.25, 0.33, 0.9))
	_z_bar.set_position(Vector2(MAP_RADIUS * 2.0 + 20.0, 8.0))
	_z_bar.set_size(Vector2(10.0, MAP_RADIUS * 2.0))
	map.add_child(_z_bar)

	_bridge_mark = _rect(BRIDGE_COLOR)
	_bridge_mark.set_size(Vector2(18.0, 4.0))
	_bridge_mark.set_position(Vector2(MAP_RADIUS * 2.0 + 16.0, 8.0))
	map.add_child(_bridge_mark)

	_engine_mark = _rect(ENGINE_COLOR)
	_engine_mark.set_size(Vector2(18.0, 4.0))
	_engine_mark.set_position(Vector2(MAP_RADIUS * 2.0 + 16.0, MAP_RADIUS * 2.0 + 4.0))
	map.add_child(_engine_mark)

	_pilot_mark = _rect(PILOT_COLOR)
	_pilot_mark.set_size(Vector2(6.0, 6.0))
	map.add_child(_pilot_mark)

	_gravity_arrow = Line2D.new()
	_gravity_arrow.width = 2.0
	_gravity_arrow.default_color = PILOT_COLOR
	map.add_child(_gravity_arrow)

	_dv_fill = _rect(DV_BASE)
	_dv_fill.set_anchors_and_margins_preset(Control.PRESET_BOTTOM_LEFT)
	_dv_fill.set_position(Vector2(28, -76))
	_dv_fill.set_size(Vector2(0.0, 7.0))
	root.add_child(_dv_fill)

func refresh(data: Dictionary) -> void:
	if _phase_label == null:
		return
	_phase_label.text = String(data.get("phase", ""))
	_timer_label.text = _format_time(float(data.get("timer", 0.0)))
	var best: float = float(data.get("best", -1.0))
	_best_label.text = "MEJOR " + (_format_time(best) if best >= 0.0 and best < 1.0e9 else "--:--.--")
	var g: float = float(data.get("g", 0.0))
	var thrusting: bool = bool(data.get("thrusting", false))
	var state := "g %.1f m/s² · Δv %d%%" % [g, int(round(float(data.get("dv", 0.0)) * 100.0))]
	var rope: String = String(data.get("rope", "IDLE"))
	if rope == "ATTACHED":
		state += " · CUERDA ENGANCHADA"
	elif rope == "REELING":
		state += " · CUERDA RETRACCIÓN"
	elif rope == "READY":
		state += " · CUERDA LISTA"
	if thrusting:
		state = "PROPULSOR ACTIVO · " + state
	_stats_label.text = state
	_dv_fill.color = DV_ACTIVE if thrusting else DV_BASE
	_dv_fill.rect_size = Vector2(180.0 * clamp(float(data.get("dv", 0.0)), 0.0, 1.0), 7.0)
	var controls: String = String(data.get("controls", ""))
	if controls != "" and _controls_label.text != controls:
		_controls_label.text = controls

	var map_center := Vector2(MAP_RADIUS + 8.0, MAP_RADIUS + 8.0)
	_pilot_mark.rect_position = map_center + Vector2(
		clamp(float(data.get("radial", 0.0)), -1.0, 1.0) * (MAP_RADIUS - 4.0), 0.0
	) - Vector2(3.0, 3.0)
	_bridge_mark.rect_position.y = 8.0 + (1.0 - clamp(float(data.get("bridge", 1.0)), 0.0, 1.0)) * (MAP_RADIUS * 2.0)
	_engine_mark.rect_position.y = 8.0 + (1.0 - clamp(float(data.get("engine", 0.0)), 0.0, 1.0)) * (MAP_RADIUS * 2.0)
	_panel.color = PANEL_BG

	var g_dir := Vector2(float(data.get("g_dir_x", 0.0)), float(data.get("g_dir_z", 0.0)))
	if g_dir.length_squared() > 0.0001:
		g_dir = g_dir.normalized()
		_gravity_arrow.points = PoolVector2Array([
			map_center + g_dir * 8.0, map_center + g_dir * 30.0
		])
		_gravity_arrow.visible = true
	else:
		_gravity_arrow.visible = false

func _format_time(seconds: float) -> String:
	var clamped: float = max(seconds, 0.0)
	var minutes: int = int(clamped / 60.0)
	var secs: float = fmod(clamped, 60.0)
	return "%02d:%05.2f" % [minutes, secs]

func get_phase_label() -> Label:
	return _phase_label
