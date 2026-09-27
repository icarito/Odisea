extends ImGuiCanvas

# DebugHudScreenImGui.gd - Pantalla diegetica de "Rendimiento" (system:performance).
#
# Mismo lenguaje visual que la pantalla de casco de la Linterna y la Criopod: marco
# oscuro, Silkscreen, paleta de OdiseaOSTheme, curvas ImPlot con grilla (como el ECG de
# CryoPodImGui). `hud` (DebugHud, el autoload) es la fuente en vivo: series_tail(name, n)
# para las seis curvas y summary() para la fila de valores. No pasa por
# DebugHudScreen.widget_snapshot() -- ese sigue chico (<2 KB/2 Hz) para el telefono, sin
# tocarse; esta pantalla es local, como el overlay F1 (debug_hud_view.gd).

const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")

const DESIGN := Vector2(640.0, 460.0)
const SERIES_LEN := 90 # ~45s a 2 Hz de resampleo (ver DebugMetrics), de sobra para ver tendencia

# label visible, clave de la serie en DebugMetrics, color de la curva.
const CURVES := [
	["FPS", "TIME_FPS", "STATE_ACTIVE"],
	["FRAME MS", "TIME_PROCESS", "SUIT_ACCENT"],
	["DRAW CALLS", "RENDER_DRAW_CALLS_IN_FRAME", "STATE_CAUTION"],
	["VÉRTICES", "RENDER_VERTICES_IN_FRAME", "SUIT_DIM"],
	["MEMORIA", "MEMORY_STATIC", "STATE_CAUTION"],
	["NODOS", "OBJECT_NODE_COUNT", "SUIT_DIM"],
]

var hud = null

var body_font := -1
var small_font := -1


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_update_hz(4.0) # metricas de sobra a menos de la mitad del framerate: no es un juego de reflejos
	set_input_hz(15.0)
	var ttf := "res://assets/fonts/Silkscreen-Regular.ttf"
	body_font = add_font(ttf, 18.0)
	small_font = add_font(ttf, 14.0)
	if body_font >= 0:
		set_default_font(body_font)
	connect("imgui_frame", self, "_on_imgui_frame")
	connect("redrawn", self, "_on_redrawn")
	request_redraw()


func _on_redrawn() -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("request_redraw"):
			node.request_redraw()
			return
		node = node.get_parent()


func _color(name: String) -> Color:
	match name:
		"STATE_ACTIVE": return OdiseaOSTheme.STATE_ACTIVE
		"STATE_CAUTION": return OdiseaOSTheme.STATE_CAUTION
		"SUIT_ACCENT": return OdiseaOSTheme.SUIT_ACCENT
		"SUIT_DIM": return OdiseaOSTheme.SUIT_DIM
	return OdiseaOSTheme.INK


func _on_imgui_frame() -> void:
	if not is_instance_valid(hud):
		return

	var flags := WINDOW_NO_DECORATION | WINDOW_NO_MOVE | WINDOW_NO_SAVED_SETTINGS | WINDOW_NO_BRING_TO_FRONT_ON_FOCUS
	set_next_window_pos(Vector2.ZERO, true)
	set_next_window_size(DESIGN, true)
	push_style_var_vec2(STYLE_VAR_WINDOW_PADDING, Vector2.ZERO)
	push_style_color(COL_WINDOW_BG, OdiseaOSTheme.SURFACE_PANEL)
	push_style_color(COL_TEXT, OdiseaOSTheme.SUIT_ACCENT)
	push_style_color(COL_BORDER, OdiseaOSTheme.SUIT_DIM)
	push_style_color(COL_TABLE_HEADER_BG, Color(0.06, 0.20, 0.26, 1.0))
	push_style_color(COL_TABLE_BORDER_STRONG, OdiseaOSTheme.SUIT_DIM)
	push_style_color(COL_TABLE_ROW_BG, Color(0.03, 0.08, 0.10, 1.0))
	push_style_color(COL_SEPARATOR, OdiseaOSTheme.SUIT_DIM)

	if begin("##performance_screen", flags):
		_header()
		_curve_grid()
		_summary_table()
	end()

	pop_style_color(7)
	pop_style_var(1)


func _header() -> void:
	set_cursor_pos(Vector2(20, 14))
	if body_font >= 0:
		push_font(body_font)
	text_colored(OdiseaOSTheme.SUIT_ACCENT, "DIAGNÓSTICO DE TRAJE")
	if body_font >= 0:
		pop_font()
	set_cursor_pos(Vector2(20, 38))
	text_colored(OdiseaOSTheme.SUIT_DIM, "SISTEMAS")
	set_cursor_pos(Vector2(20, 60))
	separator()


func _curve_grid() -> void:
	var margin := 20.0
	var gutter_x := 16.0
	var gutter_y := 14.0
	var col_w := (DESIGN.x - margin * 2.0 - gutter_x * 2.0) / 3.0
	var row_h := 150.0
	var top := 76.0
	var plot_flags := IMPLOT_FLAGS_NO_TITLE | IMPLOT_FLAGS_NO_LEGEND | IMPLOT_FLAGS_NO_MOUSE_TEXT | IMPLOT_FLAGS_NO_MENUS | IMPLOT_FLAGS_NO_BOX_SELECT | IMPLOT_FLAGS_NO_INPUTS
	var x_flags := IMPLOT_AXIS_AUTOFIT | IMPLOT_AXIS_NO_TICK_LABELS
	var y_flags := IMPLOT_AXIS_AUTOFIT

	for i in range(CURVES.size()):
		var col := i % 3
		var row := int(i / 3)
		var x := margin + col * (col_w + gutter_x)
		var y := top + row * (row_h + gutter_y)
		var entry: Array = CURVES[i]
		var label := String(entry[0])
		var series_name := String(entry[1])
		var accent := _color(String(entry[2]))

		set_cursor_pos(Vector2(x, y))
		if small_font >= 0:
			push_font(small_font)
		text_colored(accent, label)
		if small_font >= 0:
			pop_font()

		set_cursor_pos(Vector2(x, y + 20.0))
		var series: Array = hud.series_tail(series_name, SERIES_LEN) if hud.has_method("series_tail") else []
		if series.empty():
			text_colored(OdiseaOSTheme.STATE_OFFLINE, "--")
			continue
		var xs := PoolRealArray()
		var ys := PoolRealArray()
		xs.resize(series.size())
		ys.resize(series.size())
		var y_min: float = float(series[0])
		var y_max: float = y_min
		for j in range(series.size()):
			var v := float(series[j])
			xs[j] = float(j)
			ys[j] = v
			y_min = min(y_min, v)
			y_max = max(y_max, v)
		# El AUTOFIT de los ejes (ImPlotAxisFlags_AutoFit) no alcanza a ajustar solo con la
		# primera pasada de datos (medido: quedaba en el rango fijo 0..1 por defecto, sin
		# curva visible). Limites explicitos con margen, igual que el ECG de CryoPodImGui.
		if y_max - y_min < 0.001:
			y_max = y_min + 1.0
		var pad: float = (y_max - y_min) * 0.15
		implot_push_style_color(IMPLOT_COL_PLOT_BG, Color(0.03, 0.08, 0.10, 1.0))
		implot_push_style_color(IMPLOT_COL_FRAME_BG, Color(0.03, 0.08, 0.10, 1.0))
		implot_push_style_color(IMPLOT_COL_AXIS_GRID, OdiseaOSTheme.SURFACE_BORDER)
		implot_push_style_color(IMPLOT_COL_AXIS_TEXT, OdiseaOSTheme.SUIT_DIM)
		implot_push_style_color(IMPLOT_COL_LINE, accent)
		if implot_begin_plot("##" + series_name, Vector2(col_w, row_h - 20.0), plot_flags):
			implot_setup_axes("", "", x_flags, y_flags)
			implot_setup_axis_limits(IMPLOT_AXIS_X1, 0.0, max(float(series.size() - 1), 1.0), true)
			implot_setup_axis_limits(IMPLOT_AXIS_Y1, y_min - pad, y_max + pad, true)
			implot_plot_line(series_name, xs, ys)
			implot_end_plot()
		implot_pop_style_color(5)


func _summary_table() -> void:
	var s: Dictionary = hud.summary() if hud.has_method("summary") else {}
	set_cursor_pos(Vector2(20, 404))
	var flags := TABLE_BORDERS | TABLE_ROW_BG
	if begin_table("##performance_summary", 6, flags):
		table_setup_column("FPS")
		table_setup_column("MS")
		table_setup_column("DRAWS")
		table_setup_column("VÉRT")
		table_setup_column("MEM MB")
		table_setup_column("NODOS")
		table_headers_row()
		table_next_row()
		table_next_column()
		text("%.0f" % float(s.get("fps", 0.0)))
		table_next_column()
		text("%.1f" % float(s.get("frame_ms", 0.0)))
		table_next_column()
		text("%.0f" % float(s.get("draw_calls", 0.0)))
		table_next_column()
		text("%.0f" % float(s.get("vertices", 0.0)))
		table_next_column()
		text("%.0f" % float(s.get("memory_mb", 0.0)))
		table_next_column()
		text("%.0f" % float(s.get("nodes", 0.0)))
		end_table()
