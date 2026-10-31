extends ImGuiCanvas

# SuitScreenImGui.gd - Pantalla de casco de "Traje" (OdiseaOS), ImGui.
#
# Misma division que ProtocolScreenImGui: screen_ui (SuitScreenView.gd) es la unica
# fuente del snapshot; esta hoja solo lo LEE cada imgui_frame y dibuja. Pantalla de
# lectura (sin botones), asi que no pide cursor por shader.
#
# Tres secciones, un solo dato (SuitModel.snapshot()):
#   ESTADO         -> como esta el traje (integridad, oxigeno, temperatura, energia, enlace)
#   COMUNICACIONES -> log de mensajes (Odisea IA, Cargol); sin leer en cian
#   OBJETIVOS      -> la lista de tareas; el activo lleva el cian del traje

const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")
const SuitModel = preload("res://core_v2/ui/hud/SuitModel.gd")
const ImGuiOdiseaFonts = preload("res://core_v2/ui/hud/ImGuiOdiseaFonts.gd")
const ImGuiOdiseaTheme = preload("res://core_v2/ui/hud/ImGuiOdiseaTheme.gd")
# FD-316 (tarea NN): en LOW el input no rearma el frame de ImGui (ver LowUiOpt.imgui_input_hz).
const LowUiOptScript = preload("res://core_v2/systems/LowUiOpt.gd")

const DESIGN := Vector2(560.0, 480.0)
const SECTION_X := 18.0
const ROW_X := 24.0
const VALUE_X := 210.0
const STATE_Y := 78.0
const STATE_STEP := 18.0
const COMMS_Y := 212.0
const COMMS_STEP := 22.0
const OBJ_Y := 340.0
const OBJ_STEP := 24.0

var screen_ui: Node = null

var title_font := -1
var body_font := -1
var _white_tex: ImageTexture = null


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	set_update_hz(10.0)
	set_input_hz(LowUiOptScript.imgui_input_hz())
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

	var state: Dictionary = data.get("state", {})
	var status := String(state.get("status", SuitModel.STATUS_OFFLINE))
	var has_alarm: bool = not offline and status == SuitModel.STATUS_ALARM

	var header_dot := OdiseaOSTheme.STATE_OFFLINE
	if not offline:
		header_dot = OdiseaOSTheme.state(status)
	var accent := OdiseaOSTheme.STATE_ALARM if has_alarm else OdiseaOSTheme.SUIT_ACCENT

	var flags := WINDOW_NO_DECORATION | WINDOW_NO_MOVE | WINDOW_NO_SAVED_SETTINGS | WINDOW_NO_BRING_TO_FRONT_ON_FOCUS
	set_next_window_pos(Vector2.ZERO, true)
	set_next_window_size(DESIGN, true)
	push_style_var_vec2(STYLE_VAR_WINDOW_PADDING, Vector2.ZERO)
	ImGuiOdiseaTheme.push_window(self, accent)

	if begin("##suit_screen", flags):
		set_cursor_pos(Vector2(SECTION_X, 16))
		image(_white_tex, Vector2(12, 12), header_dot)
		same_line(38.0)
		if title_font >= 0:
			push_font(title_font)
		text_colored(OdiseaOSTheme.SUIT_ACCENT, "TRAJE")
		if title_font >= 0:
			pop_font()

		_draw_section("ESTADO", 56.0)
		if offline:
			_draw_line(ROW_X, STATE_Y, OdiseaOSTheme.STATE_OFFLINE, "SIN LECTURA")
		else:
			_draw_state(state)

		_draw_section("COMUNICACIONES", 188.0)
		if offline:
			_draw_line(ROW_X, COMMS_Y, OdiseaOSTheme.STATE_OFFLINE, "SIN LECTURA")
		else:
			_draw_comms(data)

		_draw_section("OBJETIVOS", 316.0)
		if offline:
			_draw_line(ROW_X, OBJ_Y, OdiseaOSTheme.STATE_OFFLINE, "SIN LECTURA")
		else:
			_draw_objectives(data)

		set_cursor_pos(Vector2(SECTION_X + 4.0, DESIGN.y - 26.0))
		if body_font >= 0:
			push_font(body_font)
		text_colored(OdiseaOSTheme.SUIT_DIM, "ODISEAOS - TRAJE")
		if body_font >= 0:
			pop_font()
	end()

	ImGuiOdiseaTheme.pop_window(self)
	pop_style_var(1)


# --- secciones --------------------------------------------------------------------

func _draw_section(title: String, y: float) -> void:
	set_cursor_pos(Vector2(SECTION_X, y))
	if body_font >= 0:
		push_font(body_font)
	text_colored(OdiseaOSTheme.SUIT_ACCENT, title)
	set_cursor_pos(Vector2(SECTION_X, y + 20.0))
	separator()
	if body_font >= 0:
		pop_font()


func _draw_state(state: Dictionary) -> void:
	var rows := [
		["INTEGRIDAD", "%d%%" % int(state.get("integrity", 0))],
		["OXIGENO", "%d%%" % int(state.get("oxygen", 0))],
		["TEMPERATURA", "%d C" % int(state.get("temperature", 0))],
		["ENERGIA", "%d%%" % int(state.get("power", 0))],
		["ENLACE", "%d%%" % int(state.get("link", 0))],
	]
	for i in range(rows.size()):
		var y := STATE_Y + STATE_STEP * float(i)
		_value_row(y, String(rows[i][0]), String(rows[i][1]), OdiseaOSTheme.INK)
	if bool(state.get("breach", false)):
		_draw_line(ROW_X, STATE_Y + STATE_STEP * float(rows.size()), OdiseaOSTheme.STATE_ALARM,
			"FALLA DE INTEGRIDAD: TRAJE DESPRESURIZADO")


func _draw_comms(data: Dictionary) -> void:
	var comms: Array = data.get("comms", [])
	if comms.empty():
		_draw_line(ROW_X, COMMS_Y, OdiseaOSTheme.STATE_OFFLINE, "SIN MENSAJES")
		return
	# Los ultimos cuatro: es un vistazo, no el log completo.
	var first: int = int(max(0, comms.size() - 4))
	for i in range(first, comms.size()):
		var entry: Dictionary = comms[i]
		var unread := bool(entry.get("unread", false))
		var color := OdiseaOSTheme.SUIT_ACCENT if unread else OdiseaOSTheme.SUIT_DIM
		var text := "%s> %s" % [String(entry.get("from", "")), _clip(String(entry.get("text", "")), 62)]
		_draw_line(ROW_X, COMMS_Y + COMMS_STEP * float(i - first), color, text)


func _draw_objectives(data: Dictionary) -> void:
	var objectives: Array = data.get("objectives", [])
	if objectives.empty():
		_draw_line(ROW_X, OBJ_Y, OdiseaOSTheme.STATE_OFFLINE, "SIN OBJETIVOS")
		return
	var first: int = int(max(0, objectives.size() - 4))
	for i in range(first, objectives.size()):
		var obj: Dictionary = objectives[i]
		var state := String(obj.get("state", SuitModel.OBJ_PENDING))
		var y := OBJ_Y + OBJ_STEP * float(i - first)
		var dot_color := OdiseaOSTheme.state(SuitModel.objective_theme_state(state))
		var text_color := OdiseaOSTheme.SUIT_DIM
		var marker := "-"
		if state == SuitModel.OBJ_ACTIVE:
			text_color = OdiseaOSTheme.SUIT_ACCENT
			marker = ">"
		elif state == SuitModel.OBJ_DONE:
			marker = "[OK]"
		set_cursor_pos(Vector2(ROW_X, y + 4.0))
		image(_white_tex, Vector2(10, 10), dot_color)
		_draw_line(ROW_X + 20.0, y, text_color, "%s %s" % [marker, String(obj.get("text", ""))])


# --- helpers ----------------------------------------------------------------------

func _draw_line(x: float, y: float, color: Color, text: String) -> void:
	set_cursor_pos(Vector2(x, y))
	if body_font >= 0:
		push_font(body_font)
	text_colored(color, text)
	if body_font >= 0:
		pop_font()


func _value_row(y: float, label: String, value: String, value_color: Color) -> void:
	set_cursor_pos(Vector2(ROW_X, y))
	if body_font >= 0:
		push_font(body_font)
	text_colored(OdiseaOSTheme.SUIT_DIM, label)
	same_line(VALUE_X)
	text_colored(value_color, value)
	if body_font >= 0:
		pop_font()


func _clip(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	return text.substr(0, max_chars - 3) + "..."
