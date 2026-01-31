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
	WAIT, LOOK,
	SET, ASSERT, ASSERT_SIGNAL, PRINT,
	GOTO, IF,
	PLAY_ANIM, WAIT_ANIM, SPAWN,
	SET_TIME_SCALE, GET_NODES_IN_GROUP,
	SCREENSHOT
}

# Command synonyms mapping
const SYNONYMS = {
	"FORWARD": "FW",
	"BACKWARD": "BW",
	"LT": "LEFT",
	"RT": "RIGHT"
}

# Preprocess script: remove comments and empty lines
static func preprocess(script_content: String) -> PoolStringArray:
	var lines = PoolStringArray()
	for line in script_content.split("\n"):
		var stripped = line.strip_edges()
		if stripped.empty() or stripped.begins_with("//") or stripped.begins_with("#"):
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
			pass # No additional data needed
		
		"WAIT":
			data["value"] = parts[1].to_float() if parts.size() > 1 else 0.0
		
		"LOOK":
			data["pitch"] = parts[1].to_float() if parts.size() > 1 else 0.0
			data["duration"] = 0.5
		
		"SET":
			data["var"] = parts[1] if parts.size() > 1 else ""
			if parts.size() > 3:
				data["func"] = parts[2]
				var args = []
				for j in range(3, parts.size()):
					args.append(parts[j])
				data["args"] = args
			elif parts.size() > 2:
				data["value"] = parts[2]
		
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
			data["path"] = _extract_quoted(parts, 1)
			data["anim"] = _extract_quoted(parts, 2)
			if parts.size() > 3:
				data["blend"] = parts[3].to_float()
		
		"WAIT_ANIM":
			data["path"] = _extract_quoted(parts, 1)
		
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
			data["path"] = parts[1] if parts.size() > 1 else "res://screenshot.png"
		
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
					data.merge(parsed, true)
				elif sub_cmd == "LEFT" or sub_cmd == "RIGHT":
					var parsed = _parse_strafe_or_turn(sub_parts, sub_cmd)
					data.merge(parsed, true)
		
		_:
			data["error"] = "Unknown command: " + cmd
	
	return data

# Parse movement commands (FW/BW)
static func _parse_movement(parts: Array, direction: String) -> Dictionary:
	var result = {"direction": direction}
	if parts.size() > 1:
		var parsed = _parse_value_with_unit(parts[1])
		result["value"] = parsed.value
		result["unit"] = parsed.unit
		result["is_running"] = true # Default
	return result

# Parse strafe/turn commands (LEFT/RIGHT)
static func _parse_strafe_or_turn(parts: Array, direction: String) -> Dictionary:
	var result = {"direction": direction}
	if parts.size() > 1:
		var parsed = _parse_value_with_unit(parts[1])
		result["value"] = parsed.value
		result["unit"] = parsed.unit
		result["is_turning"] = (parsed.unit == "deg")
	return result

# Parse value with unit suffix (e.g., "2.5s", "10m", "90deg")
static func _parse_value_with_unit(s: String) -> Dictionary:
	var unit = "s" # Default: seconds
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
	return distance_m / speed
