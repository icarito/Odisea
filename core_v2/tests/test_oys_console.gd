extends GdUnitTestSuite

const OYSConsole = preload("res://core_v2/ui/retro/OYS_Console.gd")

class DummyActor extends Node:
	var hp := 10
	var label := "pilot"

func _make_console_with_scene() -> Dictionary:
	var scene := Node.new()
	scene.name = "TestRoot"
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene

	var actor := DummyActor.new()
	actor.name = "player"
	scene.add_child(actor)

	var enemy := Node.new()
	enemy.name = "enemy_one"
	scene.add_child(enemy)

	var enemy_boss := Node.new()
	enemy_boss.name = "enemy_boss"
	scene.add_child(enemy_boss)

	var console = OYSConsole.new()
	console.name = "OYS_Console_Test"
	console._cfg_path = "user://oys_shell_test.cfg"
	scene.add_child(console)

	return {
		"scene": scene,
		"actor": actor,
		"console": console
	}

func _cleanup_ctx(ctx: Dictionary) -> void:
	var scene = ctx.get("scene", null)
	if scene and is_instance_valid(scene):
		scene.queue_free()
	yield (get_tree(), "idle_frame")

func _logs_with_tag(console: OYS_Console, tag: String) -> Array:
	var out := []
	for entry in console.get_logs():
		if str(entry.get("tag", "")) == tag:
			out.append(str(entry.get("text", "")))
	return out

func test_pwd_and_cd_on_vfs() -> void:
	var ctx = _make_console_with_scene()
	var console: OYS_Console = ctx.get("console")

	console.call("_execute_line", "pwd", 0)
	console.call("_execute_line", "cd /proc", 0)
	console.call("_execute_line", "pwd", 0)

	var sys_logs = _logs_with_tag(console, "SYS")
	assert_bool(sys_logs.has("/root")).is_true()
	assert_bool(sys_logs.has("cwd: /proc")).is_true()
	assert_bool(sys_logs.has("/proc")).is_true()

	yield (_cleanup_ctx(ctx), "completed")

func test_ls_pipeline_with_grep_and_grep_v() -> void:
	var ctx = _make_console_with_scene()
	var console: OYS_Console = ctx.get("console")

	console.call("_execute_line", "ls /root | grep enemy | grep -v boss", 0)

	var sys_logs = _logs_with_tag(console, "SYS")
	assert_bool(sys_logs.has("enemy_one/")).is_true()
	assert_bool(sys_logs.has("enemy_boss/")).is_false()

	yield (_cleanup_ctx(ctx), "completed")

func test_echo_redirect_sets_property_and_validates_type() -> void:
	var ctx = _make_console_with_scene()
	var console: OYS_Console = ctx.get("console")
	var actor: DummyActor = ctx.get("actor")

	console.call("_execute_line", "echo \"42\" > /root/player/hp", 0)
	assert_int(actor.hp).is_equal(42)

	console.call("_execute_line", "echo \"nope\" > /root/player/hp", 0)
	assert_int(actor.hp).is_equal(42)

	var err_logs = _logs_with_tag(console, "ERR")
	var has_type_error := false
	for msg in err_logs:
		if msg.find("type mismatch") != -1:
			has_type_error = true
			break
	assert_bool(has_type_error).is_true()

	yield (_cleanup_ctx(ctx), "completed")

func test_read_only_blocks_mutation_commands() -> void:
	var ctx = _make_console_with_scene()
	var console: OYS_Console = ctx.get("console")
	var scene: Node = ctx.get("scene")

	console.read_only = true
	console.call("_execute_line", "rm /root/player", 0)

	assert_object(scene.get_node_or_null("player")).is_not_null()
	var warn_logs = _logs_with_tag(console, "WARN")
	assert_bool(warn_logs.has("Console is in read-only mode.")).is_true()

	yield (_cleanup_ctx(ctx), "completed")
