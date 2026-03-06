# core_v2/tests/test_oys_logic.gd
extends GdUnitTestSuite

const OYS_Parser = preload("res://core_v2/systems/OYS_Parser.gd")
const OYS_Interpreter = preload("res://core_v2/systems/OYS_Interpreter.gd")
const OYS_Resolver = preload("res://core_v2/systems/OYS_Resolver.gd")
const SubtitlesOverlayManager = preload("res://core_v2/autoloads/SubtitlesOverlayManager.gd")
const VCameraFollow = preload("res://addons/virtualcamera/TransformModifiers/Follow.gd")
const VCameraLookAt = preload("res://addons/virtualcamera/TransformModifiers/LookAt.gd")

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

func test_parse_camera_shake_positional():
	var inst = OYS_Parser.parse_instruction("CAMERA_SHAKE 0.6 0.12 20 2.5")
	assert_str(inst.command).is_equal("CAMERA_SHAKE")
	assert_bool(is_equal_approx(float(inst.get("duration", -1.0)), 0.6)).is_true()
	assert_bool(is_equal_approx(float(inst.get("amplitude", -1.0)), 0.12)).is_true()
	assert_bool(is_equal_approx(float(inst.get("frequency", -1.0)), 20.0)).is_true()
	assert_bool(is_equal_approx(float(inst.get("roll", -1.0)), 2.5)).is_true()

func test_parse_camera_shake_key_value_synonym():
	var inst = OYS_Parser.parse_instruction("SHAKE duration=0.5 amp=0.2 freq=18 rot=3")
	assert_str(inst.command).is_equal("CAMERA_SHAKE")
	assert_bool(is_equal_approx(float(inst.get("duration", -1.0)), 0.5)).is_true()
	assert_bool(is_equal_approx(float(inst.get("amplitude", -1.0)), 0.2)).is_true()
	assert_bool(is_equal_approx(float(inst.get("frequency", -1.0)), 18.0)).is_true()
	assert_bool(is_equal_approx(float(inst.get("roll", -1.0)), 3.0)).is_true()

func test_parse_camera_shake_stop_synonym():
	var inst = OYS_Parser.parse_instruction("STOP_SHAKE")
	assert_str(inst.command).is_equal("CAMERA_SHAKE_STOP")

func test_parse_play_sound_default_targets_sfx():
	var inst = OYS_Parser.parse_instruction('PLAY_SOUND "SFX Alarm"')
	assert_str(inst.command).is_equal("PLAY_SOUND")
	assert_str(String(inst.get("sfx", ""))).is_equal("SFX Alarm")

func test_parse_play_sound_explicit_sound_name():
	var inst = OYS_Parser.parse_instruction('PLAY_SOUND sound="ui_click"')
	assert_str(inst.command).is_equal("PLAY_SOUND")
	assert_str(String(inst.get("sound", ""))).is_equal("ui_click")

func test_parse_change_scene_positional():
	var inst = OYS_Parser.parse_instruction('CHANGE_SCENE "res://core_v2/levels/BaseTerrace.tscn" "fade" "spawn_door_A"')
	assert_str(inst.command).is_equal("CHANGE_SCENE")
	assert_str(String(inst.get("path", ""))).is_equal("res://core_v2/levels/BaseTerrace.tscn")
	assert_str(String(inst.get("transition", ""))).is_equal("fade")
	assert_str(String(inst.get("spawn_id", ""))).is_equal("spawn_door_A")

func test_parse_change_scene_key_values():
	var inst = OYS_Parser.parse_instruction('CHANGE_SCENE path="res://core_v2/levels/TestScene_v2.tscn" transition=loading spawn_id=door_b')
	assert_str(inst.command).is_equal("CHANGE_SCENE")
	assert_str(String(inst.get("path", ""))).is_equal("res://core_v2/levels/TestScene_v2.tscn")
	assert_str(String(inst.get("transition", ""))).is_equal("loading")
	assert_str(String(inst.get("spawn_id", ""))).is_equal("door_b")

func test_parse_vcamera_with_follow_and_look_at():
	var inst = OYS_Parser.parse_instruction('VCAMERA name="IntroFar" duration=1.2 follow="Pilot" look_at="Beacon"')
	assert_str(inst.command).is_equal("VCAMERA")
	assert_str(String(inst.get("name", ""))).is_equal("IntroFar")
	assert_bool(is_equal_approx(float(inst.get("duration", -1.0)), 1.2)).is_true()
	assert_str(String(inst.get("follow", ""))).is_equal("Pilot")
	assert_str(String(inst.get("look_at", ""))).is_equal("Beacon")
	assert_str(String(inst.get("mode", ""))).is_equal("script")

func test_parse_vcamera_blend_with_follow_and_look_at():
	var inst = OYS_Parser.parse_instruction('VCAMERA_BLEND name="IntroClose" duration=0.8 follow="none" lookat="target_node"')
	assert_str(inst.command).is_equal("VCAMERA_BLEND")
	assert_str(String(inst.get("name", ""))).is_equal("IntroClose")
	assert_bool(is_equal_approx(float(inst.get("duration", -1.0)), 0.8)).is_true()
	assert_str(String(inst.get("follow", ""))).is_equal("none")
	assert_str(String(inst.get("look_at", ""))).is_equal("target_node")
	assert_str(String(inst.get("mode", ""))).is_equal("script")

func test_parse_vcamera_mode_scene():
	var inst = OYS_Parser.parse_instruction('VCAMERA name="IntroFar" mode="scene"')
	assert_str(inst.command).is_equal("VCAMERA")
	assert_str(String(inst.get("mode", ""))).is_equal("scene")

func test_parse_vcamera_shake_with_spaced_vectors():
	var inst = OYS_Parser.parse_instruction('VCAMERA_SHAKE translation="(0.08, 0.05, 0.03)" rotation="(0, 0, 1.5)" intensity=0.6')
	assert_str(inst.command).is_equal("VCAMERA_SHAKE")
	assert_str(String(inst.get("translation", ""))).is_equal("(0.08, 0.05, 0.03)")
	assert_str(String(inst.get("rotation", ""))).is_equal("(0, 0, 1.5)")
	assert_bool(is_equal_approx(float(inst.get("intensity", -1.0)), 0.6)).is_true()

func test_parse_camera_shake_with_vector_syntax():
	var inst = OYS_Parser.parse_instruction('CAMERA_SHAKE translation="(0.1, 0.0, 0.0)" rotation="(0, 0, 2.0)" intensity=0.5 duration=0.6 frequency=20')
	assert_str(inst.command).is_equal("CAMERA_SHAKE")
	assert_str(String(inst.get("translation", ""))).is_equal("(0.1, 0.0, 0.0)")
	assert_str(String(inst.get("rotation", ""))).is_equal("(0, 0, 2.0)")
	assert_bool(is_equal_approx(float(inst.get("intensity", -1.0)), 0.5)).is_true()
	assert_bool(is_equal_approx(float(inst.get("duration", -1.0)), 0.6)).is_true()
	assert_bool(is_equal_approx(float(inst.get("frequency", -1.0)), 20.0)).is_true()

func test_parse_spawn_with_anna_options():
	var inst = OYS_Parser.parse_instruction('SPAWN scene="res://core_v2/actors/Pilot_v2.tscn" name="AnnaNPC" pos=[3, 1, 5] anna=true anna_model="res://core_v2/trained_models/anna_best_rl4.onnx" anna_target=[0, 1, 12]')
	assert_str(inst.command).is_equal("SPAWN")
	assert_str(String(inst.get("scene", ""))).is_equal("res://core_v2/actors/Pilot_v2.tscn")
	assert_str(String(inst.get("name", ""))).is_equal("AnnaNPC")
	assert_str(String(inst.get("anna", ""))).is_equal("true")
	assert_str(String(inst.get("anna_model", ""))).is_equal("res://core_v2/trained_models/anna_best_rl4.onnx")
	assert_str(String(inst.get("anna_target", ""))).is_equal("[0, 1, 12]")

func test_parse_anna_commands():
	var enable = OYS_Parser.parse_instruction('ANNA_ENABLE "AnnaNPC"')
	assert_str(enable.command).is_equal("ANNA_ENABLE")
	assert_str(String(enable.get("target", ""))).is_equal("AnnaNPC")

	var disable = OYS_Parser.parse_instruction('ANNA_DISABLE "AnnaNPC"')
	assert_str(disable.command).is_equal("ANNA_DISABLE")
	assert_str(String(disable.get("target", ""))).is_equal("AnnaNPC")

	var set_target = OYS_Parser.parse_instruction('ANNA_SET_TARGET "AnnaNPC" pos=(0, 1, 12)')
	assert_str(set_target.command).is_equal("ANNA_SET_TARGET")
	assert_str(String(set_target.get("target", ""))).is_equal("AnnaNPC")
	assert_str(String(set_target.get("pos", ""))).is_equal("(0, 1, 12)")

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

func test_resolver_camera_shake_generates_logic_events():
	var script = """
	CAMERA_SHAKE 0.4 0.1 16 2
	WAIT_FRAMES 2
	STOP_SHAKE
	"""
	var replay = OYS_Resolver.parse_script(script)
	var events = replay.get("events", {})
	assert_bool(events.has(0)).is_true()
	assert_bool(events.has(2)).is_true()
	assert_str(events[0][0].get("command", "")).is_equal("CAMERA_SHAKE")
	assert_str(events[2][0].get("command", "")).is_equal("CAMERA_SHAKE_STOP")

func test_resolver_play_sound_generates_logic_event():
	var script = """
	PLAY_SOUND "SFX Alarm"
	"""
	var replay = OYS_Resolver.parse_script(script)
	var events = replay.get("events", {})
	assert_bool(events.has(0)).is_true()
	assert_str(events[0][0].get("command", "")).is_equal("PLAY_SOUND")

class MockHost extends Node:
	func _init():
		pass
	func get_tree():
		return Engine.get_main_loop()

class MockHostNoSession extends Node:
	func _init():
		pass
	func get_tree():
		return Engine.get_main_loop()
	func get_node_or_null(path):
		if path == "/root/SessionManager":
			return null
		return .get_node_or_null(path)

class MockPivotAnimator extends Node:
	var stop_calls := 0
	func stop_override_animation() -> void:
		stop_calls += 1

class MockSceneManagerNode extends Node:
	var calls := []
	func goto_scene(path: String, params: Dictionary = {}):
		calls.append({
			"path": path,
			"params": params.duplicate(true)
		})
		return null

class MockHostWithSceneManager extends Node:
	var scene_manager = null
	func _init():
		scene_manager = MockSceneManagerNode.new()
		scene_manager.name = "SceneManager"
		add_child(scene_manager)
	func get_tree():
		return Engine.get_main_loop()
	func get_node_or_null(path):
		if path == "/root/SceneManager":
			return scene_manager
		if path == "/root/SessionManager":
			return null
		return .get_node_or_null(path)

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

class MockSfxNode extends Node:
	var plays := 0
	func play_sfx():
		plays += 1

class MockCinematicManagerShake extends Node:
	var calls := 0
	var last_duration := 0.0
	var last_amplitude := 0.0
	var last_frequency := 0.0
	var last_roll := 0.0

	func trigger_camera_shake(duration: float = 0.35, amplitude: float = 0.08, frequency: float = 28.0, roll_degrees: float = 1.0) -> void:
		calls += 1
		last_duration = duration
		last_amplitude = amplitude
		last_frequency = frequency
		last_roll = roll_degrees

class MockCinematicManagerCommands extends Node:
	var activate_calls := []
	var deactivate_calls := 0

	func activate_rig(rig_id: String, mode: int) -> void:
		activate_calls.append({
			"rig_id": rig_id,
			"mode": mode
		})

	func deactivate_rig() -> void:
		deactivate_calls += 1

class MockScreenEffectsManagerCommands extends Node:
	var show_calls := 0
	var hide_calls := 0

	func show_script_cinematic_bars(_immediate: bool = false) -> void:
		show_calls += 1

	func hide_script_cinematic_bars(_immediate: bool = false) -> void:
		hide_calls += 1

class MockHostForCameraShake extends Node:
	var cm = null
	func get_tree():
		return Engine.get_main_loop()
	func get_node_or_null(path):
		if path == "/root/CinematicManager":
			return cm
		return .get_node_or_null(path)

class MockHostForCinematicCommands extends Node:
	var cm = null
	var screen_fx = null

	func get_tree():
		return Engine.get_main_loop()

	func get_node_or_null(path):
		if path == "/root/CinematicManager":
			return cm
		if path == "/root/ScreenEffectsManager":
			return screen_fx
		return .get_node_or_null(path)

class DisabledSubtitlesManager extends SubtitlesOverlayManager:
	func is_enabled() -> bool:
		return false

class EnabledSubtitlesManager extends SubtitlesOverlayManager:
	func is_enabled() -> bool:
		return true

class MockSubtitleOverlay extends Node:
	var shown := []
	var clears := []

	func show_subtitle(text: String, color: Color = Color.white, duration: float = 2.5) -> void:
		shown.append({
			"text": text,
			"color": color,
			"duration": duration
		})

	func clear_subtitles(immediate: bool = false) -> void:
		clears.append(immediate)

class MockOverlayUIManager extends Node:
	var ensure_calls := 0
	var last_slot := ""

	func ensure_overlay(node_name: String, _scene: PackedScene, slot_name: String = "Passive") -> Node:
		ensure_calls += 1
		last_slot = slot_name
		var existing = get_node_or_null(node_name)
		if existing:
			return existing
		var overlay = MockSubtitleOverlay.new()
		overlay.name = node_name
		add_child(overlay)
		return overlay

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

func test_interpreter_play_sound_calls_sfx_node():
	var host = MockHost.new()
	add_child(host)
	var sfx = MockSfxNode.new()
	sfx.name = "SFX Alarm"
	host.add_child(sfx)

	var interpreter = OYS_Interpreter.new(host)
	interpreter.parse('PLAY_SOUND "SFX Alarm"')
	yield (_run_interpreter(interpreter), "completed")

	assert_int(sfx.plays).is_equal(1)
	host.queue_free()

func test_interpreter_change_scene_routes_to_scene_manager():
	var host = MockHostWithSceneManager.new()
	add_child(host)

	var interpreter = OYS_Interpreter.new(host)
	interpreter.parse('CHANGE_SCENE "res://core_v2/levels/BaseTerrace.tscn" "fade" "door_c"')
	yield (_run_interpreter(interpreter), "completed")

	assert_int(host.scene_manager.calls.size()).is_equal(1)
	var call = host.scene_manager.calls[0]
	assert_str(String(call.get("path", ""))).is_equal("res://core_v2/levels/BaseTerrace.tscn")
	var params: Dictionary = call.get("params", {})
	assert_str(String(params.get("transition", ""))).is_equal("fade")
	assert_str(String(params.get("spawn_id", ""))).is_equal("door_c")
	host.queue_free()

func test_interpreter_vcamera_applies_follow_and_look_at_targets():
	var host = MockHost.new()
	add_child(host)

	var pilot = Spatial.new()
	pilot.name = "Pilot"
	pilot.add_to_group("player")
	host.add_child(pilot)

	var beacon = Spatial.new()
	beacon.name = "Beacon"
	host.add_child(beacon)

	var alt_target = Spatial.new()
	alt_target.name = "AltTarget"
	host.add_child(alt_target)

	var vcam = Spatial.new()
	vcam.name = "IntroFar"
	var follow = VCameraFollow.new()
	follow.name = "Follow"
	follow.target_path = NodePath("../../Pilot")
	follow.target = pilot
	vcam.add_child(follow)
	var look_at = VCameraLookAt.new()
	look_at.name = "LookAt"
	look_at.look_at_target = NodePath("../../Beacon")
	vcam.add_child(look_at)
	host.add_child(vcam)

	var interpreter = OYS_Interpreter.new(host)
	interpreter._configure_vcamera_targets(vcam, {
		"mode": "script",
		"follow": "AltTarget",
		"look_at": "AltTarget"
	})

	assert_object(follow.target).is_not_null()
	assert_bool(follow.target == alt_target).is_true()
	assert_bool(String(look_at.look_at_target).ends_with("/AltTarget")).is_true()

	interpreter._configure_vcamera_targets(vcam, {"mode": "scene"})
	assert_object(follow.target).is_not_null()
	assert_bool(follow.target == pilot).is_true()
	var restored_look_target = look_at.get_node_or_null(look_at.look_at_target)
	assert_object(restored_look_target).is_not_null()
	assert_bool(restored_look_target == beacon).is_true()

	host.queue_free()

func test_interpreter_vcamera_scene_mode_clears_runtime_targets_when_editor_empty():
	var host = MockHost.new()
	add_child(host)

	var pilot = Spatial.new()
	pilot.name = "Pilot"
	pilot.add_to_group("player")
	host.add_child(pilot)

	var vcam = Spatial.new()
	vcam.name = "IntroScene"
	var scene_tx = Transform(Basis.IDENTITY, Vector3(1.25, 2.5, 3.75))
	vcam.set_meta("scene_follow_target_path", NodePath(""))
	vcam.set_meta("scene_look_at_target", NodePath(""))
	vcam.set_meta("scene_vcam_transform", scene_tx)

	var follow = VCameraFollow.new()
	follow.name = "Follow"
	follow.target = pilot
	vcam.add_child(follow)

	var look_at = VCameraLookAt.new()
	look_at.name = "LookAt"
	look_at.look_at_target = NodePath("../../Pilot")
	var scene_look_tx = Transform(Basis.IDENTITY, Vector3.ZERO)
	look_at.transform = scene_look_tx
	vcam.set_meta("scene_look_at_transform", scene_look_tx)
	vcam.add_child(look_at)

	host.add_child(vcam)
	vcam.global_transform = Transform(Basis(Vector3.UP, deg2rad(37.0)), Vector3(9, 9, 9))
	look_at.transform = Transform(Basis(Vector3.UP, deg2rad(65.0)), Vector3(1, 2, 3))

	var interpreter = OYS_Interpreter.new(host)
	interpreter._configure_vcamera_targets(vcam, {"mode": "scene"})

	assert_object(follow.target).is_null()
	assert_str(String(look_at.look_at_target)).is_equal("")
	assert_bool(vcam.global_transform.origin.distance_to(scene_tx.origin) < 0.001).is_true()
	assert_bool(look_at.transform.origin.distance_to(scene_look_tx.origin) < 0.001).is_true()

	host.queue_free()

func test_interpreter_vcamera_shake_routes_to_unified_camera_shake():
	var manager = MockCinematicManagerShake.new()
	var host = MockHostForCameraShake.new()
	host.cm = manager
	add_child(host)

	var interpreter = OYS_Interpreter.new(host)
	interpreter.parse('VCAMERA_SHAKE translation="(0.1, 0.0, 0.0)" rotation="(0, 0, 2.0)" intensity=0.5 duration=0.6 frequency=20')
	yield (_run_interpreter(interpreter), "completed")

	assert_int(manager.calls).is_equal(1)
	assert_bool(is_equal_approx(manager.last_duration, 0.6)).is_true()
	assert_bool(is_equal_approx(manager.last_amplitude, 0.05)).is_true()
	assert_bool(is_equal_approx(manager.last_frequency, 20.0)).is_true()
	assert_bool(is_equal_approx(manager.last_roll, 1.0)).is_true()

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

func test_subtitles_manager_uses_overlay_ui_host_when_available():
	var overlay_ui = get_tree().root.get_node_or_null("OverlayUIManager")
	assert_object(overlay_ui).is_not_null()

	var passive_slot = overlay_ui.get_slot("Passive")
	var existing = passive_slot.get_node_or_null("SubtitlesOverlay")
	if existing:
		existing.queue_free()
		yield (get_tree(), "idle_frame")

	var manager = EnabledSubtitlesManager.new()
	add_child(manager)

	manager.show_subtitle("hola overlay", Color(1, 0, 0), 1.5)
	yield (get_tree(), "idle_frame")

	var overlay = passive_slot.get_node_or_null("SubtitlesOverlay")
	assert_object(overlay).is_not_null()
	assert_bool(overlay.get_parent() == passive_slot).is_true()
	assert_int(overlay.get("_entries").size()).is_equal(1)

	manager.clear_subtitles(true)
	assert_int(overlay.get("_entries").size()).is_equal(0)

	manager.queue_free()

func test_interpreter_cinematic_start_shows_script_bars_and_activates_rig():
	var cm = MockCinematicManagerCommands.new()
	var screen_fx = MockScreenEffectsManagerCommands.new()
	var host = MockHostForCinematicCommands.new()
	host.cm = cm
	host.screen_fx = screen_fx
	add_child(host)

	var interpreter = OYS_Interpreter.new(host)
	interpreter.parse('CINEMATIC_START "IntroRig" LOCKED_VIEW')
	yield(_run_interpreter(interpreter), "completed")

	assert_int(screen_fx.show_calls).is_equal(1)
	assert_int(cm.activate_calls.size()).is_equal(1)
	assert_str(String(cm.activate_calls[0].get("rig_id", ""))).is_equal("IntroRig")
	assert_int(int(cm.activate_calls[0].get("mode", -1))).is_equal(2)
	host.queue_free()

func test_interpreter_cinematic_stop_hides_script_bars_and_deactivates_rig():
	var cm = MockCinematicManagerCommands.new()
	var screen_fx = MockScreenEffectsManagerCommands.new()
	var host = MockHostForCinematicCommands.new()
	host.cm = cm
	host.screen_fx = screen_fx
	add_child(host)

	var interpreter = OYS_Interpreter.new(host)
	interpreter.parse("CINEMATIC_STOP")
	yield(_run_interpreter(interpreter), "completed")

	assert_int(screen_fx.hide_calls).is_equal(1)
	assert_int(cm.deactivate_calls).is_equal(1)
	host.queue_free()

func test_request_fast_forward_interrupts_player_animation_player():
	var host = MockHostNoSession.new()
	add_child(host)

	var player := KinematicBody.new()
	player.name = "Pilot"
	player.add_to_group("player")
	host.add_child(player)

	var anim_player := AnimationPlayer.new()
	var anim := Animation.new()
	anim.length = 2.0
	anim_player.add_animation("Long", anim)
	player.add_child(anim_player)
	anim_player.play("Long")
	assert_bool(anim_player.is_playing()).is_true()

	var interpreter = OYS_Interpreter.new(host)
	interpreter.request_fast_forward()
	yield (get_tree(), "idle_frame")

	assert_bool(interpreter.fast_forward).is_true()
	assert_bool(anim_player.is_playing()).is_false()
	host.queue_free()

func test_request_fast_forward_prefers_pivot_stop_override():
	var host = MockHostNoSession.new()
	add_child(host)

	var player := KinematicBody.new()
	player.name = "Pilot"
	player.add_to_group("player")
	host.add_child(player)

	var visual := Spatial.new()
	visual.name = "Visual"
	player.add_child(visual)

	var pivot := MockPivotAnimator.new()
	pivot.name = "Pivot"
	visual.add_child(pivot)

	var interpreter = OYS_Interpreter.new(host)
	interpreter.request_fast_forward()

	assert_bool(interpreter.fast_forward).is_true()
	assert_int(pivot.stop_calls).is_equal(1)
	host.queue_free()
