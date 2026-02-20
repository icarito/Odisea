# OYS Runner: Converts .oys scripts to replay JSON and runs determinism tests
# Usage: Godot --script oys_runner.gd path/to/script.oys
extends SceneTree

const OYS_Resolver = preload("res://core_v2/systems/OYS_Resolver.gd")
const SessionManager = preload("res://core_v2/autoloads/SessionManager.gd")

func _normalize_negative_zero_in_place(value):
	var t = typeof(value)
	if t == TYPE_DICTIONARY:
		for key in value.keys():
			value[key] = _normalize_negative_zero_in_place(value[key])
		return value
	if t == TYPE_ARRAY:
		for i in range(value.size()):
			value[i] = _normalize_negative_zero_in_place(value[i])
		return value
	if t == TYPE_REAL and abs(value) < 0.0000001:
		return 0
	return value

func _json_print_normalized(data, indent := "") -> String:
	var normalized = data
	if typeof(data) in [TYPE_DICTIONARY, TYPE_ARRAY]:
		normalized = data.duplicate(true)
	normalized = _normalize_negative_zero_in_place(normalized)
	return JSON.print(normalized, indent)


func _run_oys_script(oys_path: String):
	print("[OYSRunner] Opening OYS script at path: ", oys_path)
	var file = File.new()
	if file.open(oys_path, File.READ) != OK:
		printerr("Failed to open OYS script: ", oys_path)
		return false
	var script_content = file.get_as_text()
	file.close()
	print("[OYSRunner] Script content preview:\n", script_content.substr(0, 200))
	var replay_data = OYS_Resolver.parse_script(script_content)
	if not replay_data:
		printerr("Failed to parse OYS script: ", oys_path)
		return false
	# Save replay JSON for determinism test
	var replay_path = oys_path.get_basename() + ".json"
	var f = File.new()
	if f.open(replay_path, File.WRITE) != OK:
		printerr("Failed to write replay: ", replay_path)
		return false
	f.store_string(_json_print_normalized(replay_data, "  "))
	f.close()
	print("Replay written to: ", replay_path)
	return true


func _initialize():
	var args = OS.get_cmdline_args()
	print("[OYSRunner] Command line args: ", args)
	if args.size() == 0:
		print("Usage: godot --script oys_runner.gd path/to/script.oys")
		quit()
		return
	# Find the first argument that ends with .oys
	var oys_path = ""
	for a in args:
		if a.ends_with(".oys"):
			oys_path = a
			break
	if oys_path == "":
		print("No .oys script provided in args: ", args)
		quit()
		return
	_run_oys_script(oys_path)
	quit()
