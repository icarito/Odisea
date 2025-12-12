extends Resource
class_name Replay

# Metadata
var scene_path: String = ""
var godot_version: String = ""
var game_version: String = "" # You might want to add your own versioning
var timestamp: String = ""

# Initial state of tracked objects
var initial_states: Dictionary = {}

# Frame-by-frame data
var frames: Array = []

# Per-frame states for drift measurement
var frame_states: Array = []

func _init() -> void:
	pass

func save_to_json(path: String) -> int:
	var file = File.new()
	var error = file.open(path, File.WRITE)
	if error != OK:
		return error

	var data = {
		"scene_path": scene_path,
		"godot_version": godot_version,
		"game_version": game_version,
		"timestamp": timestamp,
		"initial_states": initial_states,
		"frames": frames,
		"frame_states": frame_states
	}

	file.store_line(to_json(data))
	file.close()
	
	# Save debug version with D_ prefix
	if path.begins_with("res://replays/"):
		var debug_path = path.replace("res://replays/", "res://replays/D_")
		var debug_file = File.new()
		if debug_file.open(debug_path, File.WRITE) == OK:
			debug_file.store_line(to_json(data))
			debug_file.close()
	
	return OK

func load_from_json(path: String) -> int:
	var file = File.new()
	var error = file.open(path, File.READ)
	if error != OK:
		return error

	var content = file.get_as_text()
	file.close()

	var data = parse_json(content)
	if typeof(data) == TYPE_DICTIONARY:
		scene_path = data.get("scene_path", "")
		godot_version = data.get("godot_version", "")
		game_version = data.get("game_version", "")
		timestamp = data.get("timestamp", "")
		initial_states = data.get("initial_states", {})
		frames = data.get("frames", [])
		frame_states = data.get("frame_states", [])
		return OK
	else:
		return FAILED
