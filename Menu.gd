extends Node2D

onready var debug_label: Label = $DebugLabel
onready var cursor: Sprite = $Cursor


func _unhandled_input(event):
	# --- DEBUG LABEL ---
	var text = debug_label.text
	var lista = Array(text.split("\n"))
	while lista.size() > 11:
		lista.pop_front()
	text = PoolStringArray(lista).join("\n")
	debug_label.text = text + "\n" + event.as_text()
	# --------------------

func _on_Third_pressed():
	get_tree().change_scene("res://World.tscn")
	
func _on_Flight_pressed():
	get_tree().change_scene("res://example/ExampleList.tscn")

func _on_Drive_pressed():
	get_tree().change_scene("res://Scenes/level1.tscn")
