extends Control

export var enable_touch_buttons := true

onready var cursor: Sprite = find_node("Cursor")
onready var fade_rect: ColorRect = $CanvasLayer/ColorRect  # Agrega un CanvasLayer > ColorRect negro

func _ready():
	find_node("Start").grab_focus()

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

	if enable_touch_buttons:
		var handler = $TouchCanvasLayer/TouchHandler
		var temp_buttons = []
		for b in [find_node("Start"), find_node("CoopButton"), find_node("Quit")]:
			if b:
				temp_buttons.append(b)
		handler.buttons = temp_buttons

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
	#GameGlobals.set_mode("copilot")
	get_tree().change_scene("res://scenes/multiplayer/LocalMultiplayer.tscn")

func _on_Quit_pressed():
	get_tree().quit()
