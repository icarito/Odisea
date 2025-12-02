extends Node

export (String) var track_path := "res://assets/music/Rust and Ruin.mp3"
export (float) var volume_db := -8.0
export (bool) var loop := true

func _ready() -> void:
	if typeof(AudioManager) != TYPE_NIL and AudioManager:
		var s := load(track_path)
		if s:
			AudioManager.play_bgm(s, volume_db, loop)
