extends ImGuiCanvas

# FlashlightWidgetImGui.gd - Port a ImGui del widget compacto de la Linterna
# (FlashlightWidget.gd/.tscn). Dibuja el MISMO contenido desde el mismo
# widget.snapshot() (que FlashlightWidget._render()/_render_offline() ya llenan):
# punto de estado + titulo, barra de bateria ASCII, estado + boton
# ENCENDER/APAGAR/OFFLINE -> misma accion "toggle" (FlashlightWidget.toggle_action()).
#
# El modo "pantalla completa" de la Linterna (HudViewMount._open_widget, sin
# view_scene()) reescala este mismo widget con Control.rect_scale = WIDGET_ZOOM: este
# canvas es hijo (Node2D) de ese Control y hereda esa transformacion, asi que siempre
# dibuja al mismo tamano de diseno 210x80 sin parametro de zoom propio (a diferencia de
# demo_flashlight/imgui_flashlight_widget.gd, pensado para un overlay ImGui plano sin
# arbol de Controls debajo).

const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")
const HudViewMount = preload("res://core_v2/ui/hud/HudViewMount.gd")
const ImGuiOdiseaFonts = preload("res://core_v2/ui/hud/ImGuiOdiseaFonts.gd")

const PANEL_SIZE := Vector2(210.0, 80.0)

var widget: Node = null # FlashlightWidget.gd, fuente de snapshot()/toggle_action()

var title_font := 0
var body_font := 0
var _white_tex: ImageTexture = null


# ASCII: la fuente del tema no trae bloques. Identico a
# FlashlightWidget._format_battery_bar (no se referencia esa func para no acoplar este
# canvas al arbol de Controls del widget, que puede estar escondido).
static func _format_battery_bar(val: float, max_val: float) -> String:
	if max_val <= 0.0:
		return "BAT: [..........]"
	var ratio := clamp(val / max_val, 0.0, 1.0)
	var total_segments := 10
	var filled_segments := int(round(ratio * total_segments))
	var bar := ""
	for i in range(total_segments):
		bar += "|" if i < filled_segments else "."
	return "BAT: [%s]" % bar


func _ready() -> void:
	set_update_hz(10.0)
	set_input_hz(30.0)
	# Titulo ("Linterna") en Sixtyfour, igual escala que el resto del widget compacto;
	# cuerpo (bateria/estado) a ProggyClean/Silkscreen -- ver ImGuiOdiseaFonts.gd.
	var fonts := ImGuiOdiseaFonts.setup(self, 14.0, -1.0, 14.0)
	title_font = fonts.title
	body_font = fonts.body
	set_default_font(body_font)
	connect("imgui_frame", self, "_on_imgui_frame")
	connect("redrawn", self, "_on_redrawn")
	var image := Image.new()
	image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))
	_white_tex = ImageTexture.new()
	_white_tex.create_from_image(image, 0)
	request_redraw()


# Mismo patron que CryoPodImGui._on_redrawn: un UPDATE_ONCE al Viewport que lo contiene.
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
	var on := bool(snapshot.get("on", false))
	var low := bool(snapshot.get("low", false))
	var battery := float(snapshot.get("battery", 100.0))
	var battery_max := float(snapshot.get("battery_max", 100.0))
	var offline := String(snapshot.get("source", "online")) == "offline"
	var title := String(snapshot.get("title", "Linterna"))

	var dot := OdiseaOSTheme.STATE_OFFLINE
	if not offline:
		dot = (OdiseaOSTheme.STATE_ALARM if low else OdiseaOSTheme.STATE_ACTIVE) if on else OdiseaOSTheme.STATE_OFFLINE

	var status := "APAGADA"
	var button_label := "ENCENDER"
	if offline:
		status = "OFFLINE"
		button_label = "OFFLINE"
	elif on:
		status = "BAT. BAJA" if low else "ENCENDIDA"
		button_label = "APAGAR"

	var meter := "BAT: [----------]" if offline else _format_battery_bar(battery, battery_max)
	var meter_color := OdiseaOSTheme.STATE_ALARM if (low and on and not offline) else OdiseaOSTheme.INK

	# B3a (WIDGET_PANEL_ALPHA): en el modo ampliado (rect_scale != 1) el vidrio va a
	# ~0.7, salvo tier LOW (widget_alpha() devuelve 1.0 ahi). El slot normal (rect_scale
	# 1.0) queda opaco, como el widget de Controls.
	var panel_bg: Color = OdiseaOSTheme.SURFACE_PANEL
	if is_instance_valid(widget) and (widget as Control).rect_scale != Vector2.ONE:
		panel_bg.a = min(panel_bg.a, HudViewMount.widget_alpha())

	set_next_window_pos(Vector2.ZERO, true)
	set_next_window_size(PANEL_SIZE, true)
	push_style_color(COL_WINDOW_BG, panel_bg)
	push_style_color(COL_BORDER, OdiseaOSTheme.SURFACE_BORDER)
	push_style_var_vec2(STYLE_VAR_WINDOW_PADDING, Vector2(6, 6))
	push_style_var_vec2(STYLE_VAR_ITEM_SPACING, Vector2(6, 2))

	var flags := WINDOW_NO_DECORATION | WINDOW_NO_MOVE | WINDOW_NO_SAVED_SETTINGS | WINDOW_NO_BRING_TO_FRONT_ON_FOCUS
	if begin("##flashlight_widget", flags):
		set_cursor_pos(Vector2(0, 0))
		image(_white_tex, Vector2(8, 8), dot)
		# same_line() mide el offset desde el INICIO de la linea, no desde el cursor: el
		# punto ocupa x en [0,8], asi que el offset tiene que superar 8 (medido en la
		# pantalla de casco, mismo bug).
		same_line(14.0)
		push_font(title_font)
		text_colored(OdiseaOSTheme.INK, title)
		pop_font()

		set_cursor_pos(Vector2(0, 18))
		text_colored(meter_color, meter)

		set_cursor_pos(Vector2(0, 34))
		text_colored(OdiseaOSTheme.INK if not offline else OdiseaOSTheme.STATE_OFFLINE, status)

		set_cursor_pos(Vector2(112, 32))
		if offline:
			push_style_color(COL_BUTTON, Color(0.1, 0.1, 0.1, 1.0))
			push_style_color(COL_TEXT, OdiseaOSTheme.STATE_OFFLINE)
			button(button_label, Vector2(74, 20))
			pop_style_color(2)
		elif button(button_label, Vector2(74, 20)):
			widget.toggle_action()
	end()

	pop_style_var(2)
	pop_style_color(2)
