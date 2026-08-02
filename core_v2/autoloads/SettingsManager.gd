extends Node

const SETTINGS_PATH = "user://settings.cfg"

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
var vsync = true
var telemetry_enabled: bool = true

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
	vsync = _config.get_value("display", "vsync", true)
	telemetry_enabled = _config.get_value("privacy", "telemetry_enabled", true)

func save_settings():
	_config.set_value("audio", "master_volume", master_volume)
	_config.set_value("audio", "music_volume", music_volume)
	_config.set_value("audio", "sfx_volume", sfx_volume)

	_config.set_value("input", "invert_y", invert_y)
	_config.set_value("input", "vibration", vibration)

	_config.set_value("display", "fullscreen", fullscreen)
	_config.set_value("display", "render_resolution", render_resolution)
	_config.set_value("display", "vsync", vsync)
	_config.set_value("privacy", "telemetry_enabled", telemetry_enabled)

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
	OS.vsync_enabled = vsync
	apply_render_resolution()

# Apply the internal render resolution. With stretch mode "viewport" the game
# renders to render_resolution and the engine stretches it to the window, so
# this works the same in fullscreen, windowed, web and Android.
func apply_render_resolution():
	var tree = get_tree()
	if tree == null:
		return
	tree.set_screen_stretch(
		SceneTree.STRETCH_MODE_VIEWPORT,
		SceneTree.STRETCH_ASPECT_EXPAND,
		render_resolution
	)
