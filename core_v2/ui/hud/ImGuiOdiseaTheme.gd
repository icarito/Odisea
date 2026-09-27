class_name ImGuiOdiseaTheme

# ImGuiOdiseaTheme.gd - Tema ImGui unico para las 5 piezas de Odisea (CryoPodImGui,
# Flashlight{Widget,Screen}ImGui, DebugHud{Widget,Screen}ImGui).
#
# Antes cada pantalla mezclaba a mano tokens de OdiseaOSTheme.gd (Control) con colores
# sueltos (ver los push_style_color repetidos en cada archivo). Este helper es el
# equivalente ImGui de OdiseaOSTheme.gd: un solo lugar para los ~30 ImGuiCol_* que la
# plataforma expone.
#
# Paleta: cian monocromo (gist de enemymouse, "el tema que mas se parece al de Odisea"),
# con los alfas del gist tal cual (RGBA 0-1, ImGui 1.91). WindowBg del gist es
# (0,0,0,0.83): aca queda en 1.0 porque HoloScreen.shader ya convierte LUMA en opacidad
# (coverage = luma/ink_level) -- un WindowBg con alfa < 1 point dejaba ver el fondo del
# holograma A TRAVES del panel, doble transparencia (medido en ecg_after.png).
#
# El acento (PLOT_LINES/PLOT_HISTOGRAM) NO es fijo: cada pantalla lo pasa por parametro
# (accent) para que la alarma (OdiseaOSTheme.STATE_ALARM, ambar/rojo) siga
# distinguiendose del cian nominal -- el Manual del Tripulante §6 pide que el color de
# alarma nunca se pierda en el tema base.

const TEXT := Color(0.0, 1.0, 1.0, 1.0)
const TEXT_DISABLED := Color(0.0, 0.40, 0.41, 1.0)
const WINDOW_BG := Color(0.0, 0.0, 0.0, 1.0)          # gist: 0.83 -- ver nota arriba
const CHILD_BG := Color(0.0, 0.0, 0.0, 0.0)
const POPUP_BG := Color(0.0, 0.13, 0.13, 0.90)
const BORDER := Color(0.0, 1.0, 1.0, 0.65)
const BORDER_SHADOW := Color(0.0, 0.0, 0.0, 0.0)
const FRAME_BG := Color(0.44, 0.80, 0.80, 0.18)
const FRAME_BG_HOVERED := Color(0.44, 0.80, 0.80, 0.27)
const FRAME_BG_ACTIVE := Color(0.44, 0.81, 0.86, 0.66)
const TITLE_BG := Color(0.14, 0.18, 0.21, 0.73)
const TITLE_BG_ACTIVE := Color(0.0, 1.0, 1.0, 0.27)
const TITLE_BG_COLLAPSED := Color(0.0, 0.0, 0.0, 0.54)
const MENU_BAR_BG := Color(0.0, 0.0, 0.0, 0.20)
const SCROLLBAR_BG := Color(0.22, 0.29, 0.30, 0.71)
const SCROLLBAR_GRAB := Color(0.0, 1.0, 1.0, 0.44)
const CHECK_MARK := Color(0.0, 1.0, 1.0, 0.68)
const SLIDER_GRAB := Color(0.0, 1.0, 1.0, 0.36)
const BUTTON := Color(0.0, 0.65, 0.65, 0.46)
const BUTTON_HOVERED := Color(0.01, 1.0, 1.0, 0.43)
const BUTTON_ACTIVE := Color(0.0, 1.0, 1.0, 0.62)
const HEADER := Color(0.0, 1.0, 1.0, 0.33)
const HEADER_HOVERED := Color(0.0, 1.0, 1.0, 0.42)
const HEADER_ACTIVE := Color(0.0, 1.0, 1.0, 0.54)
const SEPARATOR := Color(0.0, 0.50, 0.50, 0.33)
const TABLE_HEADER_BG := Color(0.0, 0.35, 0.35, 0.40)
const TABLE_BORDER_STRONG := Color(0.0, 0.60, 0.60, 0.60)
const TABLE_ROW_BG := Color(0.0, 0.0, 0.0, 0.0)
const TEXT_SELECTED_BG := Color(0.0, 1.0, 1.0, 0.22)

# ImPlot (grilla/fondo/eje), misma familia cian que el resto del tema.
const PLOT_BG := Color(0.02, 0.06, 0.08, 1.0)
const PLOT_AXIS_GRID := Color(0.0, 0.50, 0.50, 0.35)
const PLOT_AXIS_TEXT := TEXT_DISABLED

# Cuantos push_style_color/push_style_var hace push_window(), para el pop simetrico.
const WINDOW_COLOR_COUNT := 29
const WINDOW_VAR_COUNT := 2  # WINDOW_ROUNDING, FRAME_ROUNDING (gist: ambos 3px)

# `imgui_draw_*`, `implot_*` con IMPLOT_STYLE_VAR_* y `add_font_default` llegan juntos en
# v0.5.4-nightly2 (misma release): un solo has_method alcanza para gatear todo el tema
# nuevo contra v0.5.4-nightly1/v0.5.3.
static func supported(canvas) -> bool:
	return canvas.has_method("implot_set_next_line_style")


# Ventana ImGui completa (COL_* + rounding). `accent` es PLOT_LINES/PLOT_HISTOGRAM: pasar
# OdiseaOSTheme.STATE_ALARM en alarma, el acento nominal si no.
static func push_window(canvas, accent: Color) -> void:
	canvas.push_style_color(canvas.COL_TEXT, TEXT)
	canvas.push_style_color(canvas.COL_TEXT_DISABLED, TEXT_DISABLED)
	canvas.push_style_color(canvas.COL_WINDOW_BG, WINDOW_BG)
	canvas.push_style_color(canvas.COL_CHILD_BG, CHILD_BG)
	canvas.push_style_color(canvas.COL_POPUP_BG, POPUP_BG)
	canvas.push_style_color(canvas.COL_BORDER, BORDER)
	canvas.push_style_color(canvas.COL_BORDER_SHADOW, BORDER_SHADOW)
	canvas.push_style_color(canvas.COL_FRAME_BG, FRAME_BG)
	canvas.push_style_color(canvas.COL_FRAME_BG_HOVERED, FRAME_BG_HOVERED)
	canvas.push_style_color(canvas.COL_FRAME_BG_ACTIVE, FRAME_BG_ACTIVE)
	canvas.push_style_color(canvas.COL_TITLE_BG, TITLE_BG)
	canvas.push_style_color(canvas.COL_TITLE_BG_ACTIVE, TITLE_BG_ACTIVE)
	canvas.push_style_color(canvas.COL_TITLE_BG_COLLAPSED, TITLE_BG_COLLAPSED)
	canvas.push_style_color(canvas.COL_MENU_BAR_BG, MENU_BAR_BG)
	canvas.push_style_color(canvas.COL_SCROLLBAR_BG, SCROLLBAR_BG)
	canvas.push_style_color(canvas.COL_SCROLLBAR_GRAB, SCROLLBAR_GRAB)
	canvas.push_style_color(canvas.COL_CHECK_MARK, CHECK_MARK)
	canvas.push_style_color(canvas.COL_SLIDER_GRAB, SLIDER_GRAB)
	canvas.push_style_color(canvas.COL_BUTTON, BUTTON)
	canvas.push_style_color(canvas.COL_BUTTON_HOVERED, BUTTON_HOVERED)
	canvas.push_style_color(canvas.COL_BUTTON_ACTIVE, BUTTON_ACTIVE)
	canvas.push_style_color(canvas.COL_HEADER, HEADER)
	canvas.push_style_color(canvas.COL_HEADER_HOVERED, HEADER_HOVERED)
	canvas.push_style_color(canvas.COL_HEADER_ACTIVE, HEADER_ACTIVE)
	canvas.push_style_color(canvas.COL_SEPARATOR, SEPARATOR)
	canvas.push_style_color(canvas.COL_PLOT_LINES, accent)
	canvas.push_style_color(canvas.COL_PLOT_HISTOGRAM, accent)
	canvas.push_style_color(canvas.COL_TABLE_HEADER_BG, TABLE_HEADER_BG)
	canvas.push_style_color(canvas.COL_TABLE_BORDER_STRONG, TABLE_BORDER_STRONG)
	canvas.push_style_color(canvas.COL_TABLE_ROW_BG, TABLE_ROW_BG)
	canvas.push_style_color(canvas.COL_TEXT_SELECTED_BG, TEXT_SELECTED_BG)
	canvas.push_style_var_float(canvas.STYLE_VAR_WINDOW_ROUNDING, 3.0)
	canvas.push_style_var_float(canvas.STYLE_VAR_FRAME_ROUNDING, 3.0)


static func pop_window(canvas) -> void:
	canvas.pop_style_color(WINDOW_COLOR_COUNT)
	canvas.pop_style_var(WINDOW_VAR_COUNT)


# ImPlot: fondo/grilla/eje del tema + linea de acento (misma logica que push_window).
static func push_plot(canvas, accent: Color) -> void:
	canvas.implot_push_style_color(canvas.IMPLOT_COL_PLOT_BG, PLOT_BG)
	canvas.implot_push_style_color(canvas.IMPLOT_COL_FRAME_BG, PLOT_BG)
	canvas.implot_push_style_color(canvas.IMPLOT_COL_AXIS_GRID, PLOT_AXIS_GRID)
	canvas.implot_push_style_color(canvas.IMPLOT_COL_AXIS_TEXT, PLOT_AXIS_TEXT)
	canvas.implot_push_style_color(canvas.IMPLOT_COL_LINE, accent)


static func pop_plot(canvas) -> void:
	canvas.implot_pop_style_color(5)
