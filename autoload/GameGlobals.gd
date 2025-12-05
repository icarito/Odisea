extends Node

# GameGlobals (autoload: "GameGlobals")
# Responsibility: Point of entry global, configuration and handling of basic binary states.
# It will absorb and modernize the logic of the old GameState.gd.

# Controls the mouse mode (Input.MOUSE_MODE_CAPTURED).
var mouse_captured: bool = false setget set_mouse_captured

# Activates/Deactivates debugging tools (e.g., DrawRay from icarito-odisea.txt).
var debug_mode: bool = false setget set_debug_mode

# Global pause state of the game (get_tree().paused).
var is_paused: bool = false setget set_is_paused

# Application ID for canvas environments.
var app_id: String = ""

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

func _ready() -> void:
	# Initialize mouse mode on start
	self.mouse_captured = mouse_captured
	# Initialize pause state
	self.is_paused = is_paused
