extends Node2D

onready var debug_label: Label = $VBoxContainer/HBoxContainer/ScrollContainer/DebugLabel
onready var cursor: Sprite = $Cursor

func _ready():
	# BGM del menú
	if typeof(AudioManager) != TYPE_NIL and AudioManager:
		var stream := load("res://assets/music/Orbital Descent.mp3")
		if stream:
			AudioManager.play_bgm(stream, -8.0, true)


func _unhandled_input(event):
	# --- DEBUG LABEL ---
	var text = debug_label.text
	var lista = Array(text.split("\n"))
	while lista.size() > 11:
		lista.pop_front()
	text = PoolStringArray(lista).join("\n")
	debug_label.text = text + "\n" + event.as_text()
	# --------------------

func _on_Start_pressed():
	get_tree().change_scene("res://scenes/levels/act1/Criogenia.tscn")
