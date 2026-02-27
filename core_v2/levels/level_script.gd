extends CSGBox

export(bool) var auto_start_intro := true
export(String, FILE, "*.oys") var intro_script_file := "res://core_v2/scripts/intro.oys"
export(String) var start_section := "Intro"
export(bool) var ignore_level_directive := true

var _started := false

func _ready() -> void:
	if not auto_start_intro:
		return
	var rl_mode_env = OS.get_environment("ANNA_RL_MODE").to_lower()
	if rl_mode_env in ["1", "true", "yes", "on"]:
		return
	if Engine.has_singleton("GdUnit3") and Engine.get_singleton("GdUnit3").is_test_suite():
		return
	var session = get_node_or_null("/root/SessionManager")
	if _is_cli_session(session):
		return
	if OS.get_environment("OYS_AUTO_RUN") != "":
		return
	call_deferred("_start_intro_if_possible")

func _start_intro_if_possible() -> void:
	if _started:
		return

	var session = get_node_or_null("/root/SessionManager")
	var is_replaying := false
	var is_recording := false
	if session:
		is_replaying = bool(session.get("is_replaying"))
		is_recording = bool(session.get("is_recording"))
	if is_replaying or is_recording:
		return

	var player = _find_player()
	var attempts := 0
	while not is_instance_valid(player) and attempts < 120:
		attempts += 1
		yield(get_tree(), "idle_frame")
		player = _find_player()
	if not is_instance_valid(player):
		printerr("[LevelScript] Could not find player to start intro script: ", intro_script_file)
		return

	var comp = player.get_node_or_null("OYSComponent")
	if not comp:
		var comp_class = load("res://core_v2/components/OYSComponent.gd")
		comp = comp_class.new()
		comp.name = "OYSComponent"
		player.add_child(comp)

	_started = true

	if ignore_level_directive and comp.has_method("load_and_start_ignoring_level"):
		comp.load_and_start_ignoring_level(intro_script_file, start_section)
	else:
		comp.load_and_start(intro_script_file, start_section)

func _find_player() -> Node:
	var players = get_tree().get_nodes_in_group("player")
	for candidate in players:
		if is_instance_valid(candidate):
			return candidate
	return null

func _is_cli_session(session: Node) -> bool:
	if not session:
		return false
	if session.has_method("get"):
		return bool(session.get("is_cli_mode"))
	return false
