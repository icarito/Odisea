extends Control

export var enable_touch_buttons := true

onready var cursor: Sprite = find_node("Cursor")
onready var fade_rect: ColorRect = $CanvasLayer/ColorRect # Agrega un CanvasLayer > ColorRect negro

func _ready():
	find_node("Start").grab_focus()

	# Fade in al cargar
	fade_rect.color.a = 1.0 # Empieza negro
	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 0.0, 1.0).from(1.0).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	# El tween se auto-inicia y auto-libera.
	# No es necesario llamar a tween.start() en Godot 3.x con create_tween()
	# ni a queue_free() si no es un nodo.

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
	# Usamos create_tween() para que el tween se gestione automáticamente.
	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 1.0, 0.5).from(0.0).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tween.tween_callback(self, "_on_fade_out_complete")

func _on_fade_out_complete():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) # Capturamos el mouse
	get_tree().change_scene("res://core_v2/scenes/BaseTerrace.tscn")

func _on_copilot_pressed():
	"""Multiplayer split-screen."""
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) # Capturamos el mouse también para el modo coop
	#GameGlobals.set_mode("copilot")
	get_tree().change_scene("res://scenes/multiplayer/LocalMultiplayer.tscn")

func _on_Quit_pressed():
	get_tree().quit()
