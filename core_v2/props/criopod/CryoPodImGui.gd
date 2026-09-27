extends ImGuiCanvas

# CryoPodImGui.gd - Pantalla de la Criopod (FD-307) dibujada con ImGui/ImPlot (Paso 12).
# Port de demo_holoterminal/criopod_screen.gd (gdtk, validado) al terminal real de Odisea.
#
# No es dueña del estado: `screen_ui` (la CryoPodUI de siempre, Control) sigue siendo la
# unica fuente de verdad para pod_state()/update_snapshot()/widget_snapshot() (HUD,
# SuitOS, CryoPodHUDable). Esta hoja solo LEE esos exports cada imgui_frame y dispara la
# misma accion de escotilla (`_on_hatch_pressed`) que el boton viejo.
#
# El contenido se arma a update_hz=10 (ver CryoPodUI.gd._build_imgui_screen); el cursor
# NO se dibuja aca: HoloTerminalV2 lo escribe en HoloScreen.shader (cursor_uv) porque este
# nodo expone uses_shader_cursor() == true.

# Paleta identica a CryoPodUI.gd (elegida por luma para HoloScreen.shader).
const CYAN := Color(0.42, 0.93, 1.0)
const DIM := Color(0.42, 0.72, 0.80)
const GRID := Color(0.18, 0.36, 0.42)
const PANEL := Color(0.05, 0.12, 0.15)
const OK := Color(0.42, 1.0, 0.65)
const WARN := Color(1.0, 0.76, 0.32)

# Espacio de diseño del layout (igual al de CryoPodUI.gd). Como ImGui no tiene el
# draw_set_transform de Control, la conversion a pixeles reales del Viewport se hace a
# mano con _scale en cada imgui_frame.
const DESIGN := Vector2(1024.0, 640.0)

var screen_ui: Node = null

var body_font := 0
var big_font := 0
var _time := 0.0
var _scale := Vector2.ONE


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS  # el pulso del ECG sigue vivo con el arbol pausado
	set_update_hz(10.0)
	set_input_hz(30.0)
	var ttf := "res://assets/fonts/Silkscreen-Regular.ttf"
	body_font = add_font(ttf, 20.0)
	big_font = add_font(ttf, 56.0)
	if body_font >= 0:
		set_default_font(body_font)
	if big_font < 0:
		big_font = body_font
	connect("imgui_frame", self, "_on_imgui_frame")
	connect("redrawn", self, "_on_redrawn")
	var vp = get_viewport()
	if vp and vp.has_method("set_imgui_forward_target"):
		vp.set_imgui_forward_target(self)
	request_redraw()


func _process(delta: float) -> void:
	_time += delta


# Paso 12: esta pantalla declara soportar el cursor por shader (HoloScreen.shader
# cursor_uv). HoloTerminalV2 lo detecta con esto y deja de forzar UPDATE_ALWAYS con foco.
func uses_shader_cursor() -> bool:
	return true


# El contenido cambio (ImGuiCanvas armo un frame de verdad): un solo UPDATE_ONCE al
# Viewport que lo contiene, subiendo por la cadena hasta HoloTerminalV2 (mismo patron que
# CryoPodUI._request_redraw()).
func _on_redrawn() -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("request_redraw"):
			node.request_redraw()
			return
		node = node.get_parent()


# p in [0,1) = un ciclo cardiaco. PQRST portado tal cual de CryoPodUI.gd.
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


func _accent() -> Color:
	return WARN if (is_instance_valid(screen_ui) and bool(screen_ui.alarm)) else OK


func _p(v: Vector2) -> Vector2:
	return v * _scale


func _on_imgui_frame() -> void:
	if not is_instance_valid(screen_ui):
		return
	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	_scale = vp_size / DESIGN

	var flags := WINDOW_NO_DECORATION | WINDOW_NO_MOVE | WINDOW_NO_RESIZE | WINDOW_NO_SAVED_SETTINGS | WINDOW_NO_SCROLLBAR | WINDOW_NO_BRING_TO_FRONT_ON_FOCUS

	set_next_window_pos(Vector2.ZERO, true)
	set_next_window_size(vp_size, true)

	push_style_var_vec2(STYLE_VAR_WINDOW_PADDING, Vector2.ZERO)
	push_style_color(COL_WINDOW_BG, PANEL)
	push_style_color(COL_CHILD_BG, Color(0.03, 0.08, 0.10, 1.0))
	push_style_color(COL_TEXT, CYAN)
	push_style_color(COL_BORDER, GRID)
	push_style_color(COL_FRAME_BG, Color(0.02, 0.06, 0.08, 1.0))
	push_style_color(COL_FRAME_BG_HOVERED, Color(0.10, 0.24, 0.30, 1.0))
	push_style_color(COL_FRAME_BG_ACTIVE, Color(0.14, 0.32, 0.40, 1.0))
	push_style_color(COL_BUTTON, Color(0.13, 0.30, 0.36, 1.0))
	push_style_color(COL_BUTTON_HOVERED, Color(0.20, 0.44, 0.52, 1.0))
	push_style_color(COL_BUTTON_ACTIVE, Color(0.26, 0.56, 0.66, 1.0))
	push_style_color(COL_PLOT_HISTOGRAM, _accent())
	push_style_color(COL_SEPARATOR, DIM)

	var open := begin("##criopod", flags)
	if open:
		_header()
		_occupant()
		_vitals()
		_ecg_monitor()
		_hatch()
	end()

	pop_style_color(12)
	pop_style_var(1)


func _header() -> void:
	set_cursor_pos(_p(Vector2(28, 16)))
	text_colored(_accent(), "CRIOCÁPSULA %02d · %s · %s · %s" % [
		int(screen_ui.pod_number), String(screen_ui.occupant_name),
		tr(String(screen_ui.occupant_role)), tr(String(screen_ui.occupant_status))])
	set_cursor_pos(_p(Vector2(28, 44)))
	text_colored(CYAN, "T+%d d · %s" % [int(screen_ui.hibernation_days), tr("HIBERNACIÓN NOMINAL")])
	set_cursor_pos(_p(Vector2(28, 70)))
	text_colored(DIM, "FD-307 · %s" % tr("TERMINAL MÉDICO"))
	set_cursor_pos(_p(Vector2(28, 92)))
	separator()


func _occupant() -> void:
	set_cursor_pos(_p(Vector2(28, 112)))
	begin_child("##portrait", _p(Vector2(116, 146)))
	set_cursor_pos(_p(Vector2(18, 62)))
	text_colored(DIM, tr("SIN SEÑAL"))
	end_child()

	set_cursor_pos(_p(Vector2(164, 112)))
	text_colored(_accent(), String(screen_ui.occupant_name))
	set_cursor_pos(_p(Vector2(164, 138)))
	text_colored(CYAN, tr(String(screen_ui.occupant_role)))
	set_cursor_pos(_p(Vector2(164, 168)))
	text_colored(OK if not bool(screen_ui.alarm) else WARN, tr(String(screen_ui.occupant_status)))


func _vitals() -> void:
	var x := 28.0
	var y := 300.0
	var w := 420.0
	var body_temp_c: float = screen_ui.body_temp_c
	var integrity: float = screen_ui.integrity
	var coolant: float = screen_ui.coolant
	var oxygen: float = screen_ui.oxygen
	_bar(x, y, w, "TEMP", body_temp_c / 37.0, "%.1f °C" % body_temp_c, false)
	_bar(x, y + 58, w, "INTEGRIDAD", integrity, "%d%%" % int(round(integrity * 100.0)), true)
	_bar(x, y + 116, w, "CRIOFLUIDO", coolant, "%d%%" % int(round(coolant * 100.0)), true)
	# "O₂" (subscript, fuera de Latin-1) rompia el layout de ImGui aca: el glifo faltante en
	# la fuente Silkscreen corrompia el resto del frame (medido). "O2" ASCII es identico en
	# significado y esta dentro del rango declarado (Latin + Latin-1).
	_bar(x, y + 174, w, "O2", oxygen, "%d%%" % int(round(oxygen * 100.0)), true)


func _bar(x: float, y: float, w: float, label: String, value: float, text: String, low_is_bad: bool) -> void:
	var v := clamp(value, 0.0, 1.0)
	var col := WARN if (low_is_bad and v < 0.25) else _accent()
	set_cursor_pos(_p(Vector2(x, y)))
	text_colored(CYAN, tr(label))
	set_cursor_pos(_p(Vector2(x, y + 24)))
	text_colored(col, text)
	set_cursor_pos(_p(Vector2(x + 150, y + 22)))
	push_style_color(COL_PLOT_HISTOGRAM, col)
	progress_bar(v, _p(Vector2(w - 150.0, 14.0)), "")
	pop_style_color(1)


func _ecg_monitor() -> void:
	var bpm: float = max(float(screen_ui.bpm), 1.0)
	var hz := bpm / 60.0
	set_cursor_pos(_p(Vector2(510, 112)))
	var flags := IMPLOT_FLAGS_NO_TITLE | IMPLOT_FLAGS_NO_LEGEND | IMPLOT_FLAGS_NO_MOUSE_TEXT | IMPLOT_FLAGS_NO_MENUS | IMPLOT_FLAGS_NO_BOX_SELECT | IMPLOT_FLAGS_NO_INPUTS
	implot_push_style_color(IMPLOT_COL_PLOT_BG, PANEL)
	implot_push_style_color(IMPLOT_COL_FRAME_BG, PANEL)
	implot_push_style_color(IMPLOT_COL_AXIS_GRID, GRID)
	implot_push_style_color(IMPLOT_COL_AXIS_TEXT, DIM)
	implot_push_style_color(IMPLOT_COL_LINE, _accent())
	if implot_begin_plot("##ecg", _p(Vector2(486, 320)), flags):
		implot_setup_axes("", "", IMPLOT_AXIS_NO_TICK_LABELS, IMPLOT_AXIS_NO_TICK_LABELS)
		implot_setup_axis_limits(IMPLOT_AXIS_X1, 0.0, 1.0, true)
		implot_setup_axis_limits(IMPLOT_AXIS_Y1, -0.5, 1.2, true)
		var n := 256
		var xs := PoolRealArray()
		var ys := PoolRealArray()
		xs.resize(n)
		ys.resize(n)
		var span := 2.5 / hz
		for i in range(n):
			var f := float(i) / float(n - 1)
			var t: float = _time - span * (1.0 - f)
			xs[i] = f
			ys[i] = _ecg(wrapf(t * hz, 0.0, 1.0))
		implot_plot_line("ecg", xs, ys)
		var hx := PoolRealArray()
		var hy := PoolRealArray()
		hx.push_back(1.0)
		hy.push_back(ys[n - 1])
		implot_plot_scatter("head", hx, hy)
		implot_end_plot()
	implot_pop_style_color(5)

	set_cursor_pos(_p(Vector2(510, 452)))
	push_font(big_font)
	text_colored(_accent(), "%d" % int(round(bpm)))
	pop_font()
	# same_line(10) media contra el ancho REAL del texto anterior (offset desde el borde de
	# la ventana, no desde el cursor) puso "BPM" pegado al margen izquierdo, encima de la
	# columna de signos vitales (medido). set_cursor_pos explicito, como en _hatch(), es
	# predecible.
	set_cursor_pos(_p(Vector2(600, 478)))
	text_colored(CYAN, "BPM")
	set_cursor_pos(_p(Vector2(510, 520)))
	text_colored(CYAN, tr("HIBERNACIÓN NOMINAL") if not bool(screen_ui.alarm) else tr("ALERTA"))


func _hatch() -> void:
	var hatch_open: bool = screen_ui.has_method("is_hatch_open") and screen_ui.is_hatch_open()
	var hatch_busy: bool = screen_ui.has_method("is_hatch_busy") and screen_ui.is_hatch_busy()
	set_cursor_pos(_p(Vector2(28, 570)))
	var label := tr("CERRAR CÁPSULA") if hatch_open else tr("ABRIR CÁPSULA")
	if hatch_busy:
		push_style_color(COL_TEXT, DIM)
	if button(label, _p(Vector2(300, 50))) and not hatch_busy:
		screen_ui.call("_on_hatch_pressed")
		request_redraw()
	if hatch_busy:
		pop_style_color(1)
	same_line(320)
	set_cursor_pos(_p(Vector2(348, 584)))
	text_colored(OK if hatch_open else DIM, "%s %s" % [tr("ESTADO: CÁPSULA"), tr("ABIERTA") if hatch_open else tr("CERRADA")])
