extends Control

const FIRST_GAME_SCENE := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const MENU_BGM := "Tin Cosmos"
# Debe coincidir con el bgm_stream de BGMZoneV2 en Dome_Intro.tscn (mismo path
# res://assets/music/<nombre>) para que el crossfade arrancado aqui empalme sin corte
# cuando la zona real se registre al terminar de cargar el nivel.
const FIRST_GAME_BGM := "Elias... wake"

export var enable_touch_buttons := true

onready var fade_rect: ColorRect = $CanvasLayer/ColorRect
onready var tween: Tween = $Tween
onready var new_game_button = find_node("NewGame")
onready var continue_button = find_node("Continue")
onready var options_button = find_node("Options")
onready var quit_button = find_node("Quit")
onready var options_menu = $OptionsMenu
onready var version_label = get_node_or_null("VersionLabel")
var _continue_scene_path := ""

func _ready():
	var audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr:
		audio_mgr.crossfade_to_song(MENU_BGM, 1.0, 0.0, false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# FD-228: Confirm stable boot for UpdateManager
	if get_node_or_null("/root/UpdateManager"):
		get_node("/root/UpdateManager").confirm_boot()

	_check_save_game()
	_connect_signals()
	_initialize_version_label()

	# Ni HTML5 ni iOS deben mostrar "salir": en la web no hay a donde salir, y en iOS
	# Apple desaconseja explicitamente que una app se cierre sola (ademas el boton no
	# funcionaba alla). Si se agrega otra plataforma sin cierre, va en esta lista y en
	# la gemela de PauseMenu.gd.
	if quit_button and OS.get_name() in ["HTML5", "iOS"]:
		quit_button.visible = false

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
			if b and b.visible:
				temp_buttons.append(b)
		handler.buttons = temp_buttons
	call_deferred("_request_first_scene_preload")

func _request_first_scene_preload() -> void:
	yield(get_tree(), "idle_frame")
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager and scene_manager.has_method("request_scene_preload"):
		scene_manager.request_scene_preload(FIRST_GAME_SCENE)

func _check_save_game():
	var persistence = get_node_or_null("/root/PersistenceManager")
	_continue_scene_path = persistence.get_continue_scene_path() if persistence and persistence.has_method("get_continue_scene_path") else ""
	continue_button.disabled = _continue_scene_path == ""

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
	_start_game(FIRST_GAME_SCENE)

func _on_Continue_pressed():
	if _continue_scene_path == "":
		return
	var persistence = get_node_or_null("/root/PersistenceManager")
	if not persistence or not persistence.has_method("request_continue") or not persistence.request_continue():
		_check_save_game()
		return
	_start_game(_continue_scene_path)

func _on_Options_pressed():
	options_menu.show()
	options_menu.on_show()

func _on_Quit_pressed():
	get_tree().quit()

func _start_game(scene_path):
	# Si el destino es el nivel inicial, arrancar ya su musica (crossfade sin fijar
	# override) para que vaya sonando durante la pantalla de carga en vez de esperar a
	# que la BGMZoneV2 del nivel se registre. Otros destinos (Continue a mitad de
	# partida) dejan que SceneManager haga su fade-out/in por defecto y que la propia
	# zona decida la musica al cargar.
	if scene_path == FIRST_GAME_SCENE:
		var audio_mgr = get_node_or_null("/root/AudioManager")
		if audio_mgr:
			audio_mgr.crossfade_to_song(FIRST_GAME_BGM, 2.0, 0.0, false)
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
		# Gameplay scenes are heavy to load. Show the same loading
		# screen + progress bar the BootLoader uses, otherwise the player stares at a
		# frozen black fade with no feedback during the long interactive load.
		var params := {
			"transition": "loading",
			"show_loading": true,
			"show_progress": true,
			"loading_message": "Cargando...",
			"fade_out": 0.0,
			"fade_in": 0.25
		}
		if scene_path == FIRST_GAME_SCENE:
			# El fade-out/in automatico de SceneManager cortaria o reiniciaria el
			# crossfade a FIRST_GAME_BGM que ya arrancamos en _start_game(); dejarlo
			# vivir solo, la BGMZoneV2 del nivel lo toma sin corte al registrarse.
			params["skip_audio_fade"] = true
		scene_manager.goto_scene(scene_path, params)
	else:
		get_tree().change_scene(scene_path)
