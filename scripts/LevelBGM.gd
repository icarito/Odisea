extends Node

export (String) var track_path := "res://assets/music/Rust and Ruin.mp3"
export (float) var volume_db := -8.0
export (bool) var loop := true

func _ready() -> void:
	if typeof(AudioSystem) != TYPE_NIL and AudioSystem:
		AudioSystem.play_bgm(track_path, 0.0, loop, volume_db)
