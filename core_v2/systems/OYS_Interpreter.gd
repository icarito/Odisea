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
		
		"CALL":
			var node = host_node
			if inst.has("node"):
				node = _resolve_node(inst.node)

			if node and inst.has("method"):
				var args = inst.get("args", [])
				# Resolve args
				var resolved_args = []
				for a in args:
					resolved_args.append(_resolve_value(a))

				if node.has_method(inst.method):
					node.callv(inst.method, resolved_args)
				else:
					printerr("[OYS] CALL failed: Method %s not found on %s" % [inst.method, node.name])

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
			yield (VisualServer, "frame_post_draw")
			var img = host_node.get_viewport().get_texture().get_data()
			img.flip_y()
			var path = inst.get("path", "res://screenshot.png")
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
			move_vec = Vector2(1, 0) if cmd == "LEFT" else Vector2(-1, 0)
		
		"JUMP":
			duration_sec = inst.get("duration", 0.1)
			is_jump = true
		
		"INTERACT":
			duration_sec = 1.0 / 60.0 # One frame
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
	if is_instance_valid(node): return node

	if host_node.is_inside_tree():
		var scene = host_node.get_tree().current_scene
		if scene:
			node = scene.get_node_or_null(path)
			if is_instance_valid(node): return node

			node = scene.find_node(path, true, false)
			if is_instance_valid(node): return node

		node = host_node.get_tree().root.find_node(path, true, false)
		if is_instance_valid(node): return node

	return null

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

func _resolve_value(val: String):
	if val.begins_with("$"):
		return variables.get(val, 0)
	if val.is_valid_float():
		return val.to_float()

	if "." in val and not val.is_valid_float():
		var parts = val.split(".")
		var node_name = parts[0]
		if node_name in ["pos", "yaw_deg"]:
			pass # Handle later in player section
		else:
			var prop_path = val.substr(node_name.length() + 1)
			var node = _resolve_node(node_name)
			if node:
				var res = node.get_indexed(prop_path.replace(".", ":"))
				return res
			else:
				pass

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
	if val == "true": return true
	if val == "false": return false
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
