extends Node

const SETTINGS_PATH = "user://settings.cfg"
const DISABLE_VSYNC_ENV = "ODISEA_DISABLE_VSYNC"

var _config = ConfigFile.new()

# Default values
var master_volume = 1.0
var music_volume = 1.0
var sfx_volume = 1.0
var invert_y = false
var vibration = true
var fullscreen = true
# Internal render resolution. The project uses stretch mode "viewport", so the
# game renders to this base size and is stretched to fill the window. Lower
# values give the retro/CRT look and cost much less to render, independent of
# window size or fullscreen.
var render_resolution = Vector2(800, 600)
var render_scale: float = 1.0
var vsync = true
var telemetry_enabled: bool = true
# Overlay de log en pantalla (core_v2/levels/diag/LogOverlay.gd). NO se persiste a
# proposito: es una herramienta de la sesion activa. Si se guardara, un arranque con
# problemas dejaria el overlay prendido para siempre y encima taparia la pantalla justo
# cuando el jugador quiere jugar. Cada arranque empieza apagado; la opcion de Opciones
# y ODISEA_LOG_OVERLAY lo prenden para esta corrida nada mas.
var log_overlay_enabled: bool = false
# Enviar al central las lineas de error del log al terminar la sesion
# (core_v2/telemetry/ErrorLogReporter.gd). Va junto a telemetry_enabled porque es el
# mismo trato con el jugador: datos de diagnostico, no de juego.
var error_reports_enabled: bool = true
# Agujero de dither: los props que tapan al jugador se vuelven translucidos
# (core_v2/autoloads/PropDitherManager.gd). Estuvo apagado a la fuerza en iOS mientras
# se buscaba por que los props no se dibujaban ahi; la causa era el lightmap del motor,
# no este shader. Queda como opcion para poder apagarlo en el dispositivo sin otro build.
var prop_dither_enabled: bool = true

func _ready():
	load_settings()
	apply_all_settings()

func load_settings():
	var err = _config.load(SETTINGS_PATH)
	if err != OK:
		print("[SettingsManager] No se pudo cargar el archivo de configuración, usando valores por defecto.")
		return

	master_volume = _config.get_value("audio", "master_volume", 1.0)
	music_volume = _config.get_value("audio", "music_volume", 1.0)
	sfx_volume = _config.get_value("audio", "sfx_volume", 1.0)

	invert_y = _config.get_value("input", "invert_y", false)
	vibration = _config.get_value("input", "vibration", true)

	fullscreen = _config.get_value("display", "fullscreen", true)
	render_resolution = _config.get_value("display", "render_resolution", Vector2(800, 600))
	var default_render_scale: float = 1.0
	render_scale = float(_config.get_value(
		"display",
		"render_scale",
		_config.get_value("display", "android_render_scale", default_render_scale)
	))
	vsync = _config.get_value("display", "vsync", true)
	telemetry_enabled = _config.get_value("privacy", "telemetry_enabled", true)
	error_reports_enabled = _config.get_value("privacy", "error_reports_enabled", true)
	prop_dither_enabled = _config.get_value("display", "prop_dither_enabled", true)

func save_settings():
	_config.set_value("audio", "master_volume", master_volume)
	_config.set_value("audio", "music_volume", music_volume)
	_config.set_value("audio", "sfx_volume", sfx_volume)

	_config.set_value("input", "invert_y", invert_y)
	_config.set_value("input", "vibration", vibration)

	_config.set_value("display", "fullscreen", fullscreen)
	_config.set_value("display", "render_resolution", render_resolution)
	_config.set_value("display", "render_scale", render_scale)
	_config.set_value("display", "vsync", vsync)
	_config.set_value("privacy", "telemetry_enabled", telemetry_enabled)
	_config.set_value("privacy", "error_reports_enabled", error_reports_enabled)
	_config.set_value("display", "prop_dither_enabled", prop_dither_enabled)

	var err = _config.save(SETTINGS_PATH)
	if err != OK:
		printerr("[SettingsManager] Error al guardar configuración: ", err)

func apply_all_settings():
	apply_audio_settings()
	apply_display_settings()
	apply_privacy_settings()

func apply_privacy_settings() -> void:
	var telemetry = get_node_or_null("/root/ANNAV2")
	if telemetry and telemetry.has_method("set_telemetry_enabled"):
		telemetry.set_telemetry_enabled(telemetry_enabled)

func apply_audio_settings():
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)

func _set_bus_volume(bus_name: String, volume_linear: float):
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		AudioServer.set_bus_volume_db(bus_index, linear2db(volume_linear))

func apply_display_settings():
	# El modo de ventana sólo se aplica con foco real. Al arrancar (sin foco)
	# entrar en fullscreen crea la ventana XWayland sin foco que rompe el grab
	# del mouse bajo Mutter ("input always below"); en ese caso lo difiere
	# SessionManager._promote_to_fullscreen_if_wanted() al primer FOCUS_IN, que
	# respeta esta misma preferencia. Con foco (cambio en Opciones) se aplica ya.
	if OS.is_window_focused():
		OS.window_fullscreen = fullscreen
	OS.vsync_enabled = _effective_vsync()
	apply_render_resolution()

# ODISEA_DISABLE_VSYNC=1 apaga el vsync solo para esta corrida (perfilado: con vsync
# el bloqueo del swap se contabiliza dentro de TIME_PROCESS y enmascara el costo real
# de CPU). Es un override de runtime: no toca `vsync` ni lo que se persiste en
# settings.cfg, asi que la preferencia del jugador sobrevive intacta.
func _effective_vsync() -> bool:
	if OS.get_environment(DISABLE_VSYNC_ENV).to_lower() in ["1", "true", "yes", "on"]:
		return false
	return vsync

# Apply the internal render resolution. With stretch mode "viewport" the game
# renders to render_resolution and the engine stretches it to the window, so
# this works the same in fullscreen, windowed, web and Android.
func apply_render_resolution():
	var tree = get_tree()
	if tree == null:
		return
	var effective_resolution: Vector2 = render_resolution * clamp(render_scale, 0.5, 1.0)
	tree.set_screen_stretch(
		SceneTree.STRETCH_MODE_VIEWPORT,
		SceneTree.STRETCH_ASPECT_EXPAND,
		effective_resolution
	)
