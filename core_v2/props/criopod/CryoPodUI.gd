extends Control
class_name CryoPodUI

# CryoPodUI.gd - Ficha del ocupante de una criocapsula (FD-307).
# Todo se dibuja en _draw: no hay assets de icono todavia (el retrato y el corazon son
# placeholders vectoriales). La animacion es pura funcion de _time, sin buffer de muestras.

const HudWidgetAction = preload("res://core_v2/ui/hud/HudWidgetAction.gd")
const HeadingFont = preload("res://assets/fonts/Heading_Font.tres")
# B3b: cuerpo chico en Silkscreen (pixel font, mas legible en tamanos chicos que SyneMono).
# Se arma en codigo duplicando SyneMono_Prologue_20: de ahi sale el fallback DungGeunMo que
# ya cubre acentos y Hangul (mismo patron que TinyFont.tres).
const SmallFontTemplate = preload("res://assets/fonts/SyneMono_Prologue_20.tres")
const SmallFontData = preload("res://assets/fonts/Silkscreen-Regular.ttf")

static func small_font(size: int) -> DynamicFont:
	var font: DynamicFont = (SmallFontTemplate as DynamicFont).duplicate() as DynamicFont
	font.font_data = SmallFontData
	font.size = size
	return font

# HoloTerminalV2 redimensiona su Viewport (escala de movil/web): dibujar en pixeles
# absolutos hacia el borde de abajo desarmaba el layout. Todo se dibuja en este espacio
# de diseño y se escala de una vez; el boton usa anclas proporcionales al mismo diseño.
const DESIGN := Vector2(1024.0, 640.0)

# HoloScreen.shader reconstruye la opacidad desde la LUMINANCIA del pixel
# (coverage = luma / ink_level, con ink_level = 0.686): lo oscuro es vidrio y se ve a
# traves. El DIM viejo (0.17,0.42,0.48) tenia luma 0.35 -> 51% de cobertura, y por eso
# PILOTO, las etiquetas de las barras y la grilla salian lavadas. Estos valores estan
# elegidos por luma, no a ojo: DIM llega a 0.64 (93% de cobertura).
const CYAN := Color(0.42, 0.93, 1.0)
const DIM := Color(0.42, 0.72, 0.80)
const GRID := Color(0.18, 0.36, 0.42)
const PANEL := Color(0.05, 0.12, 0.15)
const OK := Color(0.42, 1.0, 0.65)
const WARN := Color(1.0, 0.76, 0.32)

# El rotulo es plantilla + numero: como texto libre no habia forma de traducirlo.
export(int) var pod_number := 7
export(String) var occupant_name := "ELÍAS VEGA"
export(String) var occupant_role := "PILOTO"
export(String) var occupant_status := "ESTABLE"
export(bool) var alarm := false
export(float) var bpm := 12.0             # hibernacion: el corazon late lentisimo
export(float) var body_temp_c := 4.2
export(float, 0.0, 1.0) var integrity := 0.96
export(float, 0.0, 1.0) var coolant := 0.71
export(float, 0.0, 1.0) var oxygen := 0.88
export(int) var hibernation_days := 4212

var _time := 0.0
var _big_font: DynamicFont = null
var _body_font: DynamicFont = null
var _screen_id := "ship:cryopod:elias"
var _hatch_open := false
var _hatch_busy := false

onready var _hatch_button: Button = get_node_or_null("HatchButton")

func _ready() -> void:
	pause_mode = PAUSE_MODE_PROCESS  # el modo HUD pausa el arbol; el pulso sigue vivo
	_body_font = small_font(20)
	_big_font = small_font(56)
	if _hatch_button != null and not _hatch_button.is_connected("pressed", self, "_on_hatch_pressed"):
		_hatch_button.connect("pressed", self, "_on_hatch_pressed")
		_style_hatch_button()
	_refresh_hatch_button()

# El tema por defecto deja el boton en gris oscuro, y oscuro en este shader es vidrio: el
# boton desaparecia. Un chip con relleno claro y borde del acento.
func _style_hatch_button() -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.13, 0.30, 0.36) if state != "hover" else Color(0.20, 0.44, 0.52)
		box.border_color = CYAN
		box.set_border_width_all(2)
		box.set_corner_radius_all(3)
		box.content_margin_left = 14.0
		box.content_margin_right = 14.0
		box.content_margin_top = 8.0
		box.content_margin_bottom = 8.0
		_hatch_button.add_stylebox_override(state, box)
	_hatch_button.add_font_override("font", _body_font)
	for state in ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus"]:
		_hatch_button.add_color_override(state, CYAN)
	_hatch_button.add_color_override("font_color_disabled", DIM)

# La escotilla se opera desde aca. HudWidgetAction resuelve a donde va: al SuitOS local
# cuando esta UI vive en el terminal del mundo, o al canal del control remoto cuando la
# copia la monto el control. La pantalla nunca toca el RotatingObjectV2 directo.
func _on_hatch_pressed() -> void:
	HudWidgetAction.perform(self, _screen_id, "toggle_hatch")

func update_snapshot(snapshot: Dictionary) -> void:
	_screen_id = String(snapshot.get("id", _screen_id))
	_hatch_open = bool(snapshot.get("hatch_open", _hatch_open))
	_hatch_busy = bool(snapshot.get("hatch_busy", false))
	occupant_name = String(snapshot.get("occupant_name", occupant_name))
	occupant_role = String(snapshot.get("occupant_role", occupant_role))
	occupant_status = String(snapshot.get("occupant_status", occupant_status))
	alarm = bool(snapshot.get("alarm", alarm))
	_refresh_hatch_button()
	update()
	_request_redraw()

# Lo propio del pod que el componente mete en el snapshot (widget y control remoto).
func pod_state() -> Dictionary:
	return {
		"occupant_name": occupant_name,
		"occupant_role": occupant_role,
		"occupant_status": occupant_status,
		"alarm": alarm,
		"bpm": bpm,
		"hibernation_days": hibernation_days,
	}

func _refresh_hatch_button() -> void:
	if _hatch_button == null:
		return
	_hatch_button.disabled = _hatch_busy
	_hatch_button.text = tr("CERRAR CÁPSULA") if _hatch_open else tr("ABRIR CÁPSULA")

# El ECG es funcion de _time, asi que podria redibujarse cada frame; a 60 Hz eso obliga al
# Viewport de la terminal a re-renderizar 60 veces por segundo en aparatos flacos. A 10 Hz el
# trazo sigue leyendose vivo. El terminal esta en static_content: no redibuja solo, hay que
# pedirselo (mismo patron que CoolantSchematicPanel).
const REDRAW_HZ := 10.0
var _redraw_accum := 0.0

func _process(delta: float) -> void:
	_time += delta
	_redraw_accum += delta
	if _redraw_accum < 1.0 / REDRAW_HZ:
		return
	_redraw_accum -= 1.0 / REDRAW_HZ
	update()
	_request_redraw()


func _request_redraw() -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("request_redraw"):
			node.request_redraw()
			return
		node = node.get_parent()

func _accent() -> Color:
	return WARN if alarm else CYAN

# --- trazo ECG -------------------------------------------------------------
# p in [0,1) = un ciclo cardiaco. Complejo PQRST aproximado, en [-0.35, 1.0].
static func _ecg(p: float) -> float:
	if p < 0.10:
		return 0.12 * sin(p / 0.10 * PI)
	if p < 0.16:
		return 0.0
	if p < 0.20:
		return -0.15 * sin((p - 0.16) / 0.04 * PI)
	if p < 0.24:
		return (p - 0.20) / 0.04
	if p < 0.28:
		return 1.0 - (p - 0.24) / 0.04 * 1.35
	if p < 0.33:
		return -0.35 + (p - 0.28) / 0.05 * 0.35
	if p < 0.45:
		return 0.0
	if p < 0.70:
		return 0.22 * sin((p - 0.45) / 0.25 * PI)
	return 0.0

func _draw() -> void:
	if rect_size.x <= 0.0 or rect_size.y <= 0.0:
		return
	draw_set_transform(Vector2.ZERO, 0.0, rect_size / DESIGN)
	var w := DESIGN.x
	var h := DESIGN.y
	var accent := _accent()

	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.06, 0.08, 0.85))  # oscuro = vidrio (ver nota de color)

	# cabecera
	draw_string(HeadingFont, Vector2(28, 56), tr("CRIOCÁPSULA %02d") % pod_number, accent)
	draw_line(Vector2(28, 78), Vector2(w - 28, 78), DIM, 2.0)

	var split := w * 0.46
	_draw_occupant(28.0, 104.0, split - 44.0)
	_draw_vitals(split, 104.0, w - split - 28.0, h - 132.0)

func _draw_occupant(x: float, y: float, col_w: float) -> void:
	var accent := _accent()

	# placeholder de retrato: marco + aspa. Reemplazar por Texture cuando exista.
	var frame := Rect2(x, y, 116, 146)
	draw_rect(frame, PANEL)
	draw_rect(frame, DIM, false, 2.0)
	draw_line(frame.position, frame.position + frame.size, DIM, 2.0)
	draw_line(Vector2(frame.end.x, frame.position.y), Vector2(frame.position.x, frame.end.y), DIM, 2.0)

	var tx := x + 136
	draw_string(_body_font, Vector2(tx, y + 28), occupant_name, accent)
	draw_string(_body_font, Vector2(tx, y + 58), tr(occupant_role), CYAN)
	var status_col := WARN if alarm else OK
	draw_rect(Rect2(tx, y + 76, 12, 12), status_col)
	draw_string(_body_font, Vector2(tx + 22, y + 88), tr(occupant_status), status_col)
	draw_string(_body_font, Vector2(tx, y + 128), tr("T+%d d") % hibernation_days, CYAN)

	# barras de estado
	var by := y + 190
	_draw_bar(x, by, col_w, "TEMP", body_temp_c / 37.0, "%.1f °C" % body_temp_c, false)
	_draw_bar(x, by + 54, col_w, "INTEGRIDAD", integrity, "%d%%" % int(round(integrity * 100.0)))
	_draw_bar(x, by + 108, col_w, "CRIOFLUIDO", coolant, "%d%%" % int(round(coolant * 100.0)))
	_draw_bar(x, by + 162, col_w, "O₂", oxygen, "%d%%" % int(round(oxygen * 100.0)))

func _draw_bar(x: float, y: float, w: float, label: String, value: float, text: String, low_is_bad: bool = true) -> void:
	var v := clamp(value, 0.0, 1.0)
	var col := WARN if (low_is_bad and v < 0.25) else _accent()
	draw_string(_body_font, Vector2(x, y), tr(label), CYAN)
	var text_w := _body_font.get_string_size(text).x
	draw_string(_body_font, Vector2(x + w - text_w, y), text, col)
	var track := Rect2(x, y + 10, w, 10)
	draw_rect(track, PANEL)
	draw_rect(Rect2(x, y + 10, w * v, 10), col)
	draw_rect(track, DIM, false, 2.0)

func _draw_vitals(x: float, y: float, w: float, h: float) -> void:
	var accent := _accent()
	var hz := max(bpm, 1.0) / 60.0
	var beat := wrapf(_time * hz, 0.0, 1.0)

	# corazon palpitando (placeholder vectorial)
	var pulse := 1.0 + 0.25 * exp(-beat * 9.0)
	_draw_heart(Vector2(x + 34, y + 34), 26.0 * pulse, accent)

	draw_string(_big_font, Vector2(x + 80, y + 50), "%d" % int(round(bpm)), accent)
	draw_string(_body_font, Vector2(x + 80 + _big_font.get_string_size("%d" % int(round(bpm))).x + 10, y + 50), tr("BPM"), CYAN)

	# trazo
	var plot := Rect2(x, y + 90, w, h - 130)
	draw_rect(plot, PANEL)
	draw_rect(plot, DIM, false, 2.0)
	for i in range(1, 6):
		var gy := plot.position.y + plot.size.y * i / 6.0
		draw_line(Vector2(plot.position.x, gy), Vector2(plot.end.x, gy), GRID, 1.0)

	# 2.5 ciclos a lo ancho, barriendo a la izquierda
	var samples := int(plot.size.x / 2.0)
	var span := 2.5 / hz
	var mid := plot.position.y + plot.size.y * 0.62
	var amp := plot.size.y * 0.42
	var pts := PoolVector2Array()
	for i in range(samples):
		var f := float(i) / float(samples - 1)
		var t: float = _time - span * (1.0 - f)
		var py := mid - _ecg(wrapf(t * hz, 0.0, 1.0)) * amp
		pts.append(Vector2(plot.position.x + plot.size.x * f, py))
	draw_polyline(pts, accent, 3.0)
	# cabeza del barrido
	draw_circle(pts[pts.size() - 1], 4.0, accent)

	draw_string(_body_font, Vector2(x, plot.end.y + 26), tr("HIBERNACIÓN NOMINAL") if not alarm else tr("ALERTA"),
		CYAN if not alarm else WARN)

func _draw_heart(c: Vector2, s: float, col: Color) -> void:
	var pts := PoolVector2Array()
	for i in range(28):
		var t := float(i) / 28.0 * TAU
		var hx := 16.0 * pow(sin(t), 3.0)
		var hy := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(c + Vector2(hx, -hy) * (s / 16.0))
	draw_colored_polygon(pts, col)
