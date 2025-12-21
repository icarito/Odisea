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

# Sparse snapshots for debugging (every 60 frames)
var snapshots: Dictionary = {}

# Estado final completo (player y cámara)
export (Dictionary) var final_states = {}

func _init() -> void:
	pass


func save_to_json(path: String) -> int:
	   var file = File.new()
	   var error = file.open(path, File.WRITE)
	   if error != OK:
		   return error

	   # Validar que initial_states y frames tengan datos vitales
	   var valid = true
	   if initial_states.empty():
		   printerr("Replay JSON: initial_states está vacío!")
		   valid = false
	   if frames.empty():
		   printerr("Replay JSON: frames está vacío!")
		   valid = false
		   # No se puede acceder a frames[0] ni frames[-1] si está vacío
		   # Retornar error inmediatamente para evitar crash
		   return ERR_INVALID_DATA
	   if not frames[0].has("pilot_pos") or not frames[-1].has("pilot_pos"):
		   printerr("Replay JSON: primer/último frame sin posición de player!")
		   valid = false


	   var data = {
		   "scene_path": scene_path,
		   "godot_version": godot_version,
		   "game_version": game_version,
		   "timestamp": timestamp,
		   "initial_states": initial_states,
		   "final_states": final_states,
		   "frames": frames,
		   "frame_states": frame_states
	   }

	   file.store_line(to_json(data))
	   file.close()


	   if not valid:
		   return ERR_INVALID_DATA
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
		final_states = data.get("final_states", {})
		frames = data.get("frames", [])
		frame_states = data.get("frame_states", [])
		return OK
	else:
		return FAILED
