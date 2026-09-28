extends ImGuiCanvas

# ProtocolScreenImGui.gd - Pantalla de casco del Protocolo de arranque (FD-319 T4), ImGui.
# Misma division que FlashlightScreenImGui: screen_ui (ProtocolScreenView.gd) es la unica
# fuente del snapshot; esta hoja solo lo LEE cada imgui_frame y dibuja. Sin botones: la
# pantalla es de lectura (marcar pasos es tarea del grafo de T5), asi que no pide cursor
# por shader. El checklist es el mismo dato del widget de slot: el color de cada fila es
# estado (OdiseaOSTheme.state) o identidad del sistema (ProtocolModel.identity_color);
# el texto es el verbo, instruccion siempre presente (FD-319 regla dura 2).

const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")
const ProtocolModel = preload("res://core_v2/ui/hud/ProtocolModel.gd")
const ImGuiOdiseaFonts = preload("res://core_v2/ui/hud/ImGuiOdiseaFonts.gd")
const ImGuiOdiseaTheme = preload("res://core_v2/ui/hud/ImGuiOdiseaTheme.gd")

const DESIGN := Vector2(520.0, 420.0)
const ROW_STEP := 46.0
const FIRST_ROW := Vector2(24.0, 64.0)
const DONE_DIM := 0.55

var screen_ui: Node = null

var title_font := -1
var body_font := -1
var _white_tex: ImageTexture = null


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_update_hz(10.0)
	set_input_hz(30.0)
	# Titulo en Sixtyfour (rol titulo); cuerpo a ProggyClean/Silkscreen -- ver
	# ImGuiOdiseaFonts.gd. Igual escala que la Linterna (20/20).
	var fonts := ImGuiOdiseaFonts.setup(self, 20.0, -1.0, 20.0)
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


# Pantalla de solo lectura, como la de Rendimiento: sin cursor por shader.
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
	var data: Dictionary = screen_ui.snapshot
	var offline := String(data.get("source", "online")) == "offline"
	var steps: Array = data.get("steps", [])

	var has_fail := false
	var all_done := not steps.empty()
	for step in steps:
		var state := String(step.get("state", ""))
		has_fail = has_fail or state == ProtocolModel.STATE_FAIL
		all_done = all_done and state == ProtocolModel.STATE_DONE

	var header_dot := OdiseaOSTheme.STATE_ACTIVE
	if offline or steps.empty():
		header_dot = OdiseaOSTheme.STATE_OFFLINE
	elif has_fail:
		header_dot = OdiseaOSTheme.STATE_ALARM
	elif all_done:
		header_dot = OdiseaOSTheme.STATE_NOMINAL

	# El acento del tema (PLOT_LINES/bordes vivos) sigue la misma verdad que el punto:
	# alarma si hay FALLO, cian del traje en cualquier otro caso.
	var accent := OdiseaOSTheme.STATE_ALARM if has_fail else OdiseaOSTheme.SUIT_ACCENT

	var flags := WINDOW_NO_DECORATION | WINDOW_NO_MOVE | WINDOW_NO_SAVED_SETTINGS | WINDOW_NO_BRING_TO_FRONT_ON_FOCUS
	set_next_window_pos(Vector2.ZERO, true)
	set_next_window_size(DESIGN, true)
	push_style_var_vec2(STYLE_VAR_WINDOW_PADDING, Vector2.ZERO)
	ImGuiOdiseaTheme.push_window(self, accent)

	if begin("##protocol_screen", flags):
		set_cursor_pos(Vector2(18, 16))
		image(_white_tex, Vector2(12, 12), header_dot)
		same_line(38.0)
		if title_font >= 0:
			push_font(title_font)
		text_colored(OdiseaOSTheme.SUIT_ACCENT, "PROTOCOLO DE ARRANQUE")
		if title_font >= 0:
			pop_font()
		set_cursor_pos(Vector2(18, 40))
		separator()

		if offline or steps.empty():
			set_cursor_pos(FIRST_ROW)
			text_colored(OdiseaOSTheme.STATE_OFFLINE, "SIN LECTURA")
		else:
			for i in range(steps.size()):
				_draw_row(steps[i], Vector2(FIRST_ROW.x, FIRST_ROW.y + ROW_STEP * float(i)))

		set_cursor_pos(Vector2(22, DESIGN.y - 26.0))
		if body_font >= 0:
			push_font(body_font)
		text_colored(OdiseaOSTheme.SUIT_DIM, "FD-319 - TRAJE")
		if body_font >= 0:
			pop_font()
	end()

	ImGuiOdiseaTheme.pop_window(self)
	pop_style_var(1)


func _draw_row(step: Dictionary, pos: Vector2) -> void:
	var state := String(step.get("state", ProtocolModel.STATE_PENDING))
	var verb := String(step.get("verb", ""))
	var accent := String(step.get("accent", ""))

	var dot_color := OdiseaOSTheme.state(ProtocolModel.theme_state_of(state))
	var text_color := dot_color
	if state == ProtocolModel.STATE_ACTIVE:
		# Identidad del sistema (eje 1): el color del sistema nunca cambia por estado.
		text_color = ProtocolModel.identity_color(accent)
	elif state == ProtocolModel.STATE_DONE:
		var dimmed: Color = OdiseaOSTheme.STATE_NOMINAL
		dimmed.a *= DONE_DIM
		text_color = dimmed

	set_cursor_pos(pos)
	image(_white_tex, Vector2(12, 12), dot_color)
	same_line(48.0)
	if body_font >= 0:
		push_font(body_font)
	text_colored(text_color, ("[OK] %s" % verb) if state == ProtocolModel.STATE_DONE else verb)
	if body_font >= 0:
		pop_font()
