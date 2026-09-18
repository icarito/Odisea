extends Node

const SETTINGS_PATH = "user://settings.cfg"
const DISABLE_VSYNC_ENV = "ODISEA_DISABLE_VSYNC"

var _config = ConfigFile.new()

# Default values
var master_volume = 1.0
var music_volume = 1.0
var sfx_volume = 1.0
# Inversion manual de ejes analogos (Opciones -> Invertir X / Invertir Y).
# No se detecta sola: un firmware que reporta los ejes al reves lo hace en los dos
# sticks a la vez (movimiento y camara) y no hay huella fiable que lo delate. El
# defecto es no invertir nada, asi el mismo paquete sirve en todos los handhelds.
var invert_x = false
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
var telemetry_enabled: bool = false
var consent_asked: bool = false
# Overlay de log en pantalla (core_v2/levels/diag/LogOverlay.gd). NO se persiste a
# proposito: es una herramienta de la sesion activa. Si se guardara, un arranque con
# problemas dejaria el overlay prendido para siempre y encima taparia la pantalla justo
# cuando el jugador quiere jugar. Cada arranque empieza apagado; la opcion de Opciones
# y ODISEA_LOG_OVERLAY lo prenden para esta corrida nada mas.
var log_overlay_enabled: bool = false
# Enviar al central las lineas de error del log al terminar la sesion
# (core_v2/telemetry/ErrorLogReporter.gd). Va junto a telemetry_enabled porque es el
# mismo trato con el jugador: datos de diagnostico, no de juego.
var error_reports_enabled: bool = false
# Control remoto habilitado
var remote_control_enabled: bool = true
# Agujero de dither: los props que tapan al jugador se vuelven translucidos
# (core_v2/autoloads/PropDitherManager.gd). Estuvo apagado a la fuerza en iOS mientras
# se buscaba por que los props no se dibujaban ahi; la causa era el lightmap del motor,
# no este shader. Queda como opcion para poder apagarlo en el dispositivo sin otro build.
var prop_dither_enabled: bool = true
# Forzar el tier de render LOW (FD-299): sin post-process del environment y con
# lightmap manual. El GLES3VendorGate lo activa solo en adapters verificados
# (Mali-G31 via FRT); esta opcion lo fuerza a mano en cualquier dispositivo.
var low_end_forced: bool = false
# Idioma de la interfaz ("auto"|"es"|"en").
var ui_language: String = "auto"

func _ready():
	load_settings()
	apply_all_settings()

func load_settings():
	var err = _config.load(SETTINGS_PATH)
	if err != OK:
		print("[SettingsManager] No se pudo cargar el archivo de configuración, usando valores por defecto.")
		telemetry_enabled = false
		error_reports_enabled = false
		consent_asked = false
		return

	master_volume = _config.get_value("audio", "master_volume", 1.0)
	music_volume = _config.get_value("audio", "music_volume", 1.0)
	sfx_volume = _config.get_value("audio", "sfx_volume", 1.0)

	invert_x = _config.get_value("input", "invert_x", false)
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
	remote_control_enabled = _config.get_value("network", "remote_control_enabled", true)
	telemetry_enabled = _config.get_value("privacy", "telemetry_enabled", false)
	error_reports_enabled = _config.get_value("privacy", "error_reports_enabled", false)
	# El default es true a proposito, y solo aplica cuando el archivo YA existe: una
	# instalacion vieja tiene su preferencia guardada de antes y no se le vuelve a
	# preguntar ni se le cambia nada. Una instalacion nueva no llega hasta aca (el
	# load() falla mas arriba y deja consent_asked en false), que es cuando se pregunta.
	consent_asked = _config.get_value("privacy", "consent_asked", true)
	prop_dither_enabled = _config.get_value("display", "prop_dither_enabled", true)
	low_end_forced = _config.get_value("rendering", "low_end_forced", false)
	ui_language = _config.get_value("locale", "ui_language", "auto")

func save_settings():
	_config.set_value("audio", "master_volume", master_volume)
	_config.set_value("audio", "music_volume", music_volume)
	_config.set_value("audio", "sfx_volume", sfx_volume)

	_config.set_value("input", "invert_x", invert_x)
	_config.set_value("input", "invert_y", invert_y)
	_config.set_value("input", "vibration", vibration)

	_config.set_value("display", "fullscreen", fullscreen)
	_config.set_value("display", "render_resolution", render_resolution)
	_config.set_value("display", "render_scale", render_scale)
	_config.set_value("display", "vsync", vsync)
	_config.set_value("network", "remote_control_enabled", remote_control_enabled)
	_config.set_value("privacy", "telemetry_enabled", telemetry_enabled)
	_config.set_value("privacy", "error_reports_enabled", error_reports_enabled)
	_config.set_value("privacy", "consent_asked", consent_asked)
	_config.set_value("display", "prop_dither_enabled", prop_dither_enabled)
	_config.set_value("rendering", "low_end_forced", low_end_forced)
	_config.set_value("locale", "ui_language", ui_language)

	var err = _config.save(SETTINGS_PATH)
	if err != OK:
		printerr("[SettingsManager] Error al guardar configuración: ", err)

func needs_privacy_consent() -> bool:
	return not consent_asked

func apply_all_settings():
	apply_locale_settings()
	apply_audio_settings()
	apply_display_settings()
	apply_privacy_settings()

func resolve_effective_language() -> String:
	if ui_language == "auto":
		var sys_locale = OS.get_locale().to_lower()
		if sys_locale.begins_with("es"):
			return "es"
		else:
			return "en"
	return ui_language

func apply_locale_settings() -> void:
	if not _has_translation("en"):
		var trans = load("res://locale/ui_strings.en.translation") as Translation
		if trans != null:
			TranslationServer.add_translation(trans)
			if not _has_translation("es"):
				var trans_es = Translation.new()
				trans_es.locale = "es"
				for msg_key in trans.get_message_list():
					trans_es.add_message(msg_key, msg_key)
				TranslationServer.add_translation(trans_es)
	var effective = resolve_effective_language()
	TranslationServer.set_locale(effective)

func _has_translation(locale_code: String) -> bool:
	for loc in TranslationServer.get_loaded_locales():
		if String(loc) == locale_code:
			return true
	return false

func apply_privacy_settings() -> void:
	var telemetry = get_node_or_null("/root/ANNAV2")
	if telemetry and telemetry.has_method("set_telemetry_enabled"):
		telemetry.set_telemetry_enabled(telemetry_enabled)
	if OS.has_feature("JavaScript") and Engine.has_singleton("JavaScript"):
		var js_cmd = "window.OdiseaShell && window.OdiseaShell.setTelemetryConsent && window.OdiseaShell.setTelemetryConsent(%s);" % ("true" if telemetry_enabled else "false")
		JavaScript.eval(js_cmd, true)

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

# Con stretch "viewport" la UI se dibuja a la misma resolucion que el 3D: a render_scale < 1
# el texto de un menu sale pixelado (a 640x480 al 60% son 384x288 estirados). Mientras haya
# una pantalla encima del mundo pausado (Opciones, modo HUD) se renderiza a escala 1.0 — el
# 3D de fondo esta quieto y no hay nada que ahorrar — y al cerrarla vuelve la escala elegida.
var _full_resolution_holders := {}

func hold_full_resolution_ui(holder: Object, hold: bool) -> void:
	var was_held := not _full_resolution_holders.empty()
	if hold:
		_full_resolution_holders[holder.get_instance_id()] = true
	else:
		_full_resolution_holders.erase(holder.get_instance_id())
	if was_held != (not _full_resolution_holders.empty()):
		apply_render_resolution()

# La escala con la que se dibuja de verdad (la elegida, o 1.0 con una pantalla abierta).
func effective_render_scale() -> float:
	if not _full_resolution_holders.empty():
		return 1.0
	return clamp(render_scale, 0.5, 1.0)

# Apply the internal render resolution. With stretch mode "viewport" the game
# renders to render_resolution and the engine stretches it to the window, so
# this works the same in fullscreen, windowed, web and Android.
func apply_render_resolution():
	var tree = get_tree()
	if tree == null:
		return
	var effective_resolution: Vector2 = render_resolution * effective_render_scale()
	tree.set_screen_stretch(
		SceneTree.STRETCH_MODE_VIEWPORT,
		SceneTree.STRETCH_ASPECT_EXPAND,
		effective_resolution
	)
