extends Control

export var enable_touch_buttons := true

onready var fade_rect: ColorRect = $CanvasLayer/ColorRect
onready var new_game_button = find_node("NewGame")
onready var continue_button = find_node("Continue")
onready var options_button = find_node("Options")
onready var quit_button = find_node("Quit")
onready var options_menu = $OptionsMenu

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_check_save_game()
	_connect_signals()

	if continue_button.visible and not continue_button.disabled:
		continue_button.grab_focus()
	else:
		new_game_button.grab_focus()

	# Fade in al cargar
	fade_rect.modulate.a = 1.0
	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)

	if enable_touch_buttons:
		var handler = $TouchCanvasLayer/TouchHandler
		var temp_buttons = []
		for b in [new_game_button, continue_button, options_button, quit_button]:
			if b:
				temp_buttons.append(b)
		handler.buttons = temp_buttons

func _check_save_game():
	# Simple check for existing checkpoints
	var dir = Directory.new()
	var has_save = false
	if dir.dir_exists("user://checkpoints"):
		dir.open("user://checkpoints")
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				has_save = true
				break
			file_name = dir.get_next()

	continue_button.disabled = not has_save

func _connect_signals():
	new_game_button.connect("pressed", self, "_on_NewGame_pressed")
	continue_button.connect("pressed", self, "_on_Continue_pressed")
	options_button.connect("pressed", self, "_on_Options_pressed")
	quit_button.connect("pressed", self, "_on_Quit_pressed")

func _on_NewGame_pressed():
	# TODO: Clear existing save? Requirement didn't specify.
	_start_game("res://core_v2/levels/BaseTerrace.tscn")

func _on_Continue_pressed():
	# PersistenceManager will handle loading the latest checkpoint automatically when the scene loads
	# For now, we just go to the main level.
	_start_game("res://core_v2/levels/BaseTerrace.tscn")

func _on_Options_pressed():
	options_menu.show()
	options_menu.on_show()

func _on_Quit_pressed():
	get_tree().quit()

func _start_game(scene_path):
	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tween.tween_callback(self, "_on_fade_out_complete", [scene_path])

func _on_fade_out_complete(scene_path):
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("goto_scene"):
		scene_manager.goto_scene(scene_path, {
			"show_loading": false,
			"fade_out": 0.0,
			"fade_in": 0.25
		})
	else:
		get_tree().change_scene(scene_path)
