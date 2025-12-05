# autoload/GameConfig.gd

extends Node

# ===== ENUMS =====
enum GAME_MODE {
	SINGLEPLAYER,
	COPILOT,
	NETWORKED  # Future
}

# ===== ESTADO GLOBAL =====
var current_mode = GAME_MODE.SINGLEPLAYER
var is_widescreen := false
var screen_size := Vector2.ZERO

func _ready():
	"""Inicializar configuración global."""
	_detect_screen_info()

func _detect_screen_info() -> void:
	"""Detectar pantalla."""
	screen_size = OS.get_screen_size()
	var aspect = float(screen_size.x) / float(screen_size.y)
	is_widescreen = (aspect >= 1.5) # and OS.get_name() not in ["Android", "iOS"]

	print("[GameConfig] Screen: %.0fx%.0f | Widescreen: %s" % [screen_size.x, screen_size.y, is_widescreen])

func set_mode(mode_str: String) -> void:
	"""Cambiar modo de juego."""
	match mode_str:
		"singleplayer":
			current_mode = GAME_MODE.SINGLEPLAYER
		"copilot":
			current_mode = GAME_MODE.COPILOT
		"networked":
			current_mode = GAME_MODE.NETWORKED
		_:
			push_warning("Modo desconocido: %s" % mode_str)

	print("[GameConfig] Modo cambiado a: %s" % mode_str)

func get_mode() -> String:
	"""Retornar modo actual como string."""
	match current_mode:
		GAME_MODE.SINGLEPLAYER:
			return "singleplayer"
		GAME_MODE.COPILOT:
			return "copilot"
		GAME_MODE.NETWORKED:
			return "networked"
		_:
			return "unknown"
