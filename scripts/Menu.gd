extends Node2D

onready var cursor: Sprite = $Cursor

func _ready():
	# BGM del menú
	if typeof(AudioManager) != TYPE_NIL and AudioManager:
		var stream := load("res://assets/music/Orbital Descent.mp3")
		if stream:
			AudioManager.play_bgm(stream, -8.0, true)

func _on_Start_pressed():
	get_tree().change_scene("res://scenes/levels/act1/Criogenia.tscn")
