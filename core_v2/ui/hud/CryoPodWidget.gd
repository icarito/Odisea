extends PanelContainer
class_name CryoPodWidget

# CryoPodWidget.gd - Widget compacto de una criocapsula (FD-307).
# Hace juego con CryoPodUI: mismos colores, mismo corazon, mismo trazo. Reusa su _ecg()
# en vez de tener su propia onda, para que la del slot y la de la pantalla sean la misma.

const CryoPodUI = preload("res://core_v2/props/criopod/CryoPodUI.gd")
const HudWidgetAction = preload("res://core_v2/ui/hud/HudWidgetAction.gd")
const HudViewMount = preload("res://core_v2/ui/hud/HudViewMount.gd")

onready var _vitals: Control = $Margin/VBox/Vitals
onready var _status_label: Label = $Margin/VBox/ActionRow/StatusLabel
onready var _action_button: Button = $Margin/VBox/ActionRow/ActionButton

var _screen_id: String = ""
var _snapshot: Dictionary = {}
var _time: float = 0.0
var _font: DynamicFont = null

func _ready() -> void:
	_font = CryoPodUI.small_font(14)
	if _action_button != null:
		_action_button.add_font_override("font", _font)
		if not _action_button.is_connected("pressed", self, "_on_action_pressed"):
			_action_button.connect("pressed", self, "_on_action_pressed")
	if _status_label != null:
		_status_label.add_font_override("font", _font)
	if _vitals != null and not _vitals.is_connected("draw", self, "_draw_vitals"):
		_vitals.connect("draw", self, "_draw_vitals")
	set_panel_style()

func set_panel_style() -> void:
	var box := StyleBoxFlat.new()
	# B3a: panel semi-transparente (alfa ~0.7); en tier LOW queda opaco como antes.
	box.bg_color = Color(0.02, 0.07, 0.09, min(0.92, HudViewMount.widget_alpha()))
	box.border_color = CryoPodUI.DIM
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 2.0
	box.content_margin_right = 2.0
	add_stylebox_override("panel", box)

func _process(delta: float) -> void:
	_time += delta
	if _vitals != null:
		_vitals.update()

# La accion por defecto del widget es la de la capsula: abrir o cerrar la escotilla.
func _on_action_pressed() -> void:
	HudWidgetAction.perform(self, _screen_id, "toggle_hatch")

func update_snapshot(snapshot: Dictionary) -> void:
	set_snapshot(snapshot)

func set_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	_screen_id = String(snapshot.get("id", _screen_id))
	if not is_inside_tree():
		return

	var offline: bool = String(snapshot.get("source", "online")) == "offline"
	var open: bool = bool(snapshot.get("hatch_open", false))
	var busy: bool = bool(snapshot.get("hatch_busy", false))

	if _status_label != null:
		if offline:
			_status_label.text = tr("OFFLINE")
		else:
			_status_label.text = String(snapshot.get("occupant_status", tr("SIN DATOS")))
		_status_label.add_color_override("font_color", _accent())

	if _action_button != null:
		_action_button.disabled = offline or busy
		if offline:
			_action_button.text = tr("OFFLINE")
		elif busy:
			_action_button.text = tr("...")
		else:
			_action_button.text = tr("CERRAR") if open else tr("ABRIR")

	if _vitals != null:
		_vitals.update()

func _accent() -> Color:
	return CryoPodUI.WARN if bool(_snapshot.get("alarm", false)) else CryoPodUI.CYAN

func _draw_vitals() -> void:
	if _font == null:
		return
	var c: Control = _vitals
	var w: float = c.rect_size.x
	var h: float = c.rect_size.y
	var accent := _accent()
	var bpm: float = float(_snapshot.get("bpm", 12.0))
	var hz: float = max(bpm, 1.0) / 60.0
	var beat: float = wrapf(_time * hz, 0.0, 1.0)

	# nombre del ocupante + corazon y pulso, en la misma linea
	var name_text: String = String(_snapshot.get("occupant_name", ""))
	if name_text.empty():
		name_text = String(_snapshot.get("title", tr("CRIOCÁPSULA")))
	c.draw_string(_font, Vector2(0, 14), name_text, accent)

	var bpm_text: String = "%d" % int(round(bpm))
	var bpm_w: float = _font.get_string_size(bpm_text).x
	c.draw_string(_font, Vector2(w - bpm_w, 14), bpm_text, accent)
	var pulse: float = 1.0 + 0.3 * exp(-beat * 9.0)
	_draw_heart(c, Vector2(w - bpm_w - 12, 9), 7.0 * pulse, accent)

	# trazo: el mismo PQRST de la pantalla, en miniatura
	var top: float = 24.0
	var plot_h: float = max(h - top, 8.0)
	var mid: float = top + plot_h * 0.62
	var amp: float = plot_h * 0.40
	var samples: int = int(max(w / 2.0, 8.0))
	var span: float = 2.0 / hz
	var pts := PoolVector2Array()
	for i in range(samples):
		var f: float = float(i) / float(samples - 1)
		var t: float = _time - span * (1.0 - f)
		pts.append(Vector2(w * f, mid - CryoPodUI._ecg(wrapf(t * hz, 0.0, 1.0)) * amp))
	c.draw_polyline(pts, accent, 1.0)

func _draw_heart(c: Control, center: Vector2, s: float, col: Color) -> void:
	var pts := PoolVector2Array()
	for i in range(20):
		var t: float = float(i) / 20.0 * TAU
		var hx: float = 16.0 * pow(sin(t), 3.0)
		var hy: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(center + Vector2(hx, -hy) * (s / 16.0))
	c.draw_colored_polygon(pts, col)
