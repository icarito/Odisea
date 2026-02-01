# core_v2/systems/OYS_Interpreter.gd
# Runtime interpreter: executes OYS scripts with coroutines and signal support
# Used for in-game scripting, cutscenes, and interactive tests with ASSERT_SIGNAL
extends Reference

class_name OYS_Interpreter

const OYS_Parser = preload("res://core_v2/systems/OYS_Parser.gd")

var instructions: Array = []
var pc: int = 0
var variables: Dictionary = {}
var sections: Dictionary = {}
var section_names: Array = []
var host_node: Node
var is_running: bool = false
var stop_requested: bool = false
var execution_id: int = 0

func _init(host: Node):
	host_node = host

func parse(script_content: String):
	instructions.clear()
	sections.clear()
	section_names.clear()
	pc = 0

	var lines = OYS_Parser.preprocess(script_content)
	
	for i in range(lines.size()):
		var line = lines[i]
		var inst = OYS_Parser.parse_instruction(line)
		if inst.empty():
			continue

		if inst.command == "SECTION":
			var section_name = inst.get("name", "")
			sections[section_name] = instructions.size()
			section_names.append(section_name)

		instructions.append(inst)

func run(start_section: String = ""):
	execution_id += 1
	var my_id = execution_id

	if is_running:
		stop_requested = true
		if host_node and is_instance_valid(host_node) and host_node.is_inside_tree():
			yield (host_node.get_tree(), "physics_frame")

	is_running = true
	stop_requested = false

	if start_section != "" and sections.has(start_section):
		pc = sections[start_section]
	else:
		pc = 0

	while pc < instructions.size() and not stop_requested and my_id == execution_id:
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		var inst = instructions[pc]
		pc += 1
		var result = _execute_instruction(inst, my_id)
		if result is GDScriptFunctionState:
			yield (result, "completed")

	if my_id == execution_id:
		is_running = false

# Ejecutar desde un program counter específico (para hot-reload con checkpoints)
func run_from_pc(from_pc: int):
	execution_id += 1
	var my_id = execution_id

	if is_running:
		stop_requested = true
		if host_node and is_instance_valid(host_node) and host_node.is_inside_tree():
			yield (host_node.get_tree(), "physics_frame")

	is_running = true
	stop_requested = false
	pc = from_pc

	print("[OYS_Interpreter] Ejecutando desde pc=", pc)

	while pc < instructions.size() and not stop_requested and my_id == execution_id:
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		var inst = instructions[pc]
		pc += 1
		var result = _execute_instruction(inst, my_id)
		if result is GDScriptFunctionState:
			yield (result, "completed")

	if my_id == execution_id:
		is_running = false

func _execute_instruction(inst: Dictionary, my_id: int):
	var cmd = inst.command
	
	match cmd:
		"SECTION":
			pass # Already indexed
		
		"GOTO":
			var target = inst.get("target", "")
			if sections.has(target):
				pc = sections[target]
			else:
				printerr("[OYS] GOTO target not found: ", target)
		
		"IF":
			var left = _resolve_value(inst.get("left", ""))
			var right = _resolve_value(inst.get("right", ""))
			var op = inst.get("op", "==")
			var target = inst.get("target", "")
			if _compare(left, op, right):
				if sections.has(target):
					pc = sections[target]
				else:
					printerr("[OYS] IF GOTO target not found: ", target)
		
		"PLAY_ANIM":
			var node = _resolve_node(inst.get("path", ""))
			if node and node is AnimationPlayer:
				var blend = inst.get("blend", -1.0)
				node.play(inst.get("anim", ""), blend)
		
		"WAIT_ANIM":
			var node = _resolve_node(inst.get("path", ""))
			if node and node is AnimationPlayer:
				if node.is_playing():
					yield (node, "animation_finished")
		
		"ASSERT_SIGNAL":
			var target_path = inst.get("path", "")
			var target = host_node
			if target_path != "":
				target = _resolve_node(target_path)

			if target:
				var timeout = inst.get("timeout", 5.0)
				var signal_name = inst.get("signal", "")
				var success = yield (_wait_signal(target, signal_name, timeout, my_id), "completed")
				if not success:
					printerr("[OYS] ASSERT_SIGNAL failed: ", signal_name, " on ", target.name)
		
		"SPAWN":
			var scene_path = inst.get("scene", "")
			var scene = load(scene_path)
			if scene:
				var obj = scene.instance()
				host_node.get_tree().current_scene.add_child(obj)
				if inst.has("pos") and obj is Spatial:
					obj.global_transform.origin = OYS_Parser.parse_vector3(inst.pos)
		
		"SET_TIME_SCALE":
			Engine.time_scale = inst.get("value", 1.0)
		
		"WAIT":
			var duration = inst.get("value", 0.0)
			var t = host_node.get_tree().create_timer(duration)
			while t.time_left > 0:
				if stop_requested or my_id != execution_id:
					break
				yield (host_node.get_tree(), "physics_frame")
		
		"PRINT":
			print("[OYS PRINT] ", inst.get("message", ""))
			
		"SCREENSHOT":
			yield (VisualServer, "frame_post_draw")
			var img = host_node.get_viewport().get_texture().get_data()
			img.flip_y()
			var path = inst.get("path", "res://screenshot.png")
			img.save_png(path)
			print("[OYS] Screenshot saved to: ", path)
		
		"ASSERT":
			_execute_assert(inst.get("condition", ""))
		
		"SET":
			var var_name = inst.get("var", "")
			if inst.has("func"):
				variables[var_name] = _call_func(inst.func, inst.args)
			else:
				variables[var_name] = _resolve_value(inst.get("value", ""))
		
		"GET_NODES_IN_GROUP":
			var group = inst.get("group", "")
			var target_var = inst.get("target", "")
			variables[target_var] = host_node.get_tree().get_nodes_in_group(group).size()
		
		# Movement commands - apply to player's input provider
		"FW", "BW", "LEFT", "RIGHT", "JUMP", "INTERACT":
			yield (_execute_movement(inst, my_id), "completed")
		
		"LOOK":
			yield (_execute_look(inst, my_id), "completed")
		
		# Markers - no action needed
		"LEVEL", "END":
			pass
	
	return null

func _execute_movement(inst: Dictionary, my_id: int):
	var cmd = inst.command
	var player = _find_player()
	if not player:
		return
	
	var duration_sec = 0.0
	var move_vec = Vector2.ZERO
	var is_sprint = inst.get("is_running", true)
	var is_jump = false
	var is_interact = false
	
	match cmd:
		"FW", "BW":
			var value = inst.get("value", 0.0)
			var unit = inst.get("unit", "s")
			duration_sec = value
			if unit == "m":
				duration_sec = OYS_Parser.distance_to_duration(value, is_sprint)
			move_vec = Vector2(0, 1) if cmd == "FW" else Vector2(0, -1)
		
		"LEFT", "RIGHT":
			print("[OYS_Interpreter] LEFT/RIGHT: is_turning=", inst.get("is_turning", false), " value=", inst.get("value", 0), " unit=", inst.get("unit", "?"))
			if inst.get("is_turning", false):
				# For turning, we'll handle it separately
				yield (_execute_turn(inst, my_id), "completed")
				return
			var value = inst.get("value", 0.0)
			var unit = inst.get("unit", "s")
			duration_sec = value
			if unit == "m":
				duration_sec = OYS_Parser.distance_to_duration(value, is_sprint)
			move_vec = Vector2(1, 0) if cmd == "LEFT" else Vector2(-1, 0)
		
		"JUMP":
			duration_sec = inst.get("duration", 0.1)
			is_jump = true
		
		"INTERACT":
			duration_sec = 1.0 / 60.0 # One frame
			is_interact = true
	
	# Apply movement for duration
	var num_frames = OYS_Parser.duration_to_frames(duration_sec)
	for _i in range(num_frames):
		if stop_requested or my_id != execution_id:
			break
		
		# Verify player is still valid
		if not is_instance_valid(player):
			break
		
		# Inject input to player's provider
		if player.has_method("inject_input"):
			player.inject_input({
				"move_vec": [move_vec.x, move_vec.y],
				"sprint": is_sprint,
				"jump": is_jump,
				"interact": is_interact
			})
		
		# Verify host_node is still valid before yielding
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		yield (host_node.get_tree(), "physics_frame")

func _execute_turn(inst: Dictionary, my_id: int):
	var value = inst.get("value", 0.0)
	var direction = inst.get("direction", "LEFT")
	var duration_sec = 0.5
	var num_frames = OYS_Parser.duration_to_frames(duration_sec)
	
	var sensitivity = 0.005
	var pixels_total = (value * PI / 180.0) / sensitivity
	var mouse_dx = - pixels_total / num_frames if direction == "LEFT" else pixels_total / num_frames
	
	var player = _find_player()
	if not player:
		return
	
	for _i in range(num_frames):
		if stop_requested or my_id != execution_id:
			break
		
		# Verify player is still valid
		if not is_instance_valid(player):
			break
		
		if player.has_method("inject_input"):
			player.inject_input({"mouse_delta": [mouse_dx, 0]})
		
		# Verify host_node is still valid before yielding
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		yield (host_node.get_tree(), "physics_frame")

func _execute_look(inst: Dictionary, my_id: int):
	var pitch = inst.get("pitch", 0.0)
	var duration_sec = inst.get("duration", 0.5)
	var num_frames = OYS_Parser.duration_to_frames(duration_sec)
	var mouse_dy = - pitch / num_frames
	
	var player = _find_player()
	if not player:
		return
	
	for _i in range(num_frames):
		if stop_requested or my_id != execution_id:
			break
		
		# Verify player is still valid
		if not is_instance_valid(player):
			break
		
		if player.has_method("inject_input"):
			player.inject_input({"mouse_delta": [0, mouse_dy]})
		
		# Verify host_node is still valid before yielding
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		yield (host_node.get_tree(), "physics_frame")

func _find_player() -> Node:
	if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
		return null
	var player = host_node.get_tree().get_root().find_node("Pilot", true, false)
	return player

func _resolve_node(path: String) -> Node:
	var node = host_node.get_node_or_null(path)
	if not node and host_node.is_inside_tree() and host_node.get_tree().current_scene:
		node = host_node.get_tree().current_scene.find_node(path, true, false)
	if not node and host_node.is_inside_tree():
		node = host_node.get_tree().root.find_node(path, true, false)
	return node

func _wait_signal(target: Node, signal_name: String, timeout: float, my_id: int):
	var observer = SignalObserver.new()
	target.connect(signal_name, observer, "on_signal")

	var timer = host_node.get_tree().create_timer(timeout)
	while not observer.triggered and timer.time_left > 0:
		if stop_requested or my_id != execution_id:
			break
		yield (host_node.get_tree(), "physics_frame")

	var success = observer.triggered
	if is_instance_valid(target) and target.is_connected(signal_name, observer, "on_signal"):
		target.disconnect(signal_name, observer, "on_signal")

	observer.free()
	return success

func _execute_assert(condition: String):
	var parts = condition.split(" ", false)
	if parts.size() < 3:
		return

	var left = _resolve_value(parts[0])
	var op = parts[1]
	var right = _resolve_value(parts[2])
	var msg = "Assertion failed"
	if condition.find("\"") != -1:
		msg = condition.substr(condition.find("\"")).replace("\"", "")

	if not _compare(left, op, right):
		printerr("[OYS ASSERT] FAILED: ", msg, " (", left, " ", op, " ", right, ")")
		is_running = false

class SignalObserver extends Object:
	var triggered = false
	func on_signal(_a = null, _b = null, _c = null, _d = null, _e = null):
		triggered = true

func _resolve_value(val: String):
	if val.begins_with("$"):
		return variables.get(val, 0)
	if val.is_valid_float():
		return val.to_float()
	return val.replace("\"", "")

func _call_func(func_name: String, args: Array):
	match func_name:
		"GET_NODE_POS_Y":
			var path = args[0].replace("\"", "")
			var node = _resolve_node(path)
			if node and node is Spatial:
				return node.global_transform.origin.y
			elif node and node is Node2D:
				return node.position.y
	return 0.0

func _compare(left, op, right) -> bool:
	var l = left
	var r = right
	if str(l).is_valid_float() and str(r).is_valid_float():
		l = float(l)
		r = float(r)

	match op:
		"==": return l == r
		"!=": return l != r
		">": return l > r
		"<": return l < r
		">=": return l >= r
		"<=": return l <= r
	return false
