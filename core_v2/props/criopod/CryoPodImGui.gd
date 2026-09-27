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

const ImGuiOdiseaFonts = preload("res://core_v2/ui/hud/ImGuiOdiseaFonts.gd")
const ImGuiOdiseaTheme = preload("res://core_v2/ui/hud/ImGuiOdiseaTheme.gd")

# Estilo diegetico del ECG (Paso 12b, monitor de fosforo): gateado a v0.5.4-nightly2
# (ImGuiOdiseaTheme.supported() == has_method("implot_set_next_line_style")). Sin esa
# API el trazo vuelve a implot_plot_line/implot_plot_scatter tal cual estaba (nightly1,
# v0.5.3 via CryoPodUI._build_imgui_screen que ni instancia este nodo sin el modulo).
const ECG_SEGMENTS := 32          # tramos de la polilinea (estela de fosforo + resplandor)
const ECG_GAP_FRAC := 0.035       # hueco de borrado justo delante de la cabeza del barrido
const ECG_BEAT_DECAY := 0.12      # segundos: caida del destello de latido (corazon + BPM)

var screen_ui: Node = null

var body_font := 0
var big_font := 0
var heading_font := 0
var _time := 0.0
var _scale := Vector2.ONE


func _ready() -> void:
	# Avisar a la terminal que la contiene (subiendo por los ancestros, igual que
	# CryoPodUI._request_redraw) que el cursor va por shader: este nodo entra al arbol
	# diferido, despues del primer tick en que HoloTerminalV2 sondeaba a su contenido, y
	# sin el aviso el cursor viejo quedaba tapado por este canvas y no se veia ninguno.
	call_deferred("_announce_shader_cursor")
	pause_mode = Node.PAUSE_MODE_PROCESS  # el pulso del ECG sigue vivo con el arbol pausado
	set_update_hz(10.0)
	set_input_hz(30.0)
	# Titulo Sixtyfour 36px (igual que CryoPodUI.HeadingFont); cuerpo/numeros a
	# ProggyClean (default de ImGui) en el motor que lo soporte, Silkscreen si no -- ver
	# ImGuiOdiseaFonts.gd. body=20 (rotulos), numbers=56 (BPM grande).
	var fonts := ImGuiOdiseaFonts.setup(self, 20.0, 56.0, 36.0)
	body_font = fonts.body
	big_font = fonts.numbers
	heading_font = fonts.title
	set_default_font(body_font)
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


func _announce_shader_cursor() -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("enable_shader_cursor"):
			node.enable_shader_cursor()
			return
		node = node.get_parent()


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
	# Tema monocromo cian (ImGuiOdiseaTheme, comun a las 5 piezas ImGui de Odisea): el
	# acento nominal es CYAN (antes era OK/verde); WARN sigue siendo el acento calido de
	# alarma para que nunca se pierda (Manual del Tripulante SS6).
	return WARN if (is_instance_valid(screen_ui) and bool(screen_ui.alarm)) else CYAN


# Fraccion 0..1 = intensidad del destello de latido (corazon + numero de BPM), calculada
# sin estado propio a partir de _time y hz: decae exponencialmente desde el pico R
# (p=0.22 en _ecg(), ver el tramo QRS arriba) con constante ECG_BEAT_DECAY. Funciona
# igual de bien si el redibujado (10 Hz) cae justo en el pico o un poco despues.
func _beat_pulse(hz: float) -> float:
	var cycle := wrapf(_time * hz, 0.0, 1.0)
	var since_peak_sec: float = wrapf(cycle - 0.22, 0.0, 1.0) / hz
	return exp(-since_peak_sec / ECG_BEAT_DECAY)


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
	ImGuiOdiseaTheme.push_window(self, _accent())

	var open := begin("##criopod", flags)
	if open:
		_header()
		_occupant()
		_vitals()
		_ecg_monitor()
		_hatch()
	end()

	ImGuiOdiseaTheme.pop_window(self)
	pop_style_var(1)


func _header() -> void:
	# Titulo con HeadingFont (Sixtyfour 36px, igual que CryoPodUI.HeadingFont): una linea
	# a 36px mide ~44px de alto, mas que los 28px de gap que tenia esta cabecera cuando
	# todo iba en Silkscreen 20px -- las lineas de abajo (y _occupant()) se corrieron
	# +20px para no solaparse (medido).
	set_cursor_pos(_p(Vector2(28, 16)))
	push_font(heading_font)
	text_colored(_accent(), "CRIOCÁPSULA %02d · %s · %s · %s" % [
		int(screen_ui.pod_number), String(screen_ui.occupant_name),
		tr(String(screen_ui.occupant_role)), tr(String(screen_ui.occupant_status))])
	pop_font()
	set_cursor_pos(_p(Vector2(28, 60)))
	text_colored(CYAN, "T+%d d · %s" % [int(screen_ui.hibernation_days), tr("HIBERNACIÓN NOMINAL")])
	set_cursor_pos(_p(Vector2(28, 86)))
	text_colored(DIM, "FD-307 · %s" % tr("TERMINAL MÉDICO"))
	set_cursor_pos(_p(Vector2(28, 108)))
	separator()


func _occupant() -> void:
	set_cursor_pos(_p(Vector2(28, 132)))
	begin_child("##portrait", _p(Vector2(116, 146)))
	set_cursor_pos(_p(Vector2(18, 62)))
	text_colored(DIM, tr("SIN SEÑAL"))
	end_child()

	set_cursor_pos(_p(Vector2(164, 132)))
	text_colored(_accent(), String(screen_ui.occupant_name))
	set_cursor_pos(_p(Vector2(164, 158)))
	text_colored(CYAN, tr(String(screen_ui.occupant_role)))
	set_cursor_pos(_p(Vector2(164, 188)))
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
	var accent := _accent()
	var diegetic := ImGuiOdiseaTheme.supported(self)
	set_cursor_pos(_p(Vector2(510, 112)))
	var flags := IMPLOT_FLAGS_NO_TITLE | IMPLOT_FLAGS_NO_LEGEND | IMPLOT_FLAGS_NO_MOUSE_TEXT | IMPLOT_FLAGS_NO_MENUS | IMPLOT_FLAGS_NO_BOX_SELECT | IMPLOT_FLAGS_NO_INPUTS
	ImGuiOdiseaTheme.push_plot(self, accent)
	if implot_begin_plot("##ecg", _p(Vector2(486, 320)), flags):
		implot_setup_axes("", "", IMPLOT_AXIS_NO_TICK_LABELS, IMPLOT_AXIS_NO_TICK_LABELS)
		implot_setup_axis_limits(IMPLOT_AXIS_X1, 0.0, 1.0, true)
		implot_setup_axis_limits(IMPLOT_AXIS_Y1, -0.5, 1.2, true)
		var n := 256
		var xs := PoolRealArray()
		var ys := PoolRealArray()
		xs.resize(n)
		ys.resize(n)
		# Periodo del barrido = el mismo "2.5 ciclos visibles" que ya estaba tuneado.
		var sweep := 2.5 / hz
		var head_frac := wrapf(_time / sweep, 0.0, 1.0)
		var alphas := PoolRealArray()
		alphas.resize(n)
		for i in range(n):
			var f := float(i) / float(n - 1)
			if diegetic:
				# Barrido tipo monitor de hospital: la cabeza recorre x=[0,1) y vuelve a
				# empezar. age=0 en la cabeza (recien escrito), age->1 en lo mas viejo
				# (a punto de ser tapado por la cabeza): ahi va el hueco de borrado corto
				# (ECG_GAP_FRAC) y, antes de eso, el desvanecido de fosforo (1-age).
				var age := wrapf(head_frac - f, 0.0, 1.0)
				var t_written: float = _time - age * sweep
				xs[i] = f
				ys[i] = _ecg(wrapf(t_written * hz, 0.0, 1.0))
				alphas[i] = 0.0 if age > 1.0 - ECG_GAP_FRAC else clamp(1.0 - age, 0.0, 1.0)
			else:
				# Motor sin la API nueva: scroll continuo tal cual estaba (sin barrido/gap).
				var t: float = _time - sweep * (1.0 - f)
				xs[i] = f
				ys[i] = _ecg(wrapf(t * hz, 0.0, 1.0))
		if diegetic:
			_ecg_draw_paper_grid()
			_ecg_draw_diegetic(xs, ys, alphas, accent, n)
			var head_val: float = _ecg(wrapf(_time * hz, 0.0, 1.0))
			_ecg_draw_head(head_frac, head_val, accent, _beat_pulse(hz))
		else:
			implot_plot_line("ecg", xs, ys)
			var hx := PoolRealArray()
			var hy := PoolRealArray()
			hx.push_back(1.0)
			hy.push_back(ys[n - 1])
			implot_plot_scatter("head", hx, hy)
		implot_end_plot()
	ImGuiOdiseaTheme.pop_plot(self)

	var pulse := _beat_pulse(hz) if diegetic else 0.0
	# Destello por latido: brillo (no escala -- ImGuiCanvas no expone font-scale) sobre
	# el numero de BPM, lerpeado sin llegar a blanco puro (queda "mas cian", no lavado).
	var bpm_color := accent.linear_interpolate(Color(0.75, 1.0, 1.0), pulse * 0.35)
	set_cursor_pos(_p(Vector2(510, 452)))
	push_font(big_font)
	text_colored(bpm_color, "%d" % int(round(bpm)))
	pop_font()
	# same_line(10) media contra el ancho REAL del texto anterior (offset desde el borde de
	# la ventana, no desde el cursor) puso "BPM" pegado al margen izquierdo, encima de la
	# columna de signos vitales (medido). set_cursor_pos explicito, como en _hatch(), es
	# predecible.
	set_cursor_pos(_p(Vector2(600, 478)))
	text_colored(CYAN, "BPM")
	set_cursor_pos(_p(Vector2(510, 520)))
	text_colored(CYAN, tr("HIBERNACIÓN NOMINAL") if not bool(screen_ui.alarm) else tr("ALERTA"))


# Grilla mayor/menor como papel de ECG (mas oscuras las menores): 8 columnas (mayor cada
# 4ta) x 4 filas (mayor cada 2da). Detras del trazo (se llama antes de _ecg_draw_diegetic).
func _ecg_draw_paper_grid() -> void:
	var pos := implot_get_plot_pos()
	var size := implot_get_plot_size()
	implot_push_plot_clip_rect()
	var cols := 8
	for c in range(1, cols):
		var x := pos.x + size.x * float(c) / float(cols)
		var major := c % 4 == 0
		imgui_draw_line(Vector2(x, pos.y), Vector2(x, pos.y + size.y), Color(GRID.r, GRID.g, GRID.b, 0.5 if major else 0.2), 1.0)
	var rows := 4
	for r in range(1, rows):
		var y := pos.y + size.y * float(r) / float(rows)
		var major := r % 2 == 0
		imgui_draw_line(Vector2(pos.x, y), Vector2(pos.x + size.x, y), Color(GRID.r, GRID.g, GRID.b, 0.5 if major else 0.2), 1.0)
	implot_pop_plot_clip_rect()


# Resplandor + estela de fosforo + relleno suave, en tramos (ECG_SEGMENTS) para que el
# desvanecido de _ecg_monitor() se note sin un draw call por punto. Recorta al rect del
# plot (implot_push/pop_plot_clip_rect) porque imgui_draw_* no auto-clipea como los
# implot_plot_*. Todo detras de ImGuiOdiseaTheme.supported() -- no llega a nightly1/v0.5.3.
func _ecg_draw_diegetic(xs: PoolRealArray, ys: PoolRealArray, alphas: PoolRealArray, accent: Color, n: int) -> void:
	# Relleno suave bajo la curva: un solo shaded plano y bajo, no por tramo (mas simple,
	# se nota igual bajo el trazo que si va encima).
	implot_set_next_fill_style(accent, 0.10)
	implot_plot_shaded("##ecg_fill", xs, ys, -0.5)

	implot_push_plot_clip_rect()
	var step := max(1, n / ECG_SEGMENTS)
	var i := 0
	while i < n - 1:
		var j := min(i + step, n - 1)
		var a := alphas[(i + j) / 2]
		if a > 0.01:
			var pts := PoolVector2Array()
			for k in range(i, j + 1):
				pts.push_back(implot_plot_to_pixels(xs[k], ys[k]))
			# Resplandor: mismo trazo 2 veces, mas grueso y mas transparente que la linea
			# principal debajo (HoloScreen.shader = luma->opacidad: oscuro/transparente es
			# el vidrio, blanco satura -- por eso el glow baja alfa, no sube brillo).
			imgui_draw_polyline(pts, Color(accent.r, accent.g, accent.b, accent.a * a * 0.12), 7.0)
			imgui_draw_polyline(pts, Color(accent.r, accent.g, accent.b, accent.a * a * 0.28), 4.0)
			imgui_draw_polyline(pts, Color(accent.r, accent.g, accent.b, accent.a * a), 2.0)
		i = j
	implot_pop_plot_clip_rect()


# Cabeza brillante del barrido: circulo relleno + halo (2 circulos, el grande translucido)
# en la posicion actual de la cabeza. `pulse` (0..1, ver _beat_pulse) tambien hace pulsar
# esta cabeza en el pico R, ademas del corazon/BPM.
func _ecg_draw_head(head_frac: float, head_val: float, accent: Color, pulse: float) -> void:
	var center := implot_plot_to_pixels(head_frac, head_val)
	var r := 3.5 + pulse * 2.0
	implot_push_plot_clip_rect()
	imgui_draw_circle_filled(center, r * 2.6, Color(accent.r, accent.g, accent.b, 0.18 + pulse * 0.12))
	imgui_draw_circle_filled(center, r, Color(accent.r, accent.g, accent.b, 0.9))
	implot_pop_plot_clip_rect()


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
