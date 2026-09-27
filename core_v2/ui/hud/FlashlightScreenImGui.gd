extends ImGuiCanvas

# FlashlightScreenImGui.gd - Pantalla de casco de la Linterna (FD-298), ImGui.
# Port de demo_flashlight/flashlight_screen.gd (gdtk, SPEC-flashlight.md, validado), con
# tres correcciones medidas en esa demo (ver "Cambios para Odisea" del spec):
#
#   1. "99% (99/100)" se superponia con la barra: ahora van en su propia fila, arriba de
#      la barra, con una fila libre entre medio.
#   2. El punto de estado tapaba la "L" de "LINTERNA": same_line(14) en vez de 8.
#   3. "·" no existe en Silkscreen a este tamano y salia "?": separador "-" en su lugar.
#
# screen_ui (FlashlightScreenView.gd) es la unica fuente de snapshot()/toggle(); esta
# hoja solo LEE ese snapshot cada imgui_frame y dispara la misma accion "toggle".
# Paleta de OdiseaOSTheme (pantalla del traje, no la CYAN/DIM de la Criopod, que es de a
# bordo): FlashlightScreen.view_hud_config() ademas baja el contrast_boost del vidrio a
# 1.0 (el default alto de la Criopod, 8.0, saturaba el rojo de STATE_ALARM aca).

const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")

const DESIGN := Vector2(480.0, 300.0)
const BUTTON_POS := Vector2(22.0, 220.0)
const BUTTON_SIZE := Vector2(220.0, 46.0)

var screen_ui: Node = null

var body_font := -1
var big_font := -1
var mid_font := -1
var _white_tex: ImageTexture = null


func _ready() -> void:
	call_deferred("_announce_shader_cursor")
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_update_hz(10.0)
	set_input_hz(30.0)
	var ttf := "res://assets/fonts/Silkscreen-Regular.ttf"
	body_font = add_font(ttf, 20.0)
	big_font = add_font(ttf, 36.0)
	mid_font = add_font(ttf, 26.0)
	if body_font >= 0:
		set_default_font(body_font)
	if big_font < 0:
		big_font = body_font
	if mid_font < 0:
		mid_font = body_font
	connect("imgui_frame", self, "_on_imgui_frame")
	connect("redrawn", self, "_on_redrawn")
	var image := Image.new()
	image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))
	_white_tex = ImageTexture.new()
	_white_tex.create_from_image(image, 0)
	request_redraw()


# Igual que CryoPodImGui: esta pantalla es interactiva (boton ENCENDER/APAGAR), asi que
# pide el cursor por shader en vez de dejar el HoloTerminal forzando UPDATE_ALWAYS.
func uses_shader_cursor() -> bool:
	return true


func _announce_shader_cursor() -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("enable_shader_cursor"):
			node.enable_shader_cursor()
			return
		node = node.get_parent()


func _on_redrawn() -> void:
	var node: Node = get_parent()
	while node != null:
		if node.has_method("request_redraw"):
			node.request_redraw()
			return
		node = node.get_parent()


func _on_imgui_frame() -> void:
	if not is_instance_valid(screen_ui):
		return
	var snapshot: Dictionary = screen_ui.snapshot
	var on := bool(snapshot.get("on", false))
	var low := bool(snapshot.get("low", false))
	var battery := float(snapshot.get("battery", 100.0))
	var battery_max := float(snapshot.get("battery_max", 100.0))
	var offline := String(snapshot.get("source", "online")) == "offline"

	var ratio := 0.0
	if battery_max > 0.0:
		ratio = clamp(battery / battery_max, 0.0, 1.0)

	var dot := OdiseaOSTheme.STATE_OFFLINE
	var state_text := "APAGADA"
	var state_color := OdiseaOSTheme.STATE_OFFLINE
	var button_label := "ENCENDER"
	if offline:
		state_text = "OFFLINE"
		button_label = "OFFLINE"
	elif on:
		dot = OdiseaOSTheme.STATE_ALARM if low else OdiseaOSTheme.STATE_ACTIVE
		state_text = "BAT. BAJA" if low else "ENCENDIDA"
		state_color = OdiseaOSTheme.STATE_ALARM if low else OdiseaOSTheme.STATE_ACTIVE
		button_label = "APAGAR"

	var flags := WINDOW_NO_DECORATION | WINDOW_NO_MOVE | WINDOW_NO_SAVED_SETTINGS | WINDOW_NO_BRING_TO_FRONT_ON_FOCUS
	set_next_window_pos(Vector2.ZERO, true)
	set_next_window_size(DESIGN, true)
	push_style_var_vec2(STYLE_VAR_WINDOW_PADDING, Vector2.ZERO)
	push_style_color(COL_WINDOW_BG, OdiseaOSTheme.SURFACE_PANEL)
	push_style_color(COL_TEXT, OdiseaOSTheme.SUIT_ACCENT)
	push_style_color(COL_BORDER, OdiseaOSTheme.SUIT_DIM)
	push_style_color(COL_BUTTON, Color(0.06, 0.20, 0.26, 1.0))
	push_style_color(COL_BUTTON_HOVERED, Color(0.10, 0.42, 0.52, 1.0))
	push_style_color(COL_BUTTON_ACTIVE, Color(0.16, 0.56, 0.66, 1.0))
	push_style_color(COL_PLOT_HISTOGRAM, state_color)
	push_style_color(COL_SEPARATOR, OdiseaOSTheme.SUIT_DIM)

	if begin("##flashlight_screen", flags):
		# Encabezado: punto de estado + titulo. same_line() mide el offset desde el
		# INICIO de la linea (x local de la ventana), no desde el cursor: con 8 o 14 el
		# offset caia DENTRO del punto (que ocupa x en [18,30]) y tapaba la "L" de
		# LINTERNA (medido). 38 deja el punto respirar antes del texto. "-" en vez de
		# "·": Silkscreen no trae ese glifo a este tamano y salia "?" (medido).
		set_cursor_pos(Vector2(18, 16))
		image(_white_tex, Vector2(12, 12), dot)
		same_line(38.0)
		if body_font >= 0:
			push_font(body_font)
		text_colored(OdiseaOSTheme.SUIT_ACCENT, "LINTERNA - CASCO")
		if body_font >= 0:
			pop_font()
		set_cursor_pos(Vector2(18, 40))
		separator()

		# Indicador grande ENCENDIDA / APAGADA / BAT. BAJA / OFFLINE.
		set_cursor_pos(Vector2(22, 56))
		if big_font >= 0:
			push_font(big_font)
		text_colored(state_color, state_text)
		if big_font >= 0:
			pop_font()

		# Medidor de bateria: etiqueta, numero + fraccion en su propia fila, y la barra
		# en la fila de abajo (antes el numero y la barra se superponian, medido).
		set_cursor_pos(Vector2(22, 116))
		if body_font >= 0:
			push_font(body_font)
		text_colored(OdiseaOSTheme.SUIT_ACCENT, "BATERÍA")
		if body_font >= 0:
			pop_font()

		var meter_color := OdiseaOSTheme.STATE_ALARM if (low and on and not offline) else OdiseaOSTheme.INK
		set_cursor_pos(Vector2(22, 140))
		if mid_font >= 0:
			push_font(mid_font)
		text_colored(meter_color, "--" if offline else "%d%%" % int(round(ratio * 100.0)))
		if mid_font >= 0:
			pop_font()
		set_cursor_pos(Vector2(170, 148))
		if body_font >= 0:
			push_font(body_font)
		text_colored(meter_color, "(--/--)" if offline else "(%.0f/%.0f)" % [battery, battery_max])
		if body_font >= 0:
			pop_font()

		set_cursor_pos(Vector2(22, 180))
		progress_bar(0.0 if offline else ratio, Vector2(436, 24), "")

		# Boton grande ENCENDER / APAGAR (deshabilitado si OFFLINE).
		set_cursor_pos(BUTTON_POS)
		if offline:
			push_style_color(COL_BUTTON, Color(0.07, 0.07, 0.07, 1.0))
			push_style_color(COL_TEXT, OdiseaOSTheme.STATE_OFFLINE)
			button(button_label, BUTTON_SIZE)
			pop_style_color(2)
		else:
			if body_font >= 0:
				push_font(body_font)
			if button(button_label, BUTTON_SIZE):
				screen_ui.toggle()
			if body_font >= 0:
				pop_font()

		set_cursor_pos(Vector2(22, 278))
		if body_font >= 0:
			push_font(body_font)
		text_colored(OdiseaOSTheme.SUIT_DIM, "FD-298 - VISOR DE CASCO")
		if body_font >= 0:
			pop_font()
	end()

	pop_style_color(8)
	pop_style_var(1)
