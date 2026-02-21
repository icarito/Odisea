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
	WAIT, WAIT_FRAMES, LOOK, CALL, ZOOM, FOV,
	SET, ASSERT, ASSERT_SIGNAL, PRINT, CLS,
	GOTO, IF,
	PLAY_ANIM, WAIT_ANIM, SPAWN,
	SET_TIME_SCALE, GET_NODES_IN_GROUP,
	SCREENSHOT, LOAD_PROP,
	CINEMATIC_START, CINEMATIC_STOP,
	RECORD_START, RECORD_STOP,
	GET_POS,
	CINEMATIC,
	INTERACTIVE,
	BLEND,
	ASSERT_NO_HAND_CLIPPING,
	UI_OPEN, UI_CLICK, UI_FILL, UI_TYPE, UI_PRESS, UI_WAIT, UI_SCREENSHOT, UI_ASSERT_TEXT,
	LOG,
	TELEPORT,
	CAMERA_SHAKE, CAMERA_SHAKE_STOP,
	PLAY_SOUND,
	VCAMERA, VCAMERA_BLEND, VCAMERA_RETURN, VCAMERA_SHAKE
}

# Command synonyms mapping
const SYNONYMS = {
	"FORWARD": "FW",
	"BACKWARD": "BW",
	"LT": "LEFT",
	"RT": "RIGHT",
	"WAITF": "WAIT_FRAMES",
	"WAIT_FRAME": "WAIT_FRAMES",
	"TIME_SCALE": "SET_TIME_SCALE",
	"PLAY_SFX": "PLAY_SOUND",
	"SFX": "PLAY_SOUND",
	"SHAKE": "CAMERA_SHAKE",
	"STOP_SHAKE": "CAMERA_SHAKE_STOP",
	"CAM_SHAKE": "CAMERA_SHAKE",
	"UI_OPEN": "OPEN",
	"UI_CLICK": "CLICK",
	"UI_FILL": "FILL",
	"UI_TYPE": "TYPE",
	"UI_PRESS": "PRESS",
	"UI_WAIT": "WAIT",
	"UI_ASSERT_TEXT": "ASSERT_TEXT"
}

# Preprocess script: remove comments and empty lines
static func preprocess(script_content: String) -> PoolStringArray:
	var lines = PoolStringArray()
	for line in script_content.split("\n"):
		var stripped = line.strip_edges()
		if stripped.empty(): continue

		stripped = _strip_inline_comments(stripped).strip_edges()

		if stripped.empty():
			continue
		lines.append(stripped)
	return lines

static func _strip_inline_comments(line: String) -> String:
	var in_quote := false
	for i in range(line.length()):
		var ch = line[i]
		if ch == "\"":
			in_quote = !in_quote
			continue
		if in_quote:
			continue
		if ch == "#":
			return line.substr(0, i)
		if ch == "/" and i + 1 < line.length() and line[i + 1] == "/":
			var prev = line[i - 1] if i > 0 else ""
			# Keep URI-like schemes (e.g. res://, http://)
			if prev == ":":
				continue
			return line.substr(0, i)
	return line

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
		
		"WAIT", "WAIT_FRAMES":
			var wait_data = _parse_wait_instruction(parts, cmd)
			data.merge(wait_data, true)
		
		"LOOK":
			data["pitch"] = parts[1].to_float() if parts.size() > 1 else 0.0
			data["duration"] = parts[2].to_float() if parts.size() > 2 else 0.5
		
		"ZOOM":
			data["amount"] = parts[1].to_float() if parts.size() > 1 else 0.0
			data["duration"] = parts[2].to_float() if parts.size() > 2 else 0.5
		
		"FOV":
			data["fov"] = parts[1].to_float() if parts.size() > 1 else 75.0
			data["duration"] = parts[2].to_float() if parts.size() > 2 else 0.5
		
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
		"LOG":
			var quoted = _extract_quoted_values(line)
			if quoted.size() >= 2:
				data["tag"] = quoted[0]
				data["message"] = quoted[1]
				if quoted.size() >= 3:
					data["color"] = quoted[2]
			else:
				data["tag"] = parts[1] if parts.size() > 1 else "OYS"
				if parts.size() > 2:
					var first_space = line.find(" ")
					var second_space = line.find(" ", first_space + 1)
					if second_space != -1:
						data["message"] = line.substr(second_space + 1).replace("\"", "")

		"CLS":
			pass
		
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

		"PLAY_SOUND":
			# Default behavior: target an SFXComponent node by name/path.
			# Optional fallback through AudioManager:
			# PLAY_SOUND sound="ui_click"
			# PLAY_SOUND sfx="SFX Alarm"
			# PLAY_SOUND "SFX Alarm"
			data["sfx"] = ""
			data["sound"] = ""

			var quoted = _extract_quoted_values(line)
			if quoted.size() > 0:
				data["sfx"] = quoted[0]

			for i in range(1, parts.size()):
				var token = parts[i]
				if token.find("=") == -1:
					continue
				var kv = token.split("=", false, 1)
				if kv.size() < 2:
					continue
				var k = kv[0].to_lower()
				var v = kv[1].replace("\"", "")
				match k:
					"sfx", "node", "target", "path":
						data["sfx"] = v
					"sound", "name":
						data["sound"] = v
		
		"WAIT_ANIM":
			var arg1 = _extract_quoted(parts, 1)
			# If it looks like a path (has / or is $var), treat as path.
			# Otherwise, if it's just a name, it might be an implicit wait on player?
			# Actually WAIT_ANIM usually waits for a node to finish.
			# If we want WAIT_ANIM "Confused", that's harder because we wait on a Node, not an Anim.
			# For now, let's keep WAIT_ANIM taking a NODE path.
			data["path"] = arg1
		
		"SPAWN":
			# Support both legacy SPAWN "path" AT (x,y,z) and named args SPAWN scene="path" pos=[x,y,z]
			for i in range(1, parts.size()):
				var p = parts[i]
				if p.begins_with("scene="):
					data["scene"] = _extract_quoted([p.split("=")[1]], 0)
				elif p.begins_with("pos="):
					# Handle pos=[x, y, z] potentially split by spaces
					var val_start = line.find("pos=") + 4
					# Find end of vector ] or )
					var val_end = -1
					var open_char = line[val_start]
					var close_char = ""
					if open_char == "[": close_char = "]"
					elif open_char == "(": close_char = ")"
					
					if close_char != "":
						val_end = line.find(close_char, val_start)
						if val_end != -1:
							data["pos"] = line.substr(val_start, val_end - val_start + 1)
					else:
						# Simple value?
						data["pos"] = p.split("=")[1]
			
			# Legacy Fallback
			if not data.has("scene") and parts.size() > 1 and not parts[1].begins_with("scene="):
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

		"OPEN":
			data["path"] = _extract_quoted(parts, 1)
			if data["path"] == "" and parts.size() > 1:
				data["path"] = parts[1]

		"CLICK":
			data["selector"] = _extract_quoted(parts, 1)
			if data["selector"] == "" and parts.size() > 1:
				data["selector"] = parts[1]

		"FILL", "TYPE", "PRESS", "ASSERT_TEXT":
			var quoted = _extract_quoted_values(line)
			if quoted.size() >= 2:
				data["selector"] = quoted[0]
				data["value"] = quoted[1]
			else:
				data["selector"] = _extract_quoted(parts, 1)
				if data["selector"] == "" and parts.size() > 1:
					data["selector"] = parts[1]
				if parts.size() > 2:
					var idx = line.find(parts[2])
					if idx != -1:
						data["value"] = line.substr(idx).replace("\"", "")
					else:
						data["value"] = parts[2]

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

		"BLEND":
			data["duration"] = parts[1].to_float() if parts.size() > 1 else 1.0

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
				# Store the rest of the line as expression (including the operator)
				var start_pos = line.find(parts[1]) + parts[1].length()
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

		"ASSERT_NO_HAND_CLIPPING":
			# ASSERT_NO_HAND_CLIPPING BoxName [0.05] [MONITOR 1.0] [CONSEC 3]
			data["box"] = _extract_quoted(parts, 1)
			data["max_penetration"] = parts[2].to_float() if parts.size() > 2 else 0.05
			data["monitor_duration"] = 0.0
			data["consecutive_frames"] = 0
			
			var i = 3
			while i < parts.size():
				var token = parts[i].to_upper()
				if token == "MONITOR" and i + 1 < parts.size():
					data["monitor_duration"] = parts[i + 1].to_float()
					i += 2
					continue
				if token == "CONSEC" and i + 1 < parts.size():
					data["consecutive_frames"] = int(parts[i + 1])
					i += 2
					continue
				i += 1

		"TELEPORT":
			# TELEPORT (x, y, z) or TELEPORT pos=(x, y, z)
			if parts.size() > 1:
				if parts[1].begins_with("pos="):
					data["pos"] = parts[1].split("=")[1]
				else:
					# Join remaining parts to handle spaces in vector (x, y, z)
					var val = ""
					for i in range(1, parts.size()):
						val += parts[i]
					data["pos"] = val.strip_edges()

		"CAMERA_SHAKE":
			# CAMERA_SHAKE [duration] [amplitude] [frequency] [roll]
			# CAMERA_SHAKE duration=0.35 amplitude=0.08 frequency=28 roll=1.0
			data["duration"] = 0.35
			data["amplitude"] = 0.08
			data["frequency"] = 28.0
			data["roll"] = 1.0
			data["intensity"] = 1.0
			var positional = 0
			for i in range(1, parts.size()):
				var token = parts[i]
				if token.find("=") != -1:
					var kv = token.split("=", false, 1)
					var k = kv[0].to_lower()
					var v = kv[1].to_float() if kv.size() > 1 else 0.0
					match k:
						"duration", "dur", "time":
							data["duration"] = v
						"amplitude", "amp", "strength":
							data["amplitude"] = v
						"frequency", "freq", "speed":
							data["frequency"] = v
						"roll", "roll_degrees", "rot":
							data["roll"] = v
						"intensity":
							data["intensity"] = v
				else:
					var v = token.to_float()
					match positional:
						0:
							data["duration"] = v
						1:
							data["amplitude"] = v
						2:
							data["frequency"] = v
						3:
							data["roll"] = v
					positional += 1

			# Support vector-style shake syntax used by VCAMERA_SHAKE:
			# CAMERA_SHAKE translation="(x, y, z)" rotation="(x, y, z)" intensity=0.8
			var trans = _extract_named_value(line, "translation")
			if trans == "":
				trans = _extract_named_value(line, "trans")
			if trans != "":
				data["translation"] = trans

			var rot = _extract_named_value(line, "rotation")
			if rot == "":
				rot = _extract_named_value(line, "rot")
			# Avoid clobbering scalar roll syntax like rot=3
			if rot.find(",") != -1 or (rot.begins_with("(") and rot.ends_with(")")):
				data["rotation"] = rot

			var named_intensity = _extract_named_value(line, "intensity")
			if named_intensity != "":
				data["intensity"] = named_intensity.to_float()
		
		"CAMERA_SHAKE_STOP":
			pass
		
		"VCAMERA":
			data["name"] = _extract_quoted(parts, 1)
			for i in range(1, parts.size()):
				var token = parts[i]
				if token.find("=") != -1:
					var kv = token.split("=", false, 1)
					var k = kv[0].to_lower()
					var v = kv[1].replace("\"", "") if kv.size() > 1 else ""
					match k:
						"name":
							data["name"] = v
						"duration", "dur":
							data["duration"] = v.to_float()
						"ease":
							data["ease"] = v.to_float()
						"follow":
							data["follow"] = v
						"look_at", "lookat":
							data["look_at"] = v
						"mode":
							data["mode"] = v.to_lower()
			if not data.has("duration"):
				data["duration"] = 1.0
			if not data.has("ease"):
				data["ease"] = -2.0
			if not data.has("mode"):
				data["mode"] = "script"
		
		"VCAMERA_BLEND":
			data["name"] = _extract_quoted(parts, 1)
			for i in range(1, parts.size()):
				var token = parts[i]
				if token.find("=") != -1:
					var kv = token.split("=", false, 1)
					var k = kv[0].to_lower()
					var v = kv[1].replace("\"", "") if kv.size() > 1 else ""
					match k:
						"name":
							data["name"] = v
						"duration", "dur":
							data["duration"] = v.to_float()
						"follow":
							data["follow"] = v
						"look_at", "lookat":
							data["look_at"] = v
						"mode":
							data["mode"] = v.to_lower()
			if not data.has("duration"):
				data["duration"] = 1.0
			if not data.has("mode"):
				data["mode"] = "script"
		
		"VCAMERA_RETURN":
			for i in range(1, parts.size()):
				var token = parts[i]
				if token.find("=") != -1:
					var kv = token.split("=", false, 1)
					var k = kv[0].to_lower()
					var v = kv[1].replace("\"", "") if kv.size() > 1 else ""
					if k == "duration" or k == "dur":
						data["duration"] = v.to_float()
			if not data.has("duration"):
				data["duration"] = 1.0
		
		"VCAMERA_SHAKE":
			data["translation"] = "(0, 0, 0)"
			data["rotation"] = "(0, 0, 0)"
			data["intensity"] = 1.0
			data["duration"] = 0.35
			data["frequency"] = 28.0
			for i in range(1, parts.size()):
				var token = parts[i]
				if token.find("=") != -1:
					var kv = token.split("=", false, 1)
					var k = kv[0].to_lower()
					var v = kv[1].replace("\"", "") if kv.size() > 1 else ""
					match k:
						"translation", "trans":
							data["translation"] = v
						"rotation", "rot":
							data["rotation"] = v
						"intensity":
							data["intensity"] = v.to_float()
						"duration", "dur", "time":
							data["duration"] = v.to_float()
						"frequency", "freq", "speed":
							data["frequency"] = v.to_float()

			# Robust parse from full line to support quoted vectors with spaces.
			var v_trans = _extract_named_value(line, "translation")
			if v_trans == "":
				v_trans = _extract_named_value(line, "trans")
			if v_trans != "":
				data["translation"] = v_trans

			var v_rot = _extract_named_value(line, "rotation")
			if v_rot == "":
				v_rot = _extract_named_value(line, "rot")
			if v_rot != "":
				data["rotation"] = v_rot

			var v_intensity = _extract_named_value(line, "intensity")
			if v_intensity != "":
				data["intensity"] = v_intensity.to_float()
			var v_duration = _extract_named_value(line, "duration")
			if v_duration == "":
				v_duration = _extract_named_value(line, "dur")
			if v_duration != "":
				data["duration"] = v_duration.to_float()
			var v_frequency = _extract_named_value(line, "frequency")
			if v_frequency == "":
				v_frequency = _extract_named_value(line, "freq")
			if v_frequency == "":
				v_frequency = _extract_named_value(line, "speed")
			if v_frequency != "":
				data["frequency"] = v_frequency.to_float()

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
		
		# If it's turning, check for optional duration argument
		if result["is_turning"] and parts.size() > 2:
			# Parse duration similar to movement duration logic
			var dur_parsed = _parse_value_with_unit(parts[2])
			if dur_parsed.unit == "s" or dur_parsed.unit == "none":
				result["duration"] = dur_parsed.value
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

static func _extract_quoted_values(line: String) -> Array:
	var values := []
	var in_quote := false
	var current := ""
	for i in range(line.length()):
		var ch = line[i]
		if ch == "\"":
			if in_quote:
				values.append(current)
				current = ""
			in_quote = !in_quote
		elif in_quote:
			current += ch
	return values

static func _extract_named_value(line: String, key: String) -> String:
	var lower_line := line.to_lower()
	var needle := key.to_lower() + "="
	var idx := lower_line.find(needle)
	if idx == -1:
		return ""

	var start := idx + needle.length()
	if start >= line.length():
		return ""

	if line[start] == "\"":
		var endq := line.find("\"", start + 1)
		if endq == -1:
			return line.substr(start + 1).strip_edges()
		return line.substr(start + 1, endq - (start + 1)).strip_edges()

	var end := line.find(" ", start)
	if end == -1:
		return line.substr(start).strip_edges()
	return line.substr(start, end - start).strip_edges()

static func _parse_wait_instruction(parts: Array, cmd: String) -> Dictionary:
	var token = String(parts[1]).strip_edges() if parts.size() > 1 else "0"
	if cmd == "WAIT_FRAMES":
		return {
			"value": max(0.0, token.to_float()),
			"unit": "frames"
		}

	var lower = token.to_lower()
	if lower.ends_with("frames"):
		var raw = lower.substr(0, lower.length() - 6)
		return {
			"value": max(0.0, raw.to_float()),
			"unit": "frames"
		}
	if lower.ends_with("frame"):
		var raw = lower.substr(0, lower.length() - 5)
		return {
			"value": max(0.0, raw.to_float()),
			"unit": "frames"
		}
	if lower.ends_with("f") and lower.length() > 1:
		var raw = lower.substr(0, lower.length() - 1)
		return {
			"value": max(0.0, raw.to_float()),
			"unit": "frames"
		}

	return {
		"value": max(0.0, token.to_float()),
		"unit": "s"
	}

# Parse a Vector3 from string "(x, y, z)"
static func parse_vector3(s: String) -> Vector3:
	var cleaned = s.replace("(", "").replace(")", "").replace("[", "").replace("]", "").strip_edges()
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
