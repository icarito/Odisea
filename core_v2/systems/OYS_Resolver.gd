# core_v2/systems/OYS_Resolver.gd
# Static pre-parser: converts OYS scripts to deterministic frame-based input buffers
# Used for recording replays that can be saved as JSON for determinism testing
extends Reference

class_name OYS_Resolver

const OYS_Parser = preload("res://core_v2/systems/OYS_Parser.gd")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")

const FPS = 60.0

# Main entry point: parses a script and returns a dictionary with input buffer
static func parse_script(script_content: String) -> Dictionary:
	var lines = OYS_Parser.preprocess(script_content)
	var frame_data = {}
	var events = {}
	var current_frame = 0
	var parse_errors = []

	for line in lines:
		var inst = OYS_Parser.parse_instruction(line)
		if inst.empty():
			continue
		
		# Check for parse errors
		if inst.has("error"):
			parse_errors.append(inst.error)
			printerr("[OYS_Resolver] PARSE ERROR: ", inst.error)
			return {
				"buffer": [],
				"events": {},
				"total_frames": 0,
				"errors": parse_errors
			}
		
		# Convert instruction to frames
		var result = _instruction_to_frames(inst, current_frame)
		
		# Merge frame data (inputs)
		for frame_num in result.get("frames", {}):
			if not frame_data.has(frame_num):
				frame_data[frame_num] = {}
			frame_data[frame_num].merge(result.frames[frame_num], true)
		
		# Merge events
		var new_events = result.get("events", {})
		for f in new_events:
			if not events.has(f):
				events[f] = []
			events[f].append_array(new_events[f])

		current_frame = result.get("next_frame", current_frame)

	var input_buffer = _convert_frames_to_buffer(frame_data)

	return {
		"buffer": input_buffer,
		"events": events,
		"total_frames": current_frame,
		"errors": parse_errors
	}

# Convert parsed instruction to frame data
static func _instruction_to_frames(inst: Dictionary, start_frame: int) -> Dictionary:
	var frames = {}
	var events = {}
	var next_frame = start_frame
	var cmd = inst.command

	match cmd:
		"FW", "BW":
			var duration_sec = inst.get("value", 0.0)
			var unit = inst.get("unit", "s")
			var is_running = inst.get("is_running", true)
			
			if unit == "m":
				duration_sec = OYS_Parser.distance_to_duration(inst.value, is_running)
			
			var num_frames = OYS_Parser.duration_to_frames(duration_sec)
			var move_y = -1 if cmd == "FW" else 1
			
			for i in range(num_frames):
				frames[start_frame + i] = {
					"move_vec": [0, move_y],
					"sprint": is_running
				}
			next_frame = start_frame + num_frames

		"LEFT", "RIGHT":
			var is_turning = inst.get("is_turning", false)
			var value = inst.get("value", 0.0)
			var unit = inst.get("unit", "s")
			var is_running = inst.get("is_running", true)
			
			if is_turning:
				# Turning: degrees to mouse movement
				var duration_sec = 0.5
				# For precision turning, we might want to wait?
				# For now, let's just simulate the input over frames.
				# But WAIT! Turning consumes frames. Logic commands do not.
				
				var num_frames = OYS_Parser.duration_to_frames(duration_sec)
				var sensitivity = 0.005
				var pixels_total = (value * PI / 180.0) / sensitivity
				var mouse_dx = - pixels_total / num_frames if cmd == "LEFT" else pixels_total / num_frames
				
				for i in range(num_frames):
					frames[start_frame + i] = {"mouse_delta": [mouse_dx, 0]}
				next_frame = start_frame + num_frames
			else:
				# Strafing
				var duration_sec = value
				if unit == "m":
					duration_sec = OYS_Parser.distance_to_duration(value, is_running)
				
				var num_frames = OYS_Parser.duration_to_frames(duration_sec)
				var move_x = 1 if cmd == "LEFT" else -1
				
				for i in range(num_frames):
					frames[start_frame + i] = {
						"move_vec": [move_x, 0],
						"sprint": is_running
					}
				next_frame = start_frame + num_frames

		"LOOK":
			var pitch = inst.get("pitch", 0.0)
			var duration_sec = inst.get("duration", 0.5)
			var num_frames = OYS_Parser.duration_to_frames(duration_sec)
			var mouse_dy = - pitch / num_frames
			
			for i in range(num_frames):
				frames[start_frame + i] = {"mouse_delta": [0, mouse_dy]}
			next_frame = start_frame + num_frames

		"JUMP":
			var duration_sec = inst.get("duration", 0.1)
			var num_frames = OYS_Parser.duration_to_frames(duration_sec)
			
			for i in range(num_frames):
				frames[start_frame + i] = {"jump": true}
			next_frame = start_frame + num_frames

		"INTERACT":
			frames[start_frame] = {"interact": true}
			next_frame = start_frame + 1

		"WAIT":
			var duration_sec = inst.get("value", 0.0)
			var num_frames = OYS_Parser.duration_to_frames(duration_sec)
			
			# No input, just wait (empty frames added by convert buffer logic if not present, 
			# or we explicitely add empty dicts to ensure duration matches)
			for i in range(num_frames):
				frames[start_frame + i] = {}
			next_frame = start_frame + num_frames

		"ASSERT", "SET", "MATH", "PRINT", "GET_NODES_IN_GROUP", "CALL", "LOAD_PROP", "SPAWN", "PLAY_ANIM", "SET_TIME_SCALE", "CINEMATIC_START", "CINEMATIC_STOP":
			# Logic commands: executed at the START of the frame, do not consume time
			if not events.has(start_frame):
				events[start_frame] = []
			events[start_frame].append(OYS_Parser.serialize_instruction(inst))
		
		"ASSERT_SIGNAL":
			var timeout = inst.get("timeout", 5.0)
			var num_frames = OYS_Parser.duration_to_frames(timeout)
			
			# Event START at start_frame
			if not events.has(start_frame):
				events[start_frame] = []
			var start_evt = OYS_Parser.serialize_instruction(inst)
			start_evt["phase"] = "start"
			events[start_frame].append(start_evt)
			
			# Wait frames
			for i in range(num_frames):
				frames[start_frame + i] = {}
				
			# Event CHECK at end of wait
			var end_frame = start_frame + num_frames
			if not events.has(end_frame):
				events[end_frame] = []
			var check_evt = OYS_Parser.serialize_instruction(inst)
			check_evt["phase"] = "check"
			events[end_frame].append(check_evt)
			
			next_frame = end_frame

		# These commands are markers or runtime-only - just pass through or handle if needed
		"SECTION", "END", "LEVEL", "GOTO", "IF", \
		"PLAY_ANIM", "WAIT_ANIM", "SPAWN", "SET_TIME_SCALE", "SCREENSHOT", \
		"CINEMATIC_START", "CINEMATIC_STOP", "RECORD_START", "RECORD_STOP":
			pass

	return {
		"frames": frames,
		"events": events,
		"next_frame": next_frame
	}

static func _convert_frames_to_buffer(frame_data: Dictionary) -> Array:
	var buffer = []
	if frame_data.empty():
		return buffer

	var sorted_frames = frame_data.keys()
	sorted_frames.sort()

	var max_frame = sorted_frames[-1] if sorted_frames.size() > 0 else 0
	for i in range(max_frame + 1):
		if frame_data.has(i):
			buffer.append(frame_data[i])
		else:
			buffer.append(_default_input_dict())

	return buffer

static func _default_input_dict() -> Dictionary:
	var d = InputDataV2.new()
	return d.to_dict()
