# core_v2/components/OYSComponent.gd
extends Node

class_name OYSComponent

const OYS_Interpreter = preload("../systems/OYS_Interpreter.gd")

export(String, FILE, "*.oys") var script_file
export(bool) var auto_pause_player = false

var interpreter: OYS_Interpreter
var last_modified_time: int = 0
var _current_path: String = ""

func _ready():
	interpreter = OYS_Interpreter.new(self)
	if script_file != "":
		load_and_start(script_file)

func load_and_start(path: String, start_section: String = ""):
	_current_path = path
	var f = File.new()
	if f.open(path, File.READ) == OK:
		var content = f.get_as_text()
		last_modified_time = f.get_modified_time(path)
		f.close()

		interpreter.parse(content)

		if auto_pause_player:
			_set_player_pause(true)

		call_deferred("_run_and_unpause", start_section)
	else:
		printerr("[OYSComponent] Could not open script: ", path)

func _run_and_unpause(start_section: String) -> void:
	var result = interpreter.run(start_section)
	if result is GDScriptFunctionState:
		yield(result, "completed")

	# Auto-unpause when script finishes
	if auto_pause_player:
		_set_player_pause(false)

func _process(_delta):
	if _current_path != "" and (OS.is_debug_build() or Engine.is_editor_hint()):
		var f = File.new()
		if f.file_exists(_current_path):
			var mtime = f.get_modified_time(_current_path)
			if mtime > last_modified_time:
				print("[OYSComponent] Hot-reloading script: ", _current_path)

				# Find current section to resume
				var current_section = ""
				for sname in interpreter.section_names:
					if interpreter.sections[sname] <= interpreter.pc:
						# Keep the latest section that started before or at current PC
						current_section = sname

				load_and_start(_current_path, current_section)

func _set_player_pause(paused: bool):
	var player = get_parent()
	# Try to find player if parent is not it (e.g. if we are a child of a Logic node)
	if not player or not player.is_in_group("player"):
		player = get_tree().get_root().find_node("Pilot", true, false)

	if player and "is_replay_mode" in player:
		player.is_replay_mode = paused
