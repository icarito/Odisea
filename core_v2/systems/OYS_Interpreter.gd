# core_v2/systems/OYS_Interpreter.gd
extends Reference

class_name OYS_Interpreter

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

	var lines = script_content.split("\n")
	var processed_lines = []

	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if line == "" or line.begins_with("//"):
			continue
		processed_lines.append(line)

	for i in range(processed_lines.size()):
		var line = processed_lines[i]
		var inst = _parse_instruction(line)
		if inst.empty(): continue

		if inst.command == "SECTION":
			var section_name = inst["name"]
			sections[section_name] = i
			section_names.append(section_name)

		instructions.append(inst)

func _parse_instruction(line: String) -> Dictionary:
	var parts = line.split(" ", false)
	var cmd = parts[0].to_upper()
	var data = {"command": cmd, "raw": line}

	match cmd:
		"SECTION":
			data["name"] = parts[1].replace("\"", "")
		"GOTO":
			data["target"] = parts[1].replace("\"", "")
		"IF":
			# IF $variable OP value GOTO "nombre"
			data["left"] = parts[1]
			data["op"] = parts[2]
			data["right"] = parts[3]
			# parts[4] should be "GOTO"
			data["target"] = parts[5].replace("\"", "")
		"PLAY_ANIM":
			data["path"] = parts[1].replace("\"", "")
			data["anim"] = parts[2].replace("\"", "")
			if parts.size() > 3:
				data["blend"] = parts[3].to_float()
		"WAIT_ANIM":
			data["path"] = parts[1].replace("\"", "")
		"ASSERT_SIGNAL":
			data["signal"] = parts[1].replace("\"", "")
			data["timeout"] = parts[2].to_float()
			# Optional: node path if not on host
			if parts.size() > 3:
				data["path"] = parts[3].replace("\"", "")
		"SPAWN":
			data["scene"] = parts[1].replace("\"", "")
			# SPAWN "path" AT (x,y,z)
			if parts.size() > 3 and parts[2].to_upper() == "AT":
				data["pos"] = line.substr(line.find("("))
		"SET_TIME_SCALE":
			data["value"] = parts[1].to_float()
		"WAIT":
			data["value"] = parts[1].to_float()
		"PRINT":
			data["message"] = line.substr(line.find(" ") + 1).replace("\"", "")
		"ASSERT":
			data["condition"] = line.substr(line.find(" ") + 1)
		"SET":
			data["var"] = parts[1]
			if parts.size() > 3:
				data["func"] = parts[2]
				var args_array = []
				for j in range(3, parts.size()):
					args_array.append(parts[j])
				data["args"] = args_array
			else:
				data["value"] = parts[2]
		"GET_NODES_IN_GROUP":
			data["group"] = parts[1].replace("\"", "")
			data["target"] = parts[3] # AS $var
	return data

func run(start_section: String = ""):
	execution_id += 1
	var my_id = execution_id

	if is_running:
		stop_requested = true
		yield(host_node.get_tree(), "idle_frame")

	is_running = true
	stop_requested = false

	if start_section != "" and sections.has(start_section):
		pc = sections[start_section]
	else:
		pc = 0

	while pc < instructions.size() and not stop_requested and my_id == execution_id:
		var inst = instructions[pc]
		pc += 1
		var result = _execute_instruction(inst, my_id)
		if result is GDScriptFunctionState:
			yield(result, "completed")

	if my_id == execution_id:
		is_running = false

func _execute_instruction(inst: Dictionary, my_id: int):
	match inst.command:
		"SECTION":
			pass # Already indexed
		"GOTO":
			if sections.has(inst.target):
				pc = sections[inst.target]
			else:
				printerr("[OYS] GOTO target not found: ", inst.target)
		"IF":
			var left = _resolve_value(inst.left)
			var right = _resolve_value(inst.right)
			if _compare(left, inst.op, right):
				if sections.has(inst.target):
					pc = sections[inst.target]
				else:
					printerr("[OYS] IF GOTO target not found: ", inst.target)
		"PLAY_ANIM":
			var node = _resolve_node(inst.path)
			if node and node is AnimationPlayer:
				var blend = inst.get("blend", -1.0)
				node.play(inst.anim, blend)
		"WAIT_ANIM":
			var node = _resolve_node(inst.path)
			if node and node is AnimationPlayer:
				if node.is_playing():
					yield(node, "animation_finished")
		"ASSERT_SIGNAL":
			var target_path = inst.get("path", "")
			var target = host_node
			if target_path != "":
				target = _resolve_node(target_path)

			if target:
				var success = yield(_wait_signal(target, inst.signal, inst.timeout, my_id), "completed")
				if not success:
					printerr("[OYS] ASSERT_SIGNAL failed: ", inst.signal, " on ", target.name)
		"SPAWN":
			var scene = load(inst.scene)
			if scene:
				var obj = scene.instance()
				host_node.get_tree().current_scene.add_child(obj)
				if inst.has("pos") and obj is Spatial:
					obj.global_transform.origin = _parse_vector3(inst.pos)
		"SET_TIME_SCALE":
			Engine.time_scale = inst.value
		"WAIT":
			var t = host_node.get_tree().create_timer(inst.value)
			while t.time_left > 0:
				if stop_requested or my_id != execution_id: break
				yield(host_node.get_tree(), "idle_frame")
		"PRINT":
			print("[OYS PRINT] ", inst.message)
		"ASSERT":
			_execute_assert(inst.condition)
		"SET":
			if inst.has("func"):
				variables[inst.var] = _call_func(inst.func, inst.args)
			else:
				variables[inst.var] = _resolve_value(inst.value)
		"GET_NODES_IN_GROUP":
			variables[inst.target] = host_node.get_tree().get_nodes_in_group(inst.group).size()
	return null

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
		if stop_requested or my_id != execution_id: break
		yield(host_node.get_tree(), "idle_frame")

	var success = observer.triggered
	if is_instance_valid(target) and target.is_connected(signal_name, observer, "on_signal"):
		target.disconnect(signal_name, observer, "on_signal")

	observer.free()
	return success

func _parse_vector3(s: String) -> Vector3:
	var cleaned = s.replace("(", "").replace(")", "").strip_edges()
	var components = cleaned.split(",")
	if components.size() >= 3:
		return Vector3(components[0].to_float(), components[1].to_float(), components[2].to_float())
	return Vector3.ZERO

func _execute_assert(condition: String):
	# Very basic assert evaluation
	var parts = condition.split(" ", false)
	if parts.size() < 3:
		# Maybe it's just a message? No, message comes after.
		pass

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
	func on_signal(a=null, b=null, c=null, d=null, e=null):
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
	# Try to convert to float if possible for numeric comparison
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
