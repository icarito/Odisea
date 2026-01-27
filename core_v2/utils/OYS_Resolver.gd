extends Reference

class_name OYS_Resolver

# Ensure InputDataV2 is preloaded for use in _default_input_dict
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")

const FPS = 60.0

# Main entry point: parses a script and returns a dictionary.
static func parse_script(script_content: String) -> Dictionary:
    var lines = _preprocess_script(script_content)
    var frame_data = {} # Using a dictionary to store frames to handle AT modifier easily
    var asserts = []
    var setters = []
    var current_frame = 0
    var in_section = false
    var current_section_name = ""

    for line in lines:
        var result = _parse_line(line, current_frame)
        if result:
            # Merge frame data
            for frame_num in result.get("frames", {}):
                if !frame_data.has(frame_num):
                    frame_data[frame_num] = {}
                frame_data[frame_num].merge(result.frames[frame_num], true)

            asserts.append_array(result.get("asserts", []))
            setters.append_array(result.get("setters", []))
            current_frame = result.get("next_frame", current_frame)

    var input_buffer = _convert_frames_to_buffer(frame_data)

    return {
        "buffer": input_buffer,
        "asserts": asserts,
        "setters": setters,
        "total_frames": current_frame
    }

static func _convert_frames_to_buffer(frame_data: Dictionary) -> Array:
    var buffer = []
    if frame_data.empty():
        return buffer

    var sorted_frames = frame_data.keys()
    sorted_frames.sort()

    var max_frame = sorted_frames[-1]
    for i in range(max_frame + 1):
        if frame_data.has(i):
            buffer.append(frame_data[i])
        else:
            buffer.append(_default_input_dict()) # Add empty frame for continuity

    return buffer

# Removes comments and empty lines.
static func _preprocess_script(script_content: String) -> PoolStringArray:
    var lines = PoolStringArray()
    for line in script_content.split("\n"):
        var stripped_line = line.strip_edges()
        if stripped_line.empty() or stripped_line.begins_with("//"):
            continue
        lines.append(stripped_line)
    return lines

static func _default_input_dict() -> Dictionary:
    var d = InputDataV2.new()
    return d.to_dict()

# Parses a single line of OYS script.
static func _parse_line(line: String, start_frame: int) -> Dictionary:
    print("[OYS_Resolver] _parse_line ENTRY: line=", line, ", start_frame=", start_frame)
    var parts = line.split(" ", false)
    var command = parts[0].to_upper()

    var frames = {}
    var asserts = []
    var setters = []
    var next_frame = start_frame

    var at_data = _extract_at_data(parts)

    match command:
        "FW", "BW", "WALK", "RUN", "LT", "RT", "LEFT", "RIGHT":
            var is_walking = false
            var is_running = true # Default for movement
            var current_parts = parts
            
            # Handle modifiers
            if command == "WALK":
                is_walking = true
                is_running = false
                current_parts = parts.slice(1, parts.size())
                command = current_parts[0].to_upper()
            elif command == "RUN":
                is_walking = false
                is_running = true
                current_parts = parts.slice(1, parts.size())
                command = current_parts[0].to_upper()

            # Synonyms
            if command == "LT": command = "LEFT"
            if command == "RT": command = "RIGHT"

            var value_str = current_parts[1]
            var parsed_unit = _parse_value_with_unit(value_str)
            var value = parsed_unit.value
            var unit = parsed_unit.unit

            match command:
                "FW", "BW":
                    var duration_sec = value
                    if unit == "m":
                        var speed = 5.0 # default move_speed
                        if is_running: speed *= 1.8 # run_speed_multiplier
                        duration_sec = value / speed
                    
                    var num_frames = int(duration_sec * FPS)
                    var move_vec = Vector2(0, 1) if command == "FW" else Vector2(0, -1)
                    for i in range(num_frames):
                        frames[start_frame + i] = {
                            "move_vec": [move_vec.x, move_vec.y],
                            "sprint": is_running
                        }
                    next_frame = start_frame + num_frames

                "LEFT", "RIGHT":
                    if unit == "deg":
                        # Turning behavior (synonym for LT/RT)
                        var degrees = value
                        var duration_sec = 0.5 # Default duration for turns
                        var num_frames = int(duration_sec * FPS)
                        var mouse_dx = - degrees / num_frames if command == "LEFT" else degrees / num_frames
                        for i in range(num_frames):
                            frames[start_frame + i] = {"mouse_delta": [mouse_dx, 0]}
                        next_frame = start_frame + num_frames
                    else:
                        # Strafing behavior
                        var duration_sec = value
                        if unit == "m":
                            var speed = 5.0
                            if is_running: speed *= 1.8
                            duration_sec = value / speed
                        
                        var num_frames = int(duration_sec * FPS)
                        var move_vec = Vector2(1, 0) if command == "LEFT" else Vector2(-1, 0)
                        for i in range(num_frames):
                            frames[start_frame + i] = {
                                "move_vec": [move_vec.x, move_vec.y],
                                "sprint": is_running
                            }
                        next_frame = start_frame + num_frames

        "LOOK":
            var pitch = parts[1].to_float()
            var duration_sec = 0.5 # Default duration for look
            var num_frames = int(duration_sec * FPS)
            var mouse_dy = - pitch / num_frames # Inverted mouse
            for i in range(num_frames):
                frames[start_frame + i] = {"mouse_delta": [0, mouse_dy]}
            next_frame = start_frame + num_frames

        "JUMP":
            var duration_sec = 0.1
            if parts.size() > 1 and not parts[1].to_upper() == "AT":
                duration_sec = parts[1].to_float()
            var num_frames = int(duration_sec * FPS)
            for i in range(num_frames):
                frames[start_frame + i] = {"jump": true}
            next_frame = start_frame + num_frames

        "INTERACT":
            frames[start_frame] = {"interact": true}
            next_frame = start_frame + 1 # Takes one frame

        "WAIT":
            var duration_sec = parts[1].to_float()
            var num_frames = int(duration_sec * FPS)
            for i in range(num_frames):
                frames[start_frame + i] = {} # Empty input
            next_frame = start_frame + num_frames

        "ASSERT":
            var condition = line.replace("ASSERT ", "")
            asserts.append({"frame": start_frame, "condition": condition})

        "SET":
            var prop = parts[1]
            var value_str = line.replace("SET " + prop + " ", "")
            setters.append({"frame": start_frame, "property": prop, "value": value_str})

        "SECTION", "END":
            # For now, these are just markers and don't affect the input buffer.
            # They can be used by the test runner to group assertions.
            pass

        _:
            printerr("OYS_Resolver: Unknown command '", command, "'")
            # Always return a valid Dictionary, even for unknown commands
            # This ensures the function never returns null
            return {"frames": {}, "asserts": [], "setters": [], "next_frame": start_frame}

    # Handle AT modifier
    if at_data.has("time") and at_data.has("action"):
        var at_frame = start_frame + int(at_data.time * FPS)
        var at_result = _parse_line(at_data.action, at_frame)
        if at_result == null or typeof(at_result) != TYPE_DICTIONARY:
            at_result = {"frames": {}, "asserts": [], "setters": [], "next_frame": at_frame}
        for frame_num in at_result.get("frames", {}):
            if !frames.has(frame_num):
                frames[frame_num] = {}
            frames[frame_num].merge(at_result.frames[frame_num], true)

    if frames.size() > 0 or asserts.size() > 0 or setters.size() > 0 or next_frame != start_frame:
        var result = {
            "frames": frames,
            "asserts": asserts,
            "setters": setters,
            "next_frame": next_frame
        }
        print("[OYS_Resolver] _parse_line EXIT (normal): ", result)
        return result

    # Final fallback: always return a valid Dictionary, even if all logic is bypassed
    var fallback = {"frames": {}, "asserts": [], "setters": [], "next_frame": start_frame}
    print("[OYS_Resolver] _parse_line EXIT (fallback): ", fallback)
    return fallback

static func _extract_at_data(parts: PoolStringArray) -> Dictionary:
    var at_index = -1
    for i in range(parts.size()):
        if parts[i].to_upper() == "AT":
            at_index = i
            break

    if at_index == -1:
        return {} # Always return a Dictionary

    var arr = []
    for i in range(parts.size()):
        arr.append(parts[i])
    var action_arr = arr.slice(at_index + 2, arr.size())
    return {
        "time": parts[at_index + 1].to_float(),
        "action": " ".join(action_arr)
    }

static func _parse_value_with_unit(s: String) -> Dictionary:
    var unit = "deg" # Default for raw numbers
    var value_str = s
    if s.ends_with("s"):
        unit = "s"
        value_str = s.substr(0, s.length() - 1)
    elif s.ends_with("m"):
        unit = "m"
        value_str = s.substr(0, s.length() - 1)
    
    return {"value": value_str.to_float(), "unit": unit}
