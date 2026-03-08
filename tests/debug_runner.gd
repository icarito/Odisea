extends SceneTree

const TEST_FILE_FLAG := "--test-file"


func _init() -> void:
	var test_file := _extract_test_file(OS.get_cmdline_args())
	if test_file == "":
		printerr("[debug_runner] Missing %s <path>" % TEST_FILE_FLAG)
		quit(2)
		return

	var oys_path := _normalize_res_path(test_file)
	OS.set_environment("OYS_AUTO_RUN", oys_path)

	var main_scene_path := ""
	if ProjectSettings.has_setting("application/run/main_scene"):
		main_scene_path = String(ProjectSettings.get_setting("application/run/main_scene"))
	if main_scene_path == "":
		printerr("[debug_runner] Missing application/run/main_scene in project settings.")
		quit(3)
		return

	var main_scene = load(main_scene_path)
	if main_scene == null or not (main_scene is PackedScene):
		printerr("[debug_runner] Failed to load main scene: %s" % main_scene_path)
		quit(4)
		return

	var instance = (main_scene as PackedScene).instance()
	if instance == null:
		printerr("[debug_runner] Failed to instance main scene: %s" % main_scene_path)
		quit(5)
		return

	get_root().add_child(instance)
	current_scene = instance


func _extract_test_file(args: Array) -> String:
	for i in range(args.size()):
		if String(args[i]) != TEST_FILE_FLAG:
			continue
		if i + 1 < args.size():
			return String(args[i + 1]).strip_edges()
	return ""


func _normalize_res_path(raw_path: String) -> String:
	var clean := raw_path.strip_edges()
	if clean.begins_with("res://"):
		return clean
	while clean.begins_with("./"):
		clean = clean.substr(2, clean.length() - 2)
	return "res://%s" % clean
