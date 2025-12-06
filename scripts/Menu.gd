extends Control

onready var cursor: Sprite = find_node("Cursor")
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

	find_node("Start").grab_focus()

	# BGM del menú
	if typeof(AudioSystem) != TYPE_NIL and AudioSystem:
		var bgm_path := "res://assets/music/Orbital Descent.mp3"
		AudioSystem.play_bgm(bgm_path, 0.0, true, -8.0)
	
	# Fade in al cargar
	fade_rect.modulate.a = 1.0  # Empieza negro
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(fade_rect, "modulate:a", 1.0, 0.0, 1.0, Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.start()

	# Conectar botones
	find_node("Start").connect("pressed", self, "_on_Start_pressed")
	find_node("Quit").connect("pressed", self, "_on_Quit_pressed")
	if find_node("CoopButton"):
		find_node("CoopButton").connect("pressed", self, "_on_copilot_pressed")

func _on_Start_pressed():
	# Fade out antes de cambiar escena
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(fade_rect, "modulate:a", 0.0, 1.0, 0.5, Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.connect("tween_completed", self, "_on_fade_out_complete")
	tween.start()

func _on_fade_out_complete(_object, _key):
	get_tree().change_scene("res://scenes/levels/act1/Criogenia.tscn")

func _on_copilot_pressed():
	"""Multiplayer split-screen."""
	GameGlobals.set_mode("copilot")
	get_tree().change_scene("res://scenes/multiplayer/LocalMultiplayer.tscn")

func _on_Quit_pressed():
	get_tree().quit()
