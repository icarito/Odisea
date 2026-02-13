extends SceneTree

var _test_file: String = ""
var _exit_code: int = 0
var _session_manager = null
var _first_frame: bool = true
var _pending_start: bool = false
var _frames_waited: int = 0

func _init():
	print("[INFO]: Test initialization, Godot version: %s" % Engine.get_version_info().string)

	_parse_args()
	if _test_file.empty():
		printerr("[ERROR]: No test file provided. Use --test-file <path>")
		quit(2)
		return

	print("[INFO]: Running test file: %s" % _test_file)

	_setup_autoloads()

func _parse_args():
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		if args[i] == "--test-file" and i + 1 < args.size():
			_test_file = args[i+1]

func _setup_autoloads():
	# Replicate Autoloads from project.godot
	# AudioManager, SessionManager, PersistenceManager, WallOcclusionManager, CinematicManager, CameraTransition

	_add_autoload("AudioManager", "res://core_v2/autoloads/AudioManager.gd")
	_add_autoload("PersistenceManager", "res://core_v2/autoloads/PersistenceManager.gd")
	_add_autoload("WallOcclusionManager", "res://core_v2/autoloads/WallOcclusionManager.gd")
	_add_autoload("CinematicManager", "res://core_v2/autoloads/CinematicManager.gd")
	_add_autoload("CameraTransition", "res://addons/camera_transition/camera_transition.tscn")

	# SessionManager is last as it might depend on others
	_session_manager = _add_autoload("SessionManager", "res://core_v2/autoloads/SessionManager.gd")

	if _session_manager:
		_session_manager.connect("replay_finished", self, "_on_replay_finished")

func _add_autoload(name: String, path: String) -> Node:
	var res = load(path)
	if not res:
		printerr("[ERROR]: Could not load autoload: %s at %s" % [name, path])
		return null

	var node = null
	if res is PackedScene:
		node = res.instance()
	elif res is GDScript or res is Script: # Handle script resources directly
		node = res.new()
	else:
		printerr("[ERROR]: Unknown resource type for autoload: %s" % name)
		return null

	node.name = name
	get_root().add_child(node)
	return node

func _extract_scene_path(file_path: String) -> String:
	# Default fallback
	var scene_path = "res://core_v2/levels/TestScene_v2.tscn"

	var f = File.new()
	if not f.file_exists(file_path):
		return scene_path

	if f.open(file_path, File.READ) == OK:
		if file_path.ends_with(".oys"):
			# Simple line scan for LEVEL command
			var content = f.get_as_text()
			for line in content.split("\n"):
				var l = line.strip_edges()
				if l.begins_with("LEVEL"):
					var parts = l.split(" ", false)
					if parts.size() > 1:
						scene_path = parts[1]
					break
		elif file_path.ends_with(".json"):
			var content = f.get_as_text()
			var parsed = JSON.parse(content)
			if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY:
				var meta = parsed.result.get("meta", {})
				# Prioritize explicit meta scene path
				if meta.has("scene_path"):
					scene_path = meta["scene_path"]
				# Fallback to scene key in meta if present
				elif meta.has("scene"):
					scene_path = meta["scene"]
		f.close()

	return scene_path

func _start_test():
	if _session_manager:
		# Disable CLI mode in SessionManager so we control the exit
		_session_manager.is_cli_mode = false

		# Proactively load the scene to ensure the tree is populated
		var scene_path = _extract_scene_path(_test_file)
		print("[DEBUG]: Pre-loading scene: %s" % scene_path)

		var packed_scene = load(scene_path)
		if packed_scene:
			var current = packed_scene.instance()
			get_root().add_child(current)
			# Important: Set current_scene so SessionManager finds it
			current_scene = current

			# Wait for _ready and group registration
			_pending_start = true
		else:
			printerr("[ERROR]: Could not load scene: %s" % scene_path)
			quit(4)
	else:
		printerr("[ERROR]: SessionManager not initialized.")
		quit(3)


func _on_replay_finished(success: bool, drift: float, frames: int):
	if success:
		print("[INFO]: Test passed. Drift: %s, Frames: %s" % [drift, frames])
		_exit_code = 0
	else:
		print("[ERROR]: Test failed. Drift: %s" % drift)
		_exit_code = 1

	quit(_exit_code)

func _idle(delta):
	if _first_frame:
		_first_frame = false
		_start_test()
		return false

	if _pending_start:
		_frames_waited += 1
		# Wait a few frames for nodes to register in groups (Player, etc.)
		if _frames_waited > 10: # Increased wait time slightly for safety
			_pending_start = false
			print("[DEBUG]: Invoking SessionManager.load_and_play with %s" % _test_file)
			_session_manager.load_and_play(_test_file)

	return false # return false to NOT quit the application, keep running loop
