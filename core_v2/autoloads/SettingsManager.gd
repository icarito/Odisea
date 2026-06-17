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
var resolution = Vector2(1920, 1080)
var vsync = true

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
	resolution = _config.get_value("display", "resolution", Vector2(1920, 1080))
	vsync = _config.get_value("display", "vsync", true)

func save_settings():
	_config.set_value("audio", "master_volume", master_volume)
	_config.set_value("audio", "music_volume", music_volume)
	_config.set_value("audio", "sfx_volume", sfx_volume)

	_config.set_value("input", "invert_y", invert_y)
	_config.set_value("input", "vibration", vibration)

	_config.set_value("display", "fullscreen", fullscreen)
	_config.set_value("display", "resolution", resolution)
	_config.set_value("display", "vsync", vsync)

	var err = _config.save(SETTINGS_PATH)
	if err != OK:
		printerr("[SettingsManager] Error al guardar configuración: ", err)

func apply_all_settings():
	apply_audio_settings()
	apply_display_settings()

func apply_audio_settings():
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)

func _set_bus_volume(bus_name: String, volume_linear: float):
	var bus_index = AudioServer.get_bus_index(bus_name)
	if bus_index != -1:
		AudioServer.set_bus_volume_db(bus_index, linear2db(volume_linear))

func apply_display_settings():
	OS.window_fullscreen = fullscreen
	if not fullscreen:
		OS.window_size = resolution
		# Center window
		var screen_size = OS.get_screen_size()
		OS.window_position = (screen_size - resolution) * 0.5
	OS.vsync_enabled = vsync
