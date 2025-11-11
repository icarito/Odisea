extends Node

signal input_mode_changed(mode)
signal ignore_next_mouse_motion()

enum InputMode { MOUSE, TOUCH }
var current_mode : int = InputMode.TOUCH

var mouse_capture_enabled := false
var ignore_next_mouse_motion_event := false
var initial_release := false
var menu_open := false
var movement_paused := false
const MOUSE_IDLE_TIMEOUT := 1
var mouse_idle_time := 0.0

@onready var player = get_tree().get_root().find_child("CogitoPlayer", true, false)

func _ready() -> void:
	if not DisplayServer.is_touchscreen_available():
		mouse_capture_enabled = true
		current_mode = InputMode.MOUSE
		emit_signal("input_mode_changed", InputMode.MOUSE)
		return

	mouse_capture_enabled = false
	initial_release = true
	await get_tree().process_frame
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if player and player.has_signal("menu_opened"):
		player.connect("menu_opened", Callable(self, "_on_menu_opened"))
	if player and player.has_signal("menu_closed"):
		player.connect("menu_closed", Callable(self, "_on_menu_closed"))
	if player and player.has_signal("movement_paused"):
		player.connect("movement_paused", Callable(self, "_on_movement_paused"))

func _on_menu_opened():
	menu_open = true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		mouse_capture_enabled = false

func _on_menu_closed():
	menu_open = false

func _on_movement_paused(is_paused: bool):
	movement_paused = is_paused

func _process(_delta: float) -> void:
	if not DisplayServer.is_touchscreen_available():
		return

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_idle_time += _delta
		if mouse_idle_time > MOUSE_IDLE_TIMEOUT:
			mouse_capture_enabled = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			mouse_idle_time = 0.0
			if current_mode != InputMode.TOUCH:
				current_mode = InputMode.TOUCH
				emit_signal("input_mode_changed", InputMode.TOUCH)
	else:
		mouse_idle_time = 0.0

func _input(event: InputEvent) -> void:
	if not DisplayServer.is_touchscreen_available():
		return

	if event is InputEventScreenTouch and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			mouse_capture_enabled = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			mouse_idle_time = 0.0
			if current_mode != InputMode.TOUCH:
				current_mode = InputMode.TOUCH
				emit_signal("input_mode_changed", InputMode.TOUCH)
		return

	if event is InputEventMouseMotion:
		if event.relative.length_squared() > 1.0:
			var player_paused = false
			if player and ("is_movement_paused" in player):
				player_paused = player.is_movement_paused
			if menu_open or movement_paused or player_paused:
				return
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				var viewport = get_viewport()
				if viewport:
					var center = viewport.get_visible_rect().size * 0.5
					Input.warp_mouse(center)
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				ignore_next_mouse_motion_event = true
				emit_signal("ignore_next_mouse_motion")
				mouse_capture_enabled = true
				if current_mode != InputMode.MOUSE:
					current_mode = InputMode.MOUSE
					emit_signal("input_mode_changed", InputMode.MOUSE)
			mouse_idle_time = 0.0
			if initial_release:
				initial_release = false
