extends SceneTree

const DEFAULT_SCENE := "res://core_v2/ui/retro/DebugOverlay.tscn"

var _scene_path := DEFAULT_SCENE
var _output_dir := "res://test_output/ui"
var _prefix := "debugoverlay"
var _late_delay := 0.0
var _late_label := "3_late"

func _init() -> void:
	_parse_args()
	call_deferred("_run")

func _parse_args() -> void:
	var args = OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--scene="):
			_scene_path = arg.substr("--scene=".length(), arg.length())
		elif arg.begins_with("--out="):
			_output_dir = arg.substr("--out=".length(), arg.length())
		elif arg.begins_with("--late-delay="):
			_late_delay = max(0.0, arg.substr("--late-delay=".length(), arg.length()).to_float())
		elif arg.begins_with("--late-label="):
			_late_label = arg.substr("--late-label=".length(), arg.length())

	if _scene_path.strip_edges() == "":
		_scene_path = OS.get_environment("OYS_UI_SCENE")
	if _scene_path.strip_edges() == "":
		_scene_path = DEFAULT_SCENE

	_prefix = _scene_path.get_file().get_basename().to_lower()

func _run() -> void:
	var packed = load(_scene_path)
	if packed == null:
		printerr("[ui_screenshot_runner] Failed to load scene: ", _scene_path)
		quit(1)
		return

	var inst = packed.instance()
	if inst == null:
		printerr("[ui_screenshot_runner] Failed to instance scene: ", _scene_path)
		quit(1)
		return

	root.add_child(inst)
	current_scene = inst

	# Let the scene initialize before first capture.
	yield(self, "idle_frame")
	yield(VisualServer, "frame_post_draw")
	_capture("0_boot")

	# Wait for desktop after BIOS lines.
	yield(create_timer(2.4), "timeout")
	yield(VisualServer, "frame_post_draw")
	_capture("1_desktop")

	# Ensure terminal remains centered/open if helper exists.
	if inst.has_method("_center_terminal_window"):
		inst.call("_center_terminal_window")
	yield(self, "idle_frame")
	yield(VisualServer, "frame_post_draw")
	_capture("2_terminal")

	if _late_delay > 0.0:
		yield(create_timer(_late_delay), "timeout")
		yield(VisualServer, "frame_post_draw")
		_capture(_late_label)

	quit(0)

func _capture(label: String) -> void:
	var dir = Directory.new()
	if not dir.dir_exists(_output_dir):
		dir.make_dir_recursive(_output_dir)

	var img = root.get_texture().get_data()
	img.flip_y()
	var path = "%s/%s_%s.png" % [_output_dir, _prefix, label]
	var err = img.save_png(path)
	if err != OK:
		printerr("[ui_screenshot_runner] Failed saving: ", path, " err=", err)
	else:
		print("[ui_screenshot_runner] Saved: ", path)
