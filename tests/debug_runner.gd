extends SceneTree

var _test_file: String = ""
var _exit_code: int = 0
var _session_manager = null
var _first_frame: bool = true

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

func _start_test():
	if _session_manager:
		# Disable CLI mode in SessionManager so we control the exit
		_session_manager.is_cli_mode = false

		# Depending on the file type, SessionManager handles loading the scene.
		# .oys files usually contain a LEVEL command.
		# .json files usually contain meta.scene_path.

		# We must ensure we are in a valid state.
		# SessionManager.load_and_play expects to be able to find the player and such.
		# It handles scene loading if LEVEL is present.

		print("[DEBUG]: Invoking SessionManager.load_and_play with %s" % _test_file)
		_session_manager.load_and_play(_test_file)
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
	return false # return false to NOT quit the application, keep running loop
