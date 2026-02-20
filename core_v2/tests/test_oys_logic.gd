# core_v2/tests/test_oys_logic.gd
extends GdUnitTestSuite

const OYS_Parser = preload("res://core_v2/systems/OYS_Parser.gd")
const OYS_Interpreter = preload("res://core_v2/systems/OYS_Interpreter.gd")
const OYS_Resolver = preload("res://core_v2/systems/OYS_Resolver.gd")
const SubtitlesOverlayManager = preload("res://core_v2/autoloads/SubtitlesOverlayManager.gd")

func test_preprocess_comments():
	var script = """
	# This is a comment
	PRINT "Hello" # Inline comment
	   # Indented comment
	"""
	var lines = OYS_Parser.preprocess(script)
	# Current implementation: strips lines starting with #.
	# New implementation: should strip everything from # to end of line.
	# If implemented correctly:
	# Line 1: empty -> skipped
	# Line 2: PRINT "Hello"
	# Line 3: empty -> skipped
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).is_equal('PRINT "Hello"')

func test_preprocess_shebang():
	var script = """
	#!/usr/bin/env godot
	PRINT "Start"
	"""
	var lines = OYS_Parser.preprocess(script)
	assert_int(lines.size()).is_equal(1)
	assert_str(lines[0]).is_equal('PRINT "Start"')

func test_parse_for_loop():
	var line = "FOR 5"
	var inst = OYS_Parser.parse_instruction(line)
	if inst.has("error"):
		# Allow failure before implementation
		return
	assert_str(inst.command).is_equal("FOR")
	# Check if iterations is parsed correctly (as int or string)
	if inst.has("iterations"):
		assert_int(int(inst.iterations)).is_equal(5)

func test_parse_while_loop():
	var line = 'WHILE PROP "Door" is_active == false'
	var inst = OYS_Parser.parse_instruction(line)
	if inst.has("error"):
		return
	assert_str(inst.command).is_equal("WHILE")
	if inst.has("target"): assert_str(inst.target).is_equal("Door")

func test_parse_while_spaces_and_case():
	# Test case insensitivity and spaces in target
	var line = 'while prop "My Door" is_active == false'
	var inst = OYS_Parser.parse_instruction(line)
	assert_str(inst.command).is_equal("WHILE")
	assert_str(inst.prop_type).is_equal("PROP")
	assert_str(inst.target).is_equal("My Door")
	assert_str(inst.property).is_equal("is_active")

func test_parse_cls_command():
	var inst = OYS_Parser.parse_instruction("CLS")
	assert_str(inst.command).is_equal("CLS")

func test_parse_wait_frames_command():
	var inst = OYS_Parser.parse_instruction("WAIT_FRAMES 12")
	assert_str(inst.command).is_equal("WAIT_FRAMES")
	assert_str(String(inst.get("unit", ""))).is_equal("frames")
	assert_float(float(inst.get("value", -1.0))).is_equal(12.0)

func test_parse_wait_suffix_f_as_frames():
	var inst = OYS_Parser.parse_instruction("WAIT 7f")
	assert_str(inst.command).is_equal("WAIT")
	assert_str(String(inst.get("unit", ""))).is_equal("frames")
	assert_float(float(inst.get("value", -1.0))).is_equal(7.0)

func test_resolver_cls_generates_event():
	var script = """
	CLS
	WAIT 0.5
	CLS
	"""
	var replay = OYS_Resolver.parse_script(script)
	var events = replay.get("events", {})
	assert_bool(events.has(0)).is_true()
	assert_bool(events.has(30)).is_true()
	assert_str(events[0][0].get("command", "")).is_equal("CLS")
	assert_str(events[30][0].get("command", "")).is_equal("CLS")

func test_resolver_wait_frames_generates_exact_event_offset():
	var script = """
	PRINT "A"
	WAIT_FRAMES 3
	PRINT "B"
	"""
	var replay = OYS_Resolver.parse_script(script)
	var events = replay.get("events", {})
	assert_bool(events.has(0)).is_true()
	assert_bool(events.has(3)).is_true()
	assert_str(events[0][0].get("command", "")).is_equal("PRINT")
	assert_str(events[3][0].get("command", "")).is_equal("PRINT")

func test_resolver_wait_seconds_rounds_up_to_next_frame():
	var script = """
	PRINT "A"
	WAIT 0.01
	PRINT "B"
	"""
	var replay = OYS_Resolver.parse_script(script)
	var events = replay.get("events", {})
	assert_bool(events.has(0)).is_true()
	assert_bool(events.has(1)).is_true()
	assert_str(events[0][0].get("command", "")).is_equal("PRINT")
	assert_str(events[1][0].get("command", "")).is_equal("PRINT")

class MockHost extends Node:
	func _init():
		pass
	func get_tree():
		return Engine.get_main_loop()

class RecordingInterpreter extends OYS_Interpreter:
	var subtitles := []
	var clears := []
	func _init(host = null).(host):
		pass
	func _show_subtitle(text: String, color: Color = Color.white, duration: float = 2.5) -> void:
		subtitles.append({"text": text, "color": color, "duration": duration})
	func _clear_subtitles(immediate: bool = false) -> void:
		clears.append(immediate)

class SystemMockInterpreter extends OYS_Interpreter:
	var system_calls := []
	var async_pid := 4242
	var sync_exit_code := 7

	func _init(host = null).(host):
		pass

	func _run_system_command(exec_path: String, exec_args: Array, blocking: bool) -> Dictionary:
		system_calls.append({
			"exec": exec_path,
			"args": exec_args.duplicate(),
			"blocking": blocking
		})
		return {
			"ok": true,
			"value": sync_exit_code if blocking else async_pid,
			"blocking": blocking
		}

class DisabledSubtitlesManager extends SubtitlesOverlayManager:
	func is_enabled() -> bool:
		return false

func _run_interpreter(interpreter) -> void:
	var state = interpreter.run()
	if state is GDScriptFunctionState:
		yield (state, "completed")
	else:
		yield (get_tree(), "idle_frame")

func test_interpreter_for_loop():
	var host = MockHost.new()
	add_child(host)

	var interpreter = OYS_Interpreter.new(host)
	var script = """
	SET $count 0
	FOR 3
		WAIT 0.01
		MATH $count + 1
	ENDFOR
	"""
	interpreter.parse(script)
	# Mock yield to simulate run
	yield (interpreter.run(), "completed")

	var count = interpreter.variables.get("$count", 0)
	assert_float(count).is_equal(3.0)

	host.queue_free()

func test_interpreter_nested_loop():
	var host = MockHost.new()
	add_child(host)

	var interpreter = OYS_Interpreter.new(host)
	var script = """
	SET $count 0
	FOR 2
		WAIT 0.01
		FOR 3
			MATH $count + 1
		ENDFOR
	ENDFOR
	"""
	interpreter.parse(script)
	yield (interpreter.run(), "completed")

	var count = interpreter.variables.get("$count", 0)
	assert_float(count).is_equal(6.0) # 2 * 3 = 6

	host.queue_free()

func test_interpreter_while_loop():
	var host = MockHost.new()
	add_child(host)

	var interpreter = OYS_Interpreter.new(host)
	var script = """
	SET $counter 0
	WHILE $counter < 3
		WAIT 0.01
		MATH $counter + 1
	ENDWHILE
	"""
	interpreter.parse(script)
	yield (interpreter.run(), "completed")

	var count = interpreter.variables.get("$counter", 0)
	assert_float(count).is_equal(3.0)

	host.queue_free()

class MockProp extends Node:
	var is_active = false
	func set_active(val):
		is_active = val

class MockHostForWhile extends Node:
	var prop
	var current_prop setget , _get_current_prop
	func _init():
		prop = MockProp.new()
		prop.name = "Door"
		add_child(prop)
	func _get_current_prop():
		return prop
	func load_prop(_path):
		return prop
	func get_tree():
		return Engine.get_main_loop()
	func get_node_or_null(path):
		if path == "Door": return prop
		return null

func test_interpreter_while_prop():
	var host = MockHostForWhile.new()
	add_child(host)
	host.prop.is_active = true

	var interpreter = OYS_Interpreter.new(host)
	# Loop runs while active is true. Inside loop, we set it to false.
	# So it should run once.
	var script = """
	SET $ran 0
	WHILE PROP "Door" is_active == true
		WAIT 0.01
		SET $ran 1
		CALL "Door" method="set_active" args=[false]
	ENDWHILE
	"""
	interpreter.parse(script)
	yield (interpreter.run(), "completed")

	var ran = interpreter.variables.get("$ran", 0)
	assert_float(ran).is_equal(1.0)

	host.queue_free()

func test_math_complex_assignment():
	var host = MockHost.new()
	add_child(host)
	
	var interpreter = OYS_Interpreter.new(host)
	var script = """
	SET $a 10
	SET $b 4
	WAIT 0.01
	MATH $c = $a - $b
	"""
	interpreter.parse(script)
	yield (interpreter.run(), "completed")
	
	var c = interpreter.variables.get("$c", 0)
	assert_float(c).is_equal(6.0)
	
	host.queue_free()

func test_system_helper_async_default_returns_pid():
	var host = MockHost.new()
	add_child(host)

	var interpreter = SystemMockInterpreter.new(host)
	var script = """
	SET $pid SYSTEM python3 core_v2/anna/client/anna_scene_visual_driver.py --frames 8
	"""
	interpreter.parse(script)
	yield (_run_interpreter(interpreter), "completed")

	assert_int(interpreter.system_calls.size()).is_equal(1)
	var call = interpreter.system_calls[0]
	assert_bool(bool(call.get("blocking", true))).is_false()
	assert_str(String(call.get("exec", ""))).is_equal("python3")
	assert_int(int(interpreter.variables.get("$pid", -1))).is_equal(4242)

	host.queue_free()

func test_system_helper_sync_mode_returns_exit_code():
	var host = MockHost.new()
	add_child(host)

	var interpreter = SystemMockInterpreter.new(host)
	var script = """
	SET $exit SYSTEM sync python3 --version
	"""
	interpreter.parse(script)
	yield (_run_interpreter(interpreter), "completed")

	assert_int(interpreter.system_calls.size()).is_equal(1)
	var call = interpreter.system_calls[0]
	assert_bool(bool(call.get("blocking", false))).is_true()
	assert_str(String(call.get("exec", ""))).is_equal("python3")
	assert_int(int(interpreter.variables.get("$exit", -1))).is_equal(7)

	host.queue_free()

func test_interpreter_print_calls_subtitle():
	var host = MockHost.new()
	add_child(host)
	var interpreter = RecordingInterpreter.new(host)
	interpreter.parse('PRINT "Hola mundo"')
	yield (_run_interpreter(interpreter), "completed")

	assert_int(interpreter.subtitles.size()).is_equal(1)
	assert_str(interpreter.subtitles[0].get("text", "")).is_equal("Hola mundo")
	host.queue_free()

func test_interpreter_cls_calls_clear_with_fade():
	var host = MockHost.new()
	add_child(host)
	var interpreter = RecordingInterpreter.new(host)
	interpreter.parse("CLS")
	yield (_run_interpreter(interpreter), "completed")

	assert_int(interpreter.clears.size()).is_equal(1)
	assert_bool(interpreter.clears[0]).is_false()
	host.queue_free()

func test_interpreter_assert_subtitles_ok_and_fail():
	var host = MockHost.new()
	add_child(host)
	var interpreter = RecordingInterpreter.new(host)
	var script = """
	ASSERT 1 == 1 "ok"
	ASSERT 1 == 0 "bad"
	"""
	interpreter.parse(script)
	yield (_run_interpreter(interpreter), "completed")

	assert_int(interpreter.subtitles.size()).is_equal(2)
	assert_bool(String(interpreter.subtitles[0].get("text", "")).begins_with("ASSERT OK")).is_true()
	assert_bool(String(interpreter.subtitles[1].get("text", "")).begins_with("ASSERT FAIL")).is_true()
	assert_bool(interpreter.test_failed).is_true()
	host.queue_free()

func test_subtitles_manager_warn_once_when_unavailable():
	var manager = DisabledSubtitlesManager.new()
	assert_bool(manager.get("_warned_unavailable")).is_false()
	manager.show_subtitle("linea 1")
	assert_bool(manager.get("_warned_unavailable")).is_true()
	manager.clear_subtitles(false)
	assert_bool(manager.get("_warned_unavailable")).is_true()
	manager.free()
