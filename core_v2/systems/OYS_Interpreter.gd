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
var test_failed: bool = false # Global flag to track test failure
var loop_runtime_stack: Array = [] # Runtime stack for loops
signal instruction_executed(inst, variables)
signal instruction_completed(inst, variables)

func _init(host: Node):
	host_node = host

func parse(script_content: String):
	instructions.clear()
	sections.clear()
	section_names.clear()
	pc = 0

	var lines = OYS_Parser.preprocess(script_content)
	var loop_stack = [] # Stack of indices for open loops
	
	for i in range(lines.size()):
		var line = lines[i]
		var inst = OYS_Parser.parse_instruction(line)
		if inst.empty():
			continue

		if inst.command == "SECTION":
			var section_name = inst.get("name", "")
			sections[section_name] = instructions.size()
			section_names.append(section_name)

		# Loop linking logic
		if inst.command == "FOR" or inst.command == "WHILE":
			loop_stack.push_back(instructions.size())

		elif inst.command == "ENDFOR":
			if loop_stack.empty():
				printerr("[OYS_Interpreter] ENDFOR without matching FOR at line ", i)
			else:
				var start_idx = loop_stack.pop_back()
				var start_inst = instructions[start_idx]
				if start_inst.command != "FOR":
					printerr("[OYS_Interpreter] Mismatched loop: ENDFOR matched with ", start_inst.command)
				else:
					start_inst["end_index"] = instructions.size()
					inst["start_index"] = start_idx

		elif inst.command == "ENDWHILE":
			if loop_stack.empty():
				printerr("[OYS_Interpreter] ENDWHILE without matching WHILE at line ", i)
			else:
				var start_idx = loop_stack.pop_back()
				var start_inst = instructions[start_idx]
				if start_inst.command != "WHILE":
					printerr("[OYS_Interpreter] Mismatched loop: ENDWHILE matched with ", start_inst.command)
				else:
					start_inst["end_index"] = instructions.size()
					inst["start_index"] = start_idx

		instructions.append(inst)

	if not loop_stack.empty():
		printerr("[OYS_Interpreter] Unclosed loops at end of script: ", loop_stack.size())

func run(start_section: String = ""):
	execution_id += 1
	var my_id = execution_id

	if is_running:
		stop_requested = true
		if host_node and is_instance_valid(host_node) and host_node.is_inside_tree():
			yield (host_node.get_tree(), "physics_frame")

	is_running = true
	stop_requested = false
	loop_runtime_stack.clear()

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
		emit_signal("instruction_completed", inst, variables)

	if my_id == execution_id:
		is_running = false
		var session = host_node.get_node_or_null("/root/SessionManager")
		if session and is_instance_valid(session):
			session.set("_oys_input_override", {})

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

	while pc < instructions.size() and not stop_requested and my_id == execution_id:
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		var inst = instructions[pc]
		pc += 1
		var result = _execute_instruction(inst, my_id)
		if result is GDScriptFunctionState:
			yield (result, "completed")
		emit_signal("instruction_completed", inst, variables)

	if my_id == execution_id:
		is_running = false
		var session = host_node.get_node_or_null("/root/SessionManager")
		if session and is_instance_valid(session):
			session.set("_oys_input_override", {})

func _execute_instruction(inst: Dictionary, my_id: int):
	var cmd = inst.command
	emit_signal("instruction_executed", inst, variables)
	
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
					test_failed = true
					stop_requested = true
					return

		"LOAD_PROP":
			var path = inst.get("path", "")
			# Resolve variable if path starts with $
			if path.begins_with("$"):
				var resolved = _resolve_value(path)
				if typeof(resolved) == TYPE_STRING:
					path = resolved
				else:
					printerr("[OYS ERROR] LOAD_PROP path variable resolved to non-string: ", resolved)
			
			var result = null
			if host_node.has_method("load_prop"):
				result = host_node.load_prop(path)
			elif host_node.is_inside_tree():
				var stage = host_node.get_tree().current_scene
				if not stage or not stage.has_method("load_prop"):
					# Fallback search for PropStage
					var root = host_node.get_tree().root
					for i in range(root.get_child_count()):
						var c = root.get_child(i)
						if (c.name == "PropStage" or c.name == "PropStage.tscn") and c.has_method("load_prop"):
							stage = c
							break
				
				if stage and stage.has_method("load_prop"):
					result = stage.load_prop(path)
				else:
					printerr("[OYS_Interpreter] Could not find valid stage with load_prop")
			else:
				printerr("[OYS] LOAD_PROP called but host_node '%s' lacks 'load_prop' method and current_scene doesn't support it either." % host_node.name)
			
			if result is GDScriptFunctionState:
				yield (result, "completed")
		
		"CALL":
			var method = inst.get("method", "")
			var args = inst.get("args", [])
			var resolved_args = []
			for a in args:
				resolved_args.append(_resolve_value(a))
			
			var target = _resolve_prop() # Try prop first
			if not target or not target.has_method(method):
				# Try PropStage / Current Scene
				var stage = _resolve_stage()
				if stage and stage != target and stage.has_method(method):
					target = stage
				else:
					target = host_node # Fallback to host
			
			if target and target.has_method(method):
				var result = target.callv(method, resolved_args)
				if result is GDScriptFunctionState:
					yield (result, "completed")
			else:
				# Don't fail the test immediately, just warn
				printerr("[OYS] CALL failed: Method '%s' not found on %s" % [method, target.name])

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
			var message = inst.get("message", "")
			message = _substitute_variables(message)
			print("[OYS PRINT] ", message)
			
		"SCREENSHOT":
			var label = inst.get("label", "screenshot")
			var prop_name = "unknown"
			var prop = _resolve_prop()
			if prop:
				prop_name = prop.name

			# Hook for custom screenshot logic (e.g. Editor PropStage)
			var path = ""
			if host_node.has_method("take_oys_screenshot"):
				var result = yield (host_node.take_oys_screenshot(label, prop_name), "completed")
				if result and result is String:
					path = result
			else:
				# Default Runtime Logic
				yield (VisualServer, "frame_post_draw")
				var img = host_node.get_viewport().get_texture().get_data()
				img.flip_y()
				
				var dir = Directory.new()
				var base_dir = "res://test_output/props/"
				if not dir.dir_exists(base_dir):
					dir.make_dir_recursive(base_dir)
				
				path = base_dir + "%s_%s.png" % [prop_name, label]
				img.save_png(path)
				print("[OYS] Screenshot saved to: ", path)
		
		"CINEMATIC_START":
			var rig_id = inst.get("rig_id", "")
			var mode_str = inst.get("mode", "FREE")
			var mode = CinematicManager.ControlMode.FREE
			match mode_str:
				"FREE": mode = CinematicManager.ControlMode.FREE
				"SIDESCROLL": mode = CinematicManager.ControlMode.SIDESCROLL
				"LOCKED_VIEW": mode = CinematicManager.ControlMode.LOCKED_VIEW
				"FIXED_AXIS": mode = CinematicManager.ControlMode.FIXED_AXIS

			CinematicManager.activate_rig(rig_id, mode)

		"CINEMATIC_STOP":
			CinematicManager.deactivate_rig()

		"RECORD_START":
			var recorder = _find_recorder()
			if recorder:
				recorder.start_recording()
			else:
				# Instantiate one if not found
				var FrameRecorder = load("res://core_v2/systems/FrameRecorder.gd")
				var new_recorder = FrameRecorder.new()
				new_recorder.name = "FrameRecorder"
				host_node.get_tree().root.add_child(new_recorder)
				new_recorder.start_recording()

		"RECORD_STOP":
			var recorder = _find_recorder()
			if recorder:
				recorder.stop_recording()

		"ASSERT":
			_execute_assert(inst.get("condition", ""))
			if not is_running:
				test_failed = true # Mark the test as failed
				stop_requested = true
				return # Stop execution immediately on ASSERT failure

		"SET":
			var var_name = inst.get("var", "")
			if inst.has("func"):
				variables[var_name] = _call_func(inst.func, inst.args)
			else:
				variables[var_name] = _resolve_value(inst.get("value", ""))

			# If it's a world property (like 'pos'), tell the host to handle it
			if not var_name.begins_with("$"):
				if host_node and host_node.has_method("_handle_set_command"):
					host_node._handle_set_command(inst)
		
		"GET_NODES_IN_GROUP":
			var group = inst.get("group", "")
			var target_var = inst.get("target", "")
			variables[target_var] = host_node.get_tree().get_nodes_in_group(group).size()
		
		# Movement commands - apply to player's input provider
		"FW", "BW", "LEFT", "RIGHT", "JUMP", "INTERACT":
			var __state = _execute_movement(inst, my_id)
			if __state is GDScriptFunctionState:
				yield (__state, "completed")
		
		"LOOK":
			var __state_look = _execute_look(inst, my_id)
			if __state_look is GDScriptFunctionState:
				yield (__state_look, "completed")
		
		# Markers - no action needed
		"LEVEL", "END":
			pass
		
		"MATH":
			var var_name = inst.get("var", "")
			var expression = inst.get("expression", "")
			var result = 0.0
			
			var expr_parts = expression.split(" ", false)
			if expr_parts.size() == 1:
				var right_val = _resolve_value(expr_parts[0])
				var op = inst.get("op", "")
				
				# Support in-place modification: MATH $x + 5
				if op in ["+", "-", "*", "/"]:
					var left_val = variables.get(var_name, 0.0)
					match op:
						"+": result = float(left_val) + float(right_val)
						"-": result = float(left_val) - float(right_val)
						"*": result = float(left_val) * float(right_val)
						"/": if float(right_val) != 0: result = float(left_val) / float(right_val)
				else:
					# Simple assignment: MATH $x 5 (Wait, parser treats 2nd arg as OP?)
					# If op is not a math op, treat strictly as assignment?
					# But Parser logic puts 3rd token as OP. 
					# MATH $x = 5 -> op="=".
					result = right_val
			
			elif expr_parts.size() == 3:
				var left = _resolve_value(expr_parts[0])
				var inner_op = expr_parts[1]
				var right = _resolve_value(expr_parts[2])
				match inner_op:
					"+": result = float(left) + float(right)
					"-": result = float(left) - float(right)
					"*": result = float(left) * float(right)
					"/": if float(right) != 0: result = float(left) / float(right)
			
			variables[var_name] = result
		
		"GET_POS":
			var player = _find_player()
			if player and is_instance_valid(player):
				var pos = Vector3.ZERO
				if player is Spatial:
					pos = player.global_transform.origin
				elif player is Node2D:
					pos = Vector3(player.position.x, player.position.y, 0)
				
				if inst.has("x"): variables[inst.x] = pos.x
				if inst.has("y"): variables[inst.y] = pos.y
				if inst.has("z"): variables[inst.z] = pos.z

		"FOR":
			var current_pc = pc - 1
			var iterations = int(inst.get("iterations", 1))

			if loop_runtime_stack.empty() or loop_runtime_stack.back().get("start_pc") != current_pc:
				# Start new loop
				if iterations > 0:
					loop_runtime_stack.push_back({
						"type": "FOR",
						"start_pc": current_pc,
						"remaining": iterations - 1
					})
				else:
					# Skip loop entirely
					var end_index = inst.get("end_index", -1)
					if end_index != -1:
						pc = end_index + 1
			else:
				# Continue existing loop
				var context = loop_runtime_stack.back()
				if context.remaining > 0:
					context.remaining -= 1
				else:
					# Finished
					loop_runtime_stack.pop_back()
					var end_index = inst.get("end_index", -1)
					if end_index != -1:
						pc = end_index + 1

		"ENDFOR":
			# Jump back to start
			var start_index = inst.get("start_index", -1)
			if start_index != -1:
				pc = start_index

		"WHILE":
			# Check condition
			var condition_met = false

			if inst.has("prop_type") and inst.prop_type == "PROP":
				# WHILE PROP "Door" is_active == false
				var target_name = inst.get("target", "")
				var prop_name = inst.get("property", "")
				var op = inst.get("op", "==")
				var expected_val = _resolve_value(inst.get("value", ""))

				# Find prop
				var prop = null
				if target_name == "current_prop":
					prop = _resolve_prop()
				else:
					prop = _resolve_node(target_name)

				if prop:
					var actual_val = null
					if prop_name in prop:
						actual_val = prop.get(prop_name)
					elif prop.has_method("get_" + prop_name):
						actual_val = prop.call("get_" + prop_name)

					condition_met = _compare(actual_val, op, expected_val)
				else:
					printerr("[OYS_Interpreter] WHILE PROP: Target not found: ", target_name)
					condition_met = false
			else:
				# Generic condition
				var left = _resolve_value(inst.get("left", ""))
				var right = _resolve_value(inst.get("right", ""))
				var op = inst.get("op", "==")
				condition_met = _compare(left, op, right)

			if not condition_met:
				# Jump to end
				var end_index = inst.get("end_index", -1)
				if end_index != -1:
					pc = end_index + 1
				else:
					printerr("[OYS_Interpreter] WHILE without ENDWHILE linked")

		"ENDWHILE":
			# Jump back to start
			var start_index = inst.get("start_index", -1)
			if start_index != -1:
				pc = start_index
	
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
			# Working convention: 1 is Forward, -1 is Backward
			move_vec = Vector2(0, 1) if cmd == "FW" else Vector2(0, -1)
		
		"LEFT", "RIGHT":
			if inst.get("is_turning", false):
				# For turning, we'll handle it separately
				var __state_turn = _execute_turn(inst, my_id)
				if __state_turn is GDScriptFunctionState:
					yield (__state_turn, "completed")
				return
			var value = inst.get("value", 0.0)
			var unit = inst.get("unit", "s")
			duration_sec = value
			if unit == "m":
				duration_sec = OYS_Parser.distance_to_duration(value, is_sprint)
			# Working convention: 1 is Left, -1 is Right
			move_vec = Vector2(1, 0) if cmd == "LEFT" else Vector2(-1, 0)
		
		"JUMP":
			duration_sec = inst.get("duration", 0.1)
			is_jump = true
		
		"INTERACT":
			var target_name = inst.get("target", "")
			if target_name != "":
				# Direct interaction with a specific named prop/node
				# This bypasses player input injection validation
				var target_node = null
				
				# Try resolving as prop first if it matches "prop" or similar keyword, 
				# otherwise find by name
				if target_name == "prop" or target_name == "current_prop":
					target_node = _resolve_prop()
				else:
					# Try to find part of the prop? or just a global search
					# For now, let's assume it's a node name in the scene
					target_node = host_node.find_node(target_name, true, false)
				
				if target_node:
					if target_node.has_method("interact"):
						print("[OYS] Direct INTERACT with ", target_node.name)
						target_node.interact()
					else:
						print("[OYS WARNING] Target ", target_node.name, " has no interact() method.")
				else:
					print("[OYS WARNING] Could not find target '", target_name, "' for INTERACT.")
				
				# Wait one frame and return (no input injection)
				yield (host_node.get_tree(), "physics_frame")
				return
			else:
				# Default: Inject Input to Player
				duration_sec = 1.0 / 60.0
				is_interact = true
	
	var num_frames = OYS_Parser.duration_to_frames(duration_sec)
	for _i in range(num_frames):
		if stop_requested or my_id != execution_id:
			break
		if not is_instance_valid(player):
			break
		_post_oys_input({
			"move_vec": [move_vec.x, move_vec.y],
			"sprint": is_sprint,
			"jump": is_jump,
			"interact": is_interact
		})
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		yield (host_node.get_tree(), "physics_frame")

	_post_oys_input({
		"move_vec": [0.0, 0.0],
		"sprint": false,
		"jump": false,
		"interact": false
	})

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
		
		_post_oys_input({"mouse_delta": [mouse_dx, 0]})
		
		# Verify host_node is still valid before yielding
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		yield (host_node.get_tree(), "physics_frame")
	
	# Clear turn input after finishing
	_post_oys_input({
		"mouse_delta": [0.0, 0.0]
	})

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
		
		_post_oys_input({"mouse_delta": [0, mouse_dy]})
		
		# Verify host_node is still valid before yielding
		if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
			break
		yield (host_node.get_tree(), "physics_frame")
	
	# Clear look input after finishing
	_post_oys_input({
		"mouse_delta": [0.0, 0.0]
	})

func _find_recorder() -> Node:
	if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
		return null
	return host_node.get_tree().root.find_node("FrameRecorder", true, false)

func _find_player() -> Node:
	if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
		return null
	# Prefer SessionManager.player if available (avoids stale/name-based lookups)
	var session = host_node.get_node_or_null("/root/SessionManager")
	if session and is_instance_valid(session):
		if session.has_method("get"):
			var p = session.get("player")
			if p and is_instance_valid(p):
				return p

	# Fallback: find by name in the scene tree
	var player = host_node.get_tree().get_root().find_node("Pilot", true, false)
	return player

func _post_oys_input(data: Dictionary):
	if not host_node or not is_instance_valid(host_node) or not host_node.is_inside_tree():
		return
	var session = host_node.get_node_or_null("/root/SessionManager")
	if session and is_instance_valid(session) and session.get("is_recording"):
		if not session.get("_oys_input_override"):
			session.set("_oys_input_override", {})
		var override = session.get("_oys_input_override")
		for key in data:
			override[key] = data[key]
	else:
		var player = _find_player()
		if player and is_instance_valid(player) and player.has_method("inject_input"):
			player.inject_input(data)

func _resolve_node(path: String) -> Node:
	var node = host_node.get_node_or_null(path)
	if not is_instance_valid(node) and host_node.is_inside_tree() and host_node.get_tree().current_scene:
		node = host_node.get_tree().current_scene.find_node(path, true, false)
	if not is_instance_valid(node) and host_node.is_inside_tree():
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

	# yield (host_node.get_tree(), "physics_frame") # Removed to ensure synchronous execution
	var left = _resolve_value(parts[0])
	var op = parts[1]
	var right = _resolve_value(parts[2])
	var msg = "Assertion failed"
	if condition.find("\"") != -1:
		msg = condition.substr(condition.find("\"")).replace("\"", "")

		if not _compare(left, op, right):
			printerr("[OYS ASSERT] FAILED: ", msg, " (", left, " ", op, " ", right, ")")
			test_failed = true
			stop_requested = true
			is_running = false

class SignalObserver extends Object:
	var triggered = false
	func on_signal(_a = null, _b = null, _c = null, _d = null, _e = null):
		triggered = true

func _resolve_stage() -> Node:
	# Try identifying PropStage explicitly in the tree first
	var root = host_node.get_tree().root
	var stage = root.find_node("PropStage", true, false)
	if stage:
		return stage
		
	# Try current scene
	stage = host_node.get_tree().current_scene
	if stage and (stage.name == "PropStage" or stage.has_method("load_prop")):
		return stage

	# If host_node is a stage/host itself
	if host_node.has_method("load_prop") and host_node.name != "SessionManager":
		return host_node
		
	return null

func _resolve_prop() -> Node:
	var stage = _resolve_stage()
	if stage and "current_prop" in stage:
		if is_instance_valid(stage.current_prop):
			return stage.current_prop
		
	return null
func _resolve_value(val: String):
	if val.begins_with("$"):
		return variables.get(val, 0)
	if val.is_valid_float():
		return val.to_float()
	if val in ["pos.y", "pos.x", "pos.z"]:
		# Obtener el nodo jugador principal
		var player = null
		var session = host_node.get_node_or_null("/root/SessionManager")
		if session and session.player:
			player = session.player
		if not player:
			player = host_node.get_tree().root.find_node("Pilot", true, false)
		if not is_instance_valid(player):
			printerr("[OYS ERROR] Player instance is invalid or freed when resolving ", val)
			test_failed = true
			stop_requested = true
			return null
		if player is Spatial:
			match val:
				"pos.x": return player.global_transform.origin.x
				"pos.y": return player.global_transform.origin.y
				"pos.z": return player.global_transform.origin.z
		elif player is Node2D:
			match val:
				"pos.x": return player.position.x
				"pos.y": return player.position.y
				"pos.z": return 0.0
		return 0.0
	if val == "yaw_deg":
		# Buscar variable yaw_deg en el jugador
		var player = null
		var session = host_node.get_node_or_null("/root/SessionManager")
		if session and session.player:
			player = session.player
		if not player:
			player = host_node.get_tree().root.find_node("Pilot", true, false)
		if not is_instance_valid(player):
			printerr("[OYS ERROR] Player instance is invalid or freed when resolving yaw_deg")
			test_failed = true
			stop_requested = true
			return null
		
		# Preferir propiedad directa del script del jugador
		if "yaw_deg" in player:
			return player.yaw_deg
		elif player.has_method("get_yaw_deg"):
			return player.get_yaw_deg()
			
		# Fallback a pivote si no existe la propiedad (legacy)
		if player.has_node("CameraPivot"):
			var cam_pivot = player.get_node("CameraPivot")
			if not is_instance_valid(cam_pivot):
				return 0.0
			var yaw = cam_pivot.rotation.y
			return rad2deg(yaw)
		return 0.0
	if val == "true": return true
	if val == "false": return false
	return val.replace("\"", "")

func _call_func(func_name: String, args: Array):
	match func_name:
		"GET_NODE_POS_X":
			var node = host_node.get_tree().root.find_node(args[0], true, false)
			if node:
				return node.global_transform.origin.x
			return 0.0
		"GET_NODE_POS_Y":
			var path = args[0].replace("\"", "")
			var node = _resolve_node(path)
			if node and node is Spatial:
				return node.global_transform.origin.y
			elif node and node is Node2D:
				return node.position.y
			return 0.0
		"GET_NODE_Z", "GET_NODE_POS_Z":
			var path = args[0].replace("\"", "")
			# Prefer SessionManager.player when path is the Pilot alias to ensure we
			# query the active player instance rather than a stale or name-colliding node.
			var node = null
			if path == "Pilot":
				var session_pref = host_node.get_node_or_null("/root/SessionManager")
				if session_pref and is_instance_valid(session_pref) and session_pref.has_method("get"):
					var p_pref = session_pref.get("player")
					if p_pref and is_instance_valid(p_pref):
						node = p_pref
			# Fallback to regular resolution
			if not node:
				node = _resolve_node(path)
			if not node:
				# Fallback: try SessionManager.player if available
				var session = host_node.get_node_or_null("/root/SessionManager")
				if session and is_instance_valid(session):
					if session.has_method("_find_player"):
						session._find_player()
					var p = session.get("player")
					if p and is_instance_valid(p):
						node = p
			if node and node is Spatial:
				return node.global_transform.origin.z
			return 0.0
		_:
			printerr("[OYS] Unknown function called: ", func_name)
			test_failed = true
			stop_requested = true
			return null

func _compare(left, op, right) -> bool:
		   var l = left
		   var r = right
		   var l_is_float = str(l).is_valid_float()
		   var r_is_float = str(r).is_valid_float()
		   if l_is_float and r_is_float:
			   l = float(l)
			   r = float(r)
		   else:
			   l = str(l)
			   r = str(r)

		   match op:
			   "==": return l == r
			   "!=": return l != r
			   ">": return l > r
			   "<": return l < r
			   ">=": return l >= r
			   "<=": return l <= r
		   return false

func _substitute_variables(message: String) -> String:
	var result = message
	for var_name in variables.keys():
		var pos = result.find(var_name)
		if pos != -1:
			var value = str(variables[var_name])
			result = result.substr(0, pos) + value + result.substr(pos + var_name.length())
	return result
