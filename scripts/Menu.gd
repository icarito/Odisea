extends Node2D

onready var debug_label: Label = $VBoxContainer/HBoxContainer/ScrollContainer/DebugLabel
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

func _on_Start_pressed():
	get_tree().change_scene("res://scenes/levels/act1/criogenia.tscn")
	
# eliminados botones de ejemplo

# eliminados botones de ejemplo
