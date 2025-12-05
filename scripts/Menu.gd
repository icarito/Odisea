extends Control

onready var cursor: Sprite = $Cursor
onready var fade_rect: ColorRect = $CanvasLayer/ColorRect  # Agrega un CanvasLayer > ColorRect negro
var resolution_detector: MenuResolutionDetector

func _ready():
	# Instanciar detector si no existe
	if not has_node("MenuResolutionDetector"):
		resolution_detector = MenuResolutionDetector.new()
		resolution_detector.name = "MenuResolutionDetector"
		add_child(resolution_detector)
	else:
		resolution_detector = $MenuResolutionDetector

	# BGM del menú
	if typeof(AudioManager) != TYPE_NIL and AudioManager:
		var stream := load("res://assets/music/Orbital Descent.mp3")
		if stream:
			AudioManager.play_bgm(stream, -8.0, true)
	
	# Fade in al cargar
	fade_rect.modulate.a = 1.0  # Empieza negro
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(fade_rect, "modulate:a", 1.0, 0.0, 1.0, Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.start()

	# Conectar botones
	$VBoxContainer/HBoxContainer/VBoxContainer/Start.connect("pressed", self, "_on_Start_pressed")
	$VBoxContainer/HBoxContainer/VBoxContainer/Quit.connect("pressed", self, "_on_Quit_pressed")
	if has_node("VBoxContainer/HBoxContainer/VBoxContainer/CoopButton"):
		$VBoxContainer/HBoxContainer/VBoxContainer/CoopButton.connect("pressed", self, "_on_copilot_pressed")
	$VBoxContainer/HBoxContainer/VBoxContainer/NetworkButton.connect("pressed", self, "_on_NetworkButton_pressed")

	MultiplayerManager.connect("game_started", self, "_on_game_started")

func _on_NetworkButton_pressed():
	$VBoxContainer/NetworkPanel.visible = not $VBoxContainer/NetworkPanel.visible

func _on_Start_pressed():
	_start_game("res://scenes/levels/act1/Criogenia.tscn")

func _on_game_started():
	_start_game("res://scenes/multiplayer/CoopLevel.tscn")

func _start_game(scene_path):
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(fade_rect, "modulate:a", 0.0, 1.0, 0.5, Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.connect("tween_completed", self, "_on_fade_out_complete", [scene_path])
	tween.start()

func _on_fade_out_complete(object, key, scene_path):
	get_tree().change_scene(scene_path)

func _on_copilot_pressed():
	"""Multiplayer split-screen."""
	get_node("/root/GameConfig").set_mode("copilot")
	get_tree().change_scene("res://scenes/multiplayer/LocalMultiplayer.tscn")

func _on_Quit_pressed():
	get_tree().quit()
