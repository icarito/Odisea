# core_v2/systems/OYS_Parser.gd
# Shared parsing logic for OYS scripts - used by both Resolver and Interpreter
extends Reference

class_name OYS_Parser

const FPS = 60.0

# Supported commands enum for type safety
enum Command {
	UNKNOWN,
	SECTION, END, LEVEL,
	FW, BW, LEFT, RIGHT, JUMP, INTERACT,
	WAIT, LOOK, CALL,
	SET, ASSERT, ASSERT_SIGNAL, PRINT,
	GOTO, IF,
	PLAY_ANIM, WAIT_ANIM, SPAWN,
	SET_TIME_SCALE, GET_NODES_IN_GROUP,
	SCREENSHOT, LOAD_PROP,
	CINEMATIC_START, CINEMATIC_STOP,
	RECORD_START, RECORD_STOP,
	GET_POS,
	CINEMATIC,
	INTERACTIVE,
}

# Command synonyms mapping
const SYNONYMS = {
	"FORWARD": "FW",
	"BACKWARD": "BW",
	"LT": "LEFT",
	"RT": "RIGHT",
	"TIME_SCALE": "SET_TIME_SCALE"
}

# Preprocess script: remove comments and empty lines
static func preprocess(script_content: String) -> PoolStringArray:
	var lines = PoolStringArray()
	for line in script_content.split("\n"):
		var stripped = line.strip_edges()
		if stripped.empty(): continue

		# Handle comments: strip everything after #
		# This also handles shebangs (lines starting with #!)
		var comment_idx = stripped.find("#")
		if comment_idx != -1:
			stripped = stripped.substr(0, comment_idx).strip_edges()

		# Handle // comments (legacy support)
		var slash_idx = stripped.find("//")
		if slash_idx != -1:
			stripped = stripped.substr(0, slash_idx).strip_edges()

		if stripped.empty():
			continue
		lines.append(stripped)
	return lines

# Parse a single line into an instruction dictionary
static func parse_instruction(line: String) -> Dictionary:
	var parts = line.split(" ", false)
	if parts.empty():
		return {}
	
	var cmd = parts[0].to_upper()
	
	# Apply synonyms
	if SYNONYMS.has(cmd):
		cmd = SYNONYMS[cmd]
	
	var data = {"command": cmd, "raw": line, "parts": parts}
	
	match cmd:
		"SECTION":
			data["name"] = _extract_quoted(parts, 1)
		
		"LEVEL":
			data["path"] = parts[1] if parts.size() > 1 else ""
		
		"GOTO":
			data["target"] = _extract_quoted(parts, 1)
		
		"IF":
			# IF $variable OP value GOTO "nombre"
			if parts.size() >= 6:
				data["left"] = parts[1]
				data["op"] = parts[2]
				data["right"] = parts[3]
				data["target"] = _extract_quoted(parts, 5)
		
		"FW", "BW":
			var parsed = _parse_movement(parts, cmd)
			data.merge(parsed, true)
		
		"LEFT", "RIGHT":
			var parsed = _parse_strafe_or_turn(parts, cmd)
			data.merge(parsed, true)
		
		"JUMP":
			data["duration"] = 0.1
			if parts.size() > 1 and parts[1].to_upper() != "AT":
				data["duration"] = parts[1].to_float()
		
		"INTERACT":
			for i in range(1, parts.size()):
				if parts[i].begins_with("target="):
					data["target"] = parts[i].split("=")[1]
		
		"WAIT":
			data["value"] = parts[1].to_float() if parts.size() > 1 else 0.0
		
		"LOOK":
			data["pitch"] = parts[1].to_float() if parts.size() > 1 else 0.0
			data["duration"] = 0.5
		
		"CALL":
			data["method"] = ""
			var args = []
			for j in range(1, parts.size()):
				var p = parts[j]
				if p.begins_with("method="):
					data["method"] = p.split("=")[1].replace("\"", "")
				elif p.begins_with("args="):
					# Very basic JSON-like array parsing [a,b,c]
					var arr_str = p.split("=")[1].replace("[", "").replace("]", "").replace("\"", "")
					if arr_str != "":
						for a in arr_str.split(","):
							args.append(a.strip_edges())
				else:
					# Legacy positional argument or method name without method=
					if data["method"] == "":
						data["method"] = p.replace("\"", "")
					else:
						args.append(p.replace("\"", ""))
			data["args"] = args
		
		"SET":
			data["var"] = parts[1] if parts.size() > 1 else ""
			if parts.size() > 3 and parts[2].to_upper() != "AS" and not parts[2].begins_with("("):
				data["func"] = parts[2]
				var args = []
				for j in range(3, parts.size()):
					args.append(parts[j].replace("\"", ""))
				data["args"] = args
			else:
				var start_idx = 2
				if parts.size() > 2 and parts[2].to_upper() == "AS":
					start_idx = 3
				
				if parts.size() > start_idx:
					var value = ""
					for j in range(start_idx, parts.size()):
						value += parts[j] + " "
					data["value"] = value.strip_edges()
		
		"ASSERT":
			data["condition"] = line.substr(line.find(" ") + 1)
		
		"ASSERT_SIGNAL":
			data["signal"] = _extract_quoted(parts, 1)
			data["timeout"] = parts[2].to_float() if parts.size() > 2 else 5.0
			if parts.size() > 3:
				data["path"] = _extract_quoted(parts, 3)
		
		"PRINT":
			data["message"] = line.substr(line.find(" ") + 1).replace("\"", "")
		
		"PLAY_ANIM":
			# OYS Spec: PLAY_ANIM [path] "anim_name" [blend]
			# If only one argument, assume it is the animation name for the default target (Player)
			if parts.size() == 2:
				data["anim"] = _extract_quoted(parts, 1)
				data["path"] = ""
			else:
				data["path"] = _extract_quoted(parts, 1)
				data["anim"] = _extract_quoted(parts, 2)
				if parts.size() > 3:
					data["blend"] = parts[3].to_float()
		
		"WAIT_ANIM":
			var arg1 = _extract_quoted(parts, 1)
			# If it looks like a path (has / or is $var), treat as path.
			# Otherwise, if it's just a name, it might be an implicit wait on player?
			# Actually WAIT_ANIM usually waits for a node to finish.
			# If we want WAIT_ANIM "Confused", that's harder because we wait on a Node, not an Anim.
			# For now, let's keep WAIT_ANIM taking a NODE path.
			data["path"] = arg1
		
		"SPAWN":
			data["scene"] = _extract_quoted(parts, 1)
			if parts.size() > 3 and parts[2].to_upper() == "AT":
				data["pos"] = line.substr(line.find("("))
		
		"SET_TIME_SCALE":
			data["value"] = parts[1].to_float() if parts.size() > 1 else 1.0
		
		"GET_NODES_IN_GROUP":
			data["group"] = _extract_quoted(parts, 1)
			if parts.size() > 3:
				data["target"] = parts[3] # AS $var
		
		"END":
			pass # Marker only

		"SCREENSHOT":
			data["label"] = _extract_quoted(parts, 1)
		
		"LOAD_PROP":
			data["path"] = _extract_quoted(parts, 1)
		
		"CINEMATIC_START":
			data["rig_id"] = _extract_quoted(parts, 1)
			data["mode"] = parts[2].to_upper() if parts.size() > 2 else "FREE"

		"CINEMATIC_STOP":
			pass

		"RECORD_START":
			pass

		"RECORD_STOP":
			pass

		"RECORD_STOP":
			pass

		"CINEMATIC":
			pass
		
		"INTERACTIVE":
			pass

		"WALK", "RUN":
			# These are modifiers, handle them specially
			var is_running = (cmd == "RUN")
			if parts.size() > 1:
				var sub_cmd = parts[1].to_upper()
				if SYNONYMS.has(sub_cmd):
					sub_cmd = SYNONYMS[sub_cmd]
				data["command"] = sub_cmd
				data["is_running"] = is_running
				# Re-parse with shifted parts
				var sub_parts = Array(parts).slice(1, parts.size())
				if sub_cmd == "FW" or sub_cmd == "BW":
					var parsed = _parse_movement(sub_parts, sub_cmd)
					# DO NOT overwrite is_running if we are in a modifier
					parsed.erase("is_running")
					data.merge(parsed, true)
				elif sub_cmd == "LEFT" or sub_cmd == "RIGHT":
					var parsed = _parse_strafe_or_turn(sub_parts, sub_cmd)
					data.merge(parsed, true)
		
		"MATH":
			if parts.size() >= 4:
				data["var"] = parts[1]
				data["op"] = parts[2]
				# Store the rest of the line as expression
				var start_pos = line.find(parts[2]) + parts[2].length()
				data["expression"] = line.substr(start_pos).strip_edges()
			else:
				printerr("[OYS_Parser] Invalid MATH command: ", line)
		
		"GET_POS":
			if parts.size() > 1: data["x"] = parts[1]
			if parts.size() > 2: data["y"] = parts[2]
			if parts.size() > 3: data["z"] = parts[3]

		"FOR":
			data["iterations"] = parts[1] if parts.size() > 1 else "1"

		"ENDFOR":
			pass

		"WHILE":
			# Use custom tokenizer to respect quotes (e.g. target with spaces)
			# Skip command "WHILE"
			var first_space = line.find(" ")
			if first_space == -1:
				pass # No args
			else:
				var args_str = line.substr(first_space).strip_edges()
				var tokens = []
				var current = ""
				var in_quote = false

				for i in range(args_str.length()):
					var c = args_str[i]
					if c == '"':
						in_quote = !in_quote
						# Store quote as part of token to handle it later
						current += c
					elif c == " " and !in_quote:
						if current != "":
							tokens.append(current)
							current = ""
					else:
						current += c
				if current != "":
					tokens.append(current)

				if tokens.size() > 0:
					var type = tokens[0].to_upper()
					if type == "PROP":
						if tokens.size() >= 5:
							data["prop_type"] = "PROP"
							data["target"] = tokens[1].replace("\"", "")
							data["property"] = tokens[2]
							data["op"] = tokens[3]
							data["value"] = tokens[4].replace("\"", "")
					else:
						# Generic condition
						if tokens.size() >= 3:
							data["left"] = tokens[0].replace("\"", "")
							data["op"] = tokens[1]
							data["right"] = tokens[2].replace("\"", "")

		"ENDWHILE":
			pass
		
		_:
			data["error"] = "Unknown command: " + cmd
	
	return data

# Serialize instruction data for JSON storage
static func serialize_instruction(data: Dictionary) -> Dictionary:
	# Create a clean copy
	var clean = data.duplicate()
	# Remove internal parser fields if any
	clean.erase("raw")
	clean.erase("parts")
	return clean

# Parse movement commands (FW/BW)
# Sin unidad = segundos por defecto
static func _parse_movement(parts: Array, direction: String) -> Dictionary:
	var result = {"direction": direction}
	if parts.size() > 1:
		var parsed = _parse_value_with_unit(parts[1])
		result["value"] = parsed.value
		# Para FW/BW, "none" significa segundos
		result["unit"] = "s" if parsed.unit == "none" else parsed.unit
	return result

# Parse strafe/turn commands (LEFT/RIGHT)
# Sin unidad = rotación en grados (ej: LEFT 90)
# Con unidad m o s = strafe (ej: LEFT 5m, LEFT 2s)
static func _parse_strafe_or_turn(parts: Array, direction: String) -> Dictionary:
	var result = {"direction": direction}
	if parts.size() > 1:
		var parsed = _parse_value_with_unit(parts[1])
		result["value"] = parsed.value
		result["unit"] = parsed.unit
		# Es rotación si: tiene unidad "deg" O no tiene unidad explícita (ni m ni s)
		result["is_turning"] = (parsed.unit == "deg" or parsed.unit == "none")
	return result

# Parse value with unit suffix (e.g., "2.5s", "10m", "90deg", "90")
static func _parse_value_with_unit(s: String) -> Dictionary:
	var unit = "none" # Default: sin unidad (para LEFT/RIGHT significa grados)
	var value_str = s
	
	if s.ends_with("deg"):
		unit = "deg"
		value_str = s.substr(0, s.length() - 3)
	elif s.ends_with("s"):
		unit = "s"
		value_str = s.substr(0, s.length() - 1)
	elif s.ends_with("m"):
		unit = "m"
		value_str = s.substr(0, s.length() - 1)
	
	return {"value": value_str.to_float(), "unit": unit}

# Extract quoted string from parts array
static func _extract_quoted(parts: Array, index: int) -> String:
	if index >= parts.size():
		return ""
	return parts[index].replace("\"", "")

# Parse a Vector3 from string "(x, y, z)"
static func parse_vector3(s: String) -> Vector3:
	var cleaned = s.replace("(", "").replace(")", "").strip_edges()
	var components = cleaned.split(",")
	if components.size() >= 3:
		return Vector3(
			components[0].strip_edges().to_float(),
			components[1].strip_edges().to_float(),
			components[2].strip_edges().to_float()
		)
	return Vector3.ZERO

# Calculate frame count from duration
static func duration_to_frames(duration_sec: float) -> int:
	return int(duration_sec * FPS)

# Calculate duration from distance and speed
static func distance_to_duration(distance_m: float, is_running: bool = true) -> float:
	var speed = 5.0 # base move_speed
	if is_running:
		speed *= 1.8 # run_speed_multiplier
	# Add a small buffer for acceleration ramp-up (approx 0.4s)
	return (distance_m / speed) + 0.4
