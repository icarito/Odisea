extends Control

const EXTERIOR_SCENE := "res://core_v2/levels/OdiseaExterior.tscn"

export var enable_touch_buttons := true

onready var fade_rect: ColorRect = $CanvasLayer/ColorRect
onready var tween: Tween = $Tween
onready var new_game_button = find_node("NewGame")
onready var continue_button = find_node("Continue")
onready var options_button = find_node("Options")
onready var quit_button = find_node("Quit")
onready var options_menu = $OptionsMenu
onready var version_label = get_node_or_null("VersionLabel")

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# FD-228: Confirm stable boot for UpdateManager
	if get_node_or_null("/root/UpdateManager"):
		get_node("/root/UpdateManager").confirm_boot()

	_check_save_game()
	_connect_signals()
	_initialize_version_label()

	if continue_button.visible and not continue_button.disabled:
		continue_button.grab_focus()
	else:
		new_game_button.grab_focus()

	# Fade in al cargar
	fade_rect.modulate.a = 1.0
	tween.interpolate_property(fade_rect, "modulate:a", 1.0, 0.0, 1.0, Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.start()

	if enable_touch_buttons:
		var handler = $TouchCanvasLayer/TouchHandler
		var temp_buttons = []
		for b in [new_game_button, continue_button, options_button, quit_button]:
			if b:
				temp_buttons.append(b)
		handler.buttons = temp_buttons
	call_deferred("_request_exterior_preload")

func _request_exterior_preload() -> void:
	yield(get_tree(), "idle_frame")
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("request_scene_preload"):
		scene_manager.request_scene_preload(EXTERIOR_SCENE)

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

func _initialize_version_label():
	if version_label:
		var VersionLabelHelper = load("res://core_v2/ui/VersionLabel.gd")
		if VersionLabelHelper:
			version_label.text = VersionLabelHelper.get_formatted_version()

func _connect_signals():
	new_game_button.connect("pressed", self, "_on_NewGame_pressed")
	continue_button.connect("pressed", self, "_on_Continue_pressed")
	options_button.connect("pressed", self, "_on_Options_pressed")
	quit_button.connect("pressed", self, "_on_Quit_pressed")

func _on_NewGame_pressed():
	# TODO: Clear existing save? Requirement didn't specify.
	_start_game("res://scenes/levels/act0/Core.tscn")

func _on_Continue_pressed():
	# PersistenceManager will handle loading the latest checkpoint automatically when the scene loads
	# For now, we just go to the main level.
	_start_game("res://core_v2/levels/interiors/Dome_Crio.tscn")

func _on_Options_pressed():
	options_menu.show()
	options_menu.on_show()

func _on_Quit_pressed():
	get_tree().quit()

func _start_game(scene_path):
	# Avoid double-triggering if a button is pressed twice during the fade.
	for b in [new_game_button, continue_button, options_button, quit_button]:
		if b:
			b.disabled = true
	tween.stop_all()
	tween.interpolate_property(fade_rect, "modulate:a", fade_rect.modulate.a, 1.0, 0.5, Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.start()
	if not tween.is_connected("tween_completed", self, "_on_fade_out_complete"):
		tween.connect("tween_completed", self, "_on_fade_out_complete", [scene_path], CONNECT_ONESHOT)

func _on_fade_out_complete(_object, _key, scene_path):
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("goto_scene"):
		# Gameplay scenes (Core, Dome_Crio) are heavy to load. Show the same loading
		# screen + progress bar the BootLoader uses, otherwise the player stares at a
		# frozen black fade with no feedback during the long interactive load.
		scene_manager.goto_scene(scene_path, {
			"transition": "loading",
			"show_loading": true,
			"show_progress": true,
			"loading_message": "Cargando...",
			"fade_out": 0.0,
			"fade_in": 0.25
		})
	else:
		get_tree().change_scene(scene_path)
