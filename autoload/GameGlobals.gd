extends Node

# GameGlobals (autoload: "GameGlobals")
# Responsibility: Point of entry global, configuration and handling of basic binary states.
# It will absorb and modernize the logic of the old GameState.gd.

# Controls the mouse mode (Input.MOUSE_MODE_CAPTURED).
var mouse_captured: bool = false setget set_mouse_captured

# Activates/Deactivates debugging tools (e.g., DrawRay from icarito-odisea.txt).
var debug_mode: bool = true setget set_debug_mode

# Global pause state of the game (get_tree().paused).
var is_paused: bool = false setget set_is_paused

# Application ID for canvas environments.
var app_id: String = ""

# Screen detection
var is_widescreen := false
var screen_size := Vector2.ZERO

# Game mode
enum GAME_MODE {
	SINGLEPLAYER,
	COPILOT,
	NETWORKED  # Future
}
var current_mode = GAME_MODE.SINGLEPLAYER

# Signals
signal debug_mode_changed(enabled)
signal game_paused(is_paused)

func set_mouse_captured(value: bool) -> void:
	mouse_captured = value
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE)

func set_debug_mode(value: bool) -> void:
	if debug_mode != value:
		debug_mode = value
		emit_signal("debug_mode_changed", debug_mode)

func set_is_paused(value: bool) -> void:
	if is_paused != value:
		is_paused = value
		get_tree().paused = is_paused
		emit_signal("game_paused", is_paused)

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

	print("[GameGlobals] Modo cambiado a: %s" % mode_str)

func get_mode() -> String:
	"""Retornar modo actual como string."""
	match current_mode:
		GAME_MODE.SINGLEPLAYER:
			return "singleplayer"
		GAME_MODE.COPILOT:
			return "copilot"
		GAME_MODE.NETWORKED:
			return "networked"
	return "unknown"

func _ready() -> void:
	# Initialize mouse mode on start
	self.mouse_captured = mouse_captured
	# Initialize pause state
	self.is_paused = is_paused
	# Detect screen info
	_detect_screen_info()

func _detect_screen_info() -> void:
	"""Detectar pantalla."""
	screen_size = OS.get_screen_size()
	var aspect = float(screen_size.x) / float(screen_size.y)
	is_widescreen = (aspect >= 1.5) # and OS.get_name() not in ["Android", "iOS"]

	print("[GameGlobals] Screen: %.0fx%.0f | Widescreen: %s" % [screen_size.x, screen_size.y, is_widescreen])
