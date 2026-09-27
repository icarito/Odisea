extends ImGuiCanvas

# DebugHudWidgetImGui.gd - Widget compacto diegetico de "Rendimiento" (system:performance).
# Dibuja el mismo widget_snapshot() que DebugHudWidget._render() ya guarda en
# widget.snapshot(): FPS, frame ms, draw calls y una mini curva de FPS (ImPlot, sin
# decoraciones, autofit), con el marco/tipografia/paleta de los demas widgets de SuitOS
# en vez del Label suelto de antes.

const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")
const HudViewMount = preload("res://core_v2/ui/hud/HudViewMount.gd")
const ImGuiOdiseaFonts = preload("res://core_v2/ui/hud/ImGuiOdiseaFonts.gd")
const ImGuiOdiseaTheme = preload("res://core_v2/ui/hud/ImGuiOdiseaTheme.gd")

const PANEL_SIZE := Vector2(210.0, 72.0)
# El panel tiene 186x64 de contenido: dejarlo en (0,0) lo hacia verse pegado al borde
# aunque el Control padre ya estuviera centrado dentro de su slot.
const CONTENT_OFFSET := Vector2(12.0, 4.0)

var widget: Node = null # DebugHudWidget.gd

var title_font := 0
var body_font := 0


func _ready() -> void:
	set_update_hz(10.0)
	set_input_hz(30.0)
	# Igual criterio que FlashlightWidgetImGui: titulo ("SISTEMAS") en Sixtyfour, cuerpo
	# a ProggyClean/Silkscreen -- ver ImGuiOdiseaFonts.gd.
	var fonts := ImGuiOdiseaFonts.setup(self, 14.0, -1.0, 14.0)
	title_font = fonts.title
	body_font = fonts.body
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


func _on_imgui_frame() -> void:
	if not is_instance_valid(widget):
		return
	var snapshot: Dictionary = widget.snapshot()
	var offline := String(snapshot.get("source", "online")) == "offline"
	var fps := float(snapshot.get("fps", 0.0))
	var frame_ms := float(snapshot.get("frame_ms", 0.0))
	var draw_calls := float(snapshot.get("draw_calls", 0.0))
	var fps_series: Array = snapshot.get("fps_series", [])
	var accent := OdiseaOSTheme.STATE_OFFLINE if offline else (OdiseaOSTheme.STATE_ALARM if fps < 30.0 else OdiseaOSTheme.STATE_ACTIVE)

	var panel_bg: Color = OdiseaOSTheme.SURFACE_PANEL
	if is_instance_valid(widget) and (widget as Control).rect_scale != Vector2.ONE:
		panel_bg.a = min(panel_bg.a, HudViewMount.widget_alpha())

	set_next_window_pos(Vector2.ZERO, true)
	set_next_window_size(PANEL_SIZE, true)
	push_style_var_vec2(STYLE_VAR_WINDOW_PADDING, Vector2(6, 6))
	push_style_var_vec2(STYLE_VAR_ITEM_SPACING, Vector2(6, 2))
	ImGuiOdiseaTheme.push_window(self, accent)
	push_style_color(COL_WINDOW_BG, panel_bg)  # alfa variable (B3a widget_alpha) pisa el WINDOW_BG del tema

	var flags := WINDOW_NO_DECORATION | WINDOW_NO_MOVE | WINDOW_NO_SAVED_SETTINGS | WINDOW_NO_BRING_TO_FRONT_ON_FOCUS
	if begin("##debughud_widget", flags):
		set_cursor_pos(CONTENT_OFFSET)
		push_font(title_font)
		text_colored(accent, "SISTEMAS")
		pop_font()

		if offline:
			set_cursor_pos(CONTENT_OFFSET + Vector2(0, 18))
			text_colored(OdiseaOSTheme.STATE_OFFLINE, tr("OFFLINE"))
		else:
			set_cursor_pos(CONTENT_OFFSET + Vector2(0, 18))
			text_colored(OdiseaOSTheme.INK, "%.0f FPS  %.1f ms" % [fps, frame_ms])
			set_cursor_pos(CONTENT_OFFSET + Vector2(0, 34))
			text_colored(OdiseaOSTheme.SUIT_DIM, "DRAWS %.0f" % draw_calls)

			set_cursor_pos(CONTENT_OFFSET + Vector2(112, 4))
			if not fps_series.empty():
				var xs := PoolRealArray()
				var ys := PoolRealArray()
				xs.resize(fps_series.size())
				ys.resize(fps_series.size())
				var y_min: float = float(fps_series[0])
				var y_max: float = y_min
				for i in range(fps_series.size()):
					var v := float(fps_series[i])
					xs[i] = float(i)
					ys[i] = v
					y_min = min(y_min, v)
					y_max = max(y_max, v)
				if y_max - y_min < 0.001:
					y_max = y_min + 1.0
				var pad: float = (y_max - y_min) * 0.15
				var plot_flags := IMPLOT_FLAGS_NO_TITLE | IMPLOT_FLAGS_NO_LEGEND | IMPLOT_FLAGS_NO_MOUSE_TEXT | IMPLOT_FLAGS_NO_MENUS | IMPLOT_FLAGS_NO_BOX_SELECT | IMPLOT_FLAGS_NO_INPUTS
				var axis_flags := IMPLOT_AXIS_NO_DECORATIONS | IMPLOT_AXIS_AUTOFIT
				ImGuiOdiseaTheme.push_plot(self, accent)
				if implot_begin_plot("##fps_mini", Vector2(74, 46), plot_flags):
					implot_setup_axes("", "", axis_flags, axis_flags)
					# El AUTOFIT solo no alcanzo a ajustar el rango (medido: caja vacia sin
					# curva); limites explicitos con margen, igual que el ECG de CryoPodImGui.
					implot_setup_axis_limits(IMPLOT_AXIS_X1, 0.0, max(float(fps_series.size() - 1), 1.0), true)
					implot_setup_axis_limits(IMPLOT_AXIS_Y1, y_min - pad, y_max + pad, true)
					implot_plot_line("fps", xs, ys)
					implot_end_plot()
				ImGuiOdiseaTheme.pop_plot(self)
	end()

	pop_style_color(1)
	ImGuiOdiseaTheme.pop_window(self)
	pop_style_var(2)


# Tamano de diseno del panel (ventana ImGui anclada al origen del canvas), igual
# criterio que FlashlightWidgetImGui.panel_size(): el Control del widget baja a esto
# cuando el canvas reemplaza a los Controls y el marco del slot abraza al panel.
func panel_size() -> Vector2:
	return PANEL_SIZE
