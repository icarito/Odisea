extends Node

# Lector del log del motor en pantalla. Autoload: arranca dormido y solo construye la
# UI cuando se prende la opcion "Overlay de log" en Opciones
# (SettingsManager.log_overlay_enabled) o la variable de entorno de abajo.
#
# Pensado sobre todo para moviles: ahi no hay consola ni comandos remotos (ANNAV2 los
# bloquea en release, y en iOS debug el build no se puede archivar para distribucion --
# xcodebuild: "ARCHIVE FAILED"). Los errores del driver solo viven en
# user://logs/godot.log, que ya esta activo en todas las plataformas
# (logging/file_logging/enable_file_logging).
#
# Es de SESION: la opcion no se persiste, asi que el proximo arranque vuelve apagado.
# Cerrar el panel tambien la apaga, para que nada lo vuelva a abrir solo.
#
# Las sondas de diagnostico que vivian aca (dos planos para separar iluminacion por
# vertice de normales rotas, y el censo de usuarios del BakedLightmap) se fueron: esas
# dos preguntas ya estan contestadas -- ver core_v2/systems/IOSLightmapFallback.gd y el
# presupuesto de varyings en shaders/prop_dither_occlusion.gdshader.

const ENV_FLAG := "ODISEA_LOG_OVERLAY"
const LOG_PATH_FALLBACK := "user://logs/godot.log"
const REFRESH_SECONDS := 1.0
const MAX_LINES := 200
const FONT_DATA := preload("res://assets/fonts/Ac437_OlivettiThin_8x16.ttf")

# Se muestran solo las lineas que contengan alguno de estos. Un log completo no entra en
# una pantalla y lo que importa es lo que el motor y el driver tengan para decir.
const KEYWORDS := ["ERROR", "error", "SCRIPT ERROR", "shader", "Shader", "SHADER",
	"WARNING", "GLES", "lightmap", "Failed", "failed"]

# Alto del panel como fraccion de la pantalla, anclado ARRIBA. No es pantalla completa a
# proposito: el overlay se usa MIENTRAS se juega, para ver que dice el driver al entrar a
# una zona. Arriba y no abajo porque abajo viven el joystick y los botones tactiles.
const PANEL_HEIGHT_RATIO := 0.42
# Tamano de fuente en pixeles a 600 px de alto de viewport. Se reescala con el viewport
# real, que con stretch "viewport" es render_resolution * render_scale: sin esto el
# texto crece en pantalla justo cuando AdaptiveRenderScale baja la escala, y el log
# termina tapando el juego.
const FONT_SIZE_AT_600 := 13.0
const FONT_SIZE_MIN := 8
const FONT_SIZE_MAX := 40

var _layer: CanvasLayer = null
var _text: RichTextLabel = null
var _title: Label = null
var _close: Button = null
var _font: DynamicFont = null
var _elapsed := 0.0
var _read_pos := 0
var _shown := 0
var _aviso_sin_log := false
var _log_path := ""


static func _wants_overlay(env_value: String, setting_enabled: bool) -> bool:
	if env_value.to_lower().strip_edges() in ["1", "true", "yes", "on"]:
		return true
	return setting_enabled


func _ready() -> void:
	set_process(true)


func _settings():
	return get_node_or_null("/root/SettingsManager")


func _enabled() -> bool:
	var sm = _settings()
	return _wants_overlay(OS.get_environment(ENV_FLAG), sm != null and sm.log_overlay_enabled)


func _process(delta: float) -> void:
	var want := _enabled()
	if want and _layer == null:
		_build()
	elif not want and _layer != null:
		_teardown()
	if _layer == null:
		return
	_elapsed += delta
	if _elapsed < REFRESH_SECONDS:
		return
	_elapsed = 0.0
	_pump()


# --- UI ---------------------------------------------------------------------------

func _build() -> void:
	_log_path = String(ProjectSettings.get_setting("logging/file_logging/log_path"))
	if _log_path == "":
		_log_path = LOG_PATH_FALLBACK
	_read_pos = 0
	_shown = 0
	_aviso_sin_log = false

	_font = DynamicFont.new()
	_font.font_data = FONT_DATA

	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)

	var panel := PanelContainer.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = PANEL_HEIGHT_RATIO
	panel.margin_left = 8
	panel.margin_top = 8
	panel.margin_right = -8
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.82)
	style.border_color = Color(0.35, 0.85, 0.45, 0.7)
	style.set_border_width_all(1)
	for m in [MARGIN_LEFT, MARGIN_TOP, MARGIN_RIGHT, MARGIN_BOTTOM]:
		style.set_default_margin(m, 6)
	panel.add_stylebox_override("panel", style)
	# El overlay vive en la capa 128, por encima de la UI tactil (MobileUI usa 10 y 100).
	# Si el panel captura el toque, se come todo lo que quede debajo suyo. Nada del
	# overlay recibe input salvo la X: por eso tampoco hay seleccion de texto ni scroll
	# a mano en el log -- el scroll se sigue solo.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(panel)

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rows)

	_title = Label.new()
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.text = "LOG"
	rows.add_child(_title)

	_text = RichTextLabel.new()
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.scroll_following = true
	_text.selection_enabled = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_text)

	# La X cuelga del CanvasLayer, NO del panel: asi su unico ancestro no es un Control y
	# no depende de como resuelva el motor un hijo que para el input dentro de padres que
	# lo ignoran. Es el unico nodo del overlay que recibe toques.
	_close = Button.new()
	_close.text = "X"
	_close.anchor_left = 1.0
	_close.anchor_right = 1.0
	_close.hint_tooltip = "Cerrar el overlay de log (tambien apaga la opcion)"
	_close.connect("pressed", self, "_on_close_pressed")
	_layer.add_child(_close)

	_apply_font_size()
	var vp := get_viewport()
	if vp != null and not vp.is_connected("size_changed", self, "_apply_font_size"):
		vp.connect("size_changed", self, "_apply_font_size")

	_pump()


func _teardown() -> void:
	var vp := get_viewport()
	if vp != null and vp.is_connected("size_changed", self, "_apply_font_size"):
		vp.disconnect("size_changed", self, "_apply_font_size")
	if _layer != null:
		_layer.queue_free()
	_layer = null
	_text = null
	_title = null
	_close = null
	_font = null


func _on_close_pressed() -> void:
	var sm = _settings()
	if sm != null:
		sm.log_overlay_enabled = false
	_teardown()


func _apply_font_size() -> void:
	if _font == null:
		return
	var vp := get_viewport()
	var height: float = vp.size.y if vp != null else 600.0
	var size := int(round(FONT_SIZE_AT_600 * height / 600.0))
	_font.size = int(clamp(size, FONT_SIZE_MIN, FONT_SIZE_MAX))
	if _text != null:
		_text.add_font_override("normal_font", _font)
	if _title != null:
		_title.add_font_override("font", _font)
	if _close != null:
		_close.add_font_override("font", _font)
		# Blanco tactil: un "X" del tamano del texto es imposible de acertar con el dedo.
		# El piso va en fraccion del viewport, no en pixeles fijos: con stretch "viewport"
		# un minimo absoluto crece en pantalla justo cuando baja el render_scale, que es
		# lo contrario de lo que hace el texto.
		var lado: float = max(_font.size * 2.4, height * 0.05)
		_close.rect_min_size = Vector2(lado, lado)
		_close.margin_left = -lado - 12
		_close.margin_right = -12
		_close.margin_top = 12
		_close.margin_bottom = 12 + lado


# --- Lectura incremental -----------------------------------------------------------

# Se relee SOLO lo que crecio desde la ultima pasada: el log del motor no para de crecer
# y releerlo entero cada segundo cuesta mas que lo que se muestra.
func _pump() -> void:
	if _text == null:
		return
	var f := File.new()
	if not f.file_exists(_log_path):
		if not _aviso_sin_log:
			_aviso_sin_log = true
			_text.clear()
			_text.add_text("no existe %s\n(file_logging = %s)" % [
				_log_path, ProjectSettings.get_setting("logging/file_logging/enable_file_logging")])
		return
	if f.open(_log_path, File.READ) != OK:
		return
	var length := int(f.get_len())
	# El motor rota los logs: si el archivo encogio, arrancar de cero.
	if length < _read_pos:
		_read_pos = 0
	if length == _read_pos:
		f.close()
		return
	f.seek(_read_pos)
	var nuevas := []
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		for k in KEYWORDS:
			if line.find(k) != -1:
				nuevas.append(line)
				break
	_read_pos = length
	f.close()

	if _aviso_sin_log:
		_aviso_sin_log = false
		_text.clear()
	for line in nuevas:
		_text.add_text(line + "\n")
		_shown += 1
	# El RichTextLabel guarda todo lo que se le mete; sin tope, una sesion larga con un
	# error por frame se come la memoria.
	while _text.get_line_count() > MAX_LINES:
		_text.remove_line(0)
	if _title != null:
		_title.text = "LOG  %s  lineas=%d" % [_log_path.get_file(), _shown]
