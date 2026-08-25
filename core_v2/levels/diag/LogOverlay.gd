extends Node

# Muestra en pantalla el final del log del motor. SOLO iOS.
#
# En iOS no hay consola ni comandos remotos: ANNAV2 los bloquea en release, y en debug
# el build no se puede archivar para distribucion (xcodebuild: "ARCHIVE FAILED"). Los
# errores de compilacion de shaders del driver solo viven en user://logs/godot.log, que
# se activa con logging/file_logging/enable_file_logging.iOS.
#
# Uso: instanciar LogOverlay.tscn en la escena del nivel y sacarlo al terminar. En
# escritorio y Android se libera solo sin dibujar nada.

# Segundos antes de leer: los shaders se compilan al renderizar los primeros frames,
# asi que leer en _ready mostraria un log sin los errores que interesan.
const READ_DELAY := 6.0
const MAX_LINES := 14
const ENV_FLAG := "ODISEA_LOG_OVERLAY"

# Se muestran solo las lineas que contengan alguno de estos. Un log completo no entra
# en una pantalla y lo que importa es lo que el driver tenga para decir.
const KEYWORDS := ["ERROR", "error", "shader", "Shader", "SHADER", "WARNING", "GLES", "lightmap"]

var _label: Label
var _elapsed := 0.0
var _done := false

static func _wants_overlay(os_name: String, env_value: String) -> bool:
	if env_value.to_lower().strip_edges() in ["1", "true", "yes", "on"]:
		return true
	return os_name == "iOS"

func _ready() -> void:
	if not _wants_overlay(OS.get_name(), OS.get_environment(ENV_FLAG)):
		queue_free()
		return
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	layer.add_child(bg)
	_label = Label.new()
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.margin_left = 10
	_label.margin_top = 8
	_label.autowrap = true
	_label.text = "LOG OVERLAY: leyendo en %ds..." % int(READ_DELAY)
	layer.add_child(_label)
	set_process(true)

func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed < READ_DELAY:
		return
	_done = true
	set_process(false)
	_label.text = _read_report()

func _read_report() -> String:
	var path := String(ProjectSettings.get_setting("logging/file_logging/log_path"))
	if path == "":
		path = "user://logs/godot.log"

	var f := File.new()
	if not f.file_exists(path):
		return "LOG OVERLAY\nNO EXISTE %s\n(file_logging apagado en esta plataforma)" % path
	if f.open(path, File.READ) != OK:
		return "LOG OVERLAY\nno se pudo abrir %s" % path

	var hits := []
	var total := 0
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		total += 1
		for k in KEYWORDS:
			if line.find(k) != -1:
				hits.append(line)
				break
	f.close()

	var head := "LOG OVERLAY  lineas=%d  interesantes=%d" % [total, hits.size()]
	if hits.empty():
		# Que no haya ni un error tambien es un resultado: los shaders linkean y el
		# problema esta en la asignacion, no en la compilacion.
		return head + "\n(sin errores ni warnings en el log)"
	var shown = hits
	if shown.size() > MAX_LINES:
		shown = shown.slice(shown.size() - MAX_LINES, shown.size() - 1)
	return head + "\n" + PoolStringArray(shown).join("\n")
