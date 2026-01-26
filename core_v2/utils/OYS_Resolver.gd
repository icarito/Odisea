extends Reference
class_name OYS_Resolver

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
    var parts = line.split(" ", false)
    var command = parts[0].to_upper()

    var frames = {}
    var asserts = []
    var setters = []
    var next_frame = start_frame

    var at_data = _extract_at_data(parts)

    match command:
        "FW", "BW":
            var duration_sec = parts[1].to_float()
            var num_frames = int(duration_sec * FPS)
            var move_vec = Vector2(0, 1) if command == "FW" else Vector2(0, -1)
            for i in range(num_frames):
                frames[start_frame + i] = {"move_vec": [move_vec.x, move_vec.y]}
            next_frame = start_frame + num_frames

        "LT", "RT":
            var degrees = parts[1].to_float()
            var duration_sec = 0.5 # Default duration for turns
            var num_frames = int(duration_sec * FPS)
            var mouse_dx = -degrees / num_frames if command == "LT" else degrees / num_frames
            for i in range(num_frames):
                frames[start_frame + i] = {"mouse_delta": [mouse_dx, 0]}
            next_frame = start_frame + num_frames

        "LOOK":
            var pitch = parts[1].to_float()
            var duration_sec = 0.5 # Default duration for look
            var num_frames = int(duration_sec * FPS)
            var mouse_dy = -pitch / num_frames # Inverted mouse
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
            var condition = line.replace("ASSERT ", "", 1)
            asserts.append({"frame": start_frame, "condition": condition})

        "SET":
            var prop = parts[1]
            var value_str = line.replace("SET " + prop + " ", "", 1)
            setters.append({"frame": start_frame, "property": prop, "value": value_str})

        "SECTION", "END":
            # For now, these are just markers and don't affect the input buffer.
            # They can be used by the test runner to group assertions.
            pass

        _:
            printerr("OYS_Resolver: Unknown command '", command, "'")
            return null

    # Handle AT modifier
    if at_data:
        var at_frame = start_frame + int(at_data.time * FPS)
        var at_result = _parse_line(at_data.action, at_frame)
        if at_result:
             for frame_num in at_result.get("frames", {}):
                if !frames.has(frame_num):
                    frames[frame_num] = {}
                frames[frame_num].merge(at_result.frames[frame_num], true)

    return {
        "frames": frames,
        "asserts": asserts,
        "setters": setters,
        "next_frame": next_frame
    }

static func _extract_at_data(parts: PoolStringArray) -> Dictionary:
    var at_index = -1
    for i in range(parts.size()):
        if parts[i].to_upper() == "AT":
            at_index = i
            break

    if at_index == -1:
        return null

    return {
        "time": parts[at_index + 1].to_float(),
        "action": " ".join(parts.slice(at_index + 2, parts.size() -1))
    }
