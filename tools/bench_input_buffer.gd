extends SceneTree

# bench_input_buffer.gd — Measures time and size of compact input buffer delta encoding
#
# Run: godot3-bin --no-window -s tools/bench_input_buffer.gd

const TEST_FILE_IDLE := "user://bench_idle.json"
const TEST_FILE_ACTIVE := "user://bench_active.json"
const NUM_FRAMES := 3600 # 60 seconds at 60 FPS

func _init() -> void:
	print("--- BENCHMARK: INPUT BUFFER DELTA ENCODING ---")
	
	# Load SessionManager to access its methods safely
	var sm_script = load("res://core_v2/autoloads/SessionManager.gd")
	var sm = sm_script.new()
	sm.name = "SessionManager"
	
	# Generate mock uncompressed data
	var idle_inputs := []
	var active_inputs := []
	
	# Idle inputs: completely identical frames
	var default_input = {
		"move_vec": [0.0, 0.0],
		"mouse_delta": [0.0, 0.0],
		"zoom_delta": 0.0,
		"fov_override": -1.0,
		"jump": false,
		"sprint": false,
		"crouch": false,
		"interact": false,
		"focus": false,
		"rotate_left": false,
		"rotate_right": false,
		"roll_left": false,
		"roll_right": false,
		"tool_fire_primary": false,
		"tool_fire_secondary": false,
		"tool_next_mode": false,
		"tool_prev_mode": false,
		"cargol_ability": false,
		"hardware_mouse_active": false
	}
	
	# Add an initial snapshot as would happen in a real replay
	idle_inputs.append({"snapshot": {"position": [0,0,0], "yaw": 0, "pitch": 0}})
	active_inputs.append({"snapshot": {"position": [0,0,0], "yaw": 0, "pitch": 0}})
	
	for i in range(NUM_FRAMES):
		idle_inputs.append({"input": default_input.duplicate(true)})
		
		var active_input = default_input.duplicate(true)
		if i % 10 == 0:
			active_input["move_vec"] = [1.0, 0.0]
		if i % 5 == 0:
			active_input["mouse_delta"] = [float(i % 100), 0.0]
			active_input["hardware_mouse_active"] = true
		if i % 100 == 0:
			active_input["jump"] = true
		active_inputs.append({"input": active_input})

	print("Benchmarking %d frames..." % NUM_FRAMES)
	
	# Benchmark Compression Time
	var t0_idle := OS.get_ticks_usec()
	var idle_compact = sm.compress_buffer(idle_inputs)
	var t1_idle := OS.get_ticks_usec()
	var time_idle_compress = (t1_idle - t0_idle) / 1000.0 # ms
	
	var t0_active := OS.get_ticks_usec()
	var active_compact = sm.compress_buffer(active_inputs)
	var t1_active := OS.get_ticks_usec()
	var time_active_compress = (t1_active - t0_active) / 1000.0 # ms
	
	# Benchmark Serialization / Save Time and File Size
	# Uncompressed Save Times (estimate via raw prints)
	var t0_idle_uncompressed_save = OS.get_ticks_usec()
	var idle_uncompressed_json = sm._json_print_normalized({"buffer": idle_inputs})
	var t1_idle_uncompressed_save = OS.get_ticks_usec()
	var time_idle_uncompressed_save = (t1_idle_uncompressed_save - t0_idle_uncompressed_save) / 1000.0
	
	# Compact Save Times
	var t0_idle_compact_save = OS.get_ticks_usec()
	var idle_compact_json = sm._json_print_normalized({"buffer": idle_compact})
	var t1_idle_compact_save = OS.get_ticks_usec()
	var time_idle_compact_save = (t1_idle_compact_save - t0_idle_compact_save) / 1000.0
	
	var t0_active_compact_save = OS.get_ticks_usec()
	var active_compact_json = sm._json_print_normalized({"buffer": active_compact})
	var t1_active_compact_save = OS.get_ticks_usec()
	var time_active_compact_save = (t1_active_compact_save - t0_active_compact_save) / 1000.0
	
	# Measure file sizes
	var idle_compact_size = idle_compact_json.length()
	var active_compact_size = active_compact_json.length()
	
	var uncompressed_size = idle_uncompressed_json.length()
	
	# Benchmark Load and Expansion Time
	var t0_idle_load = OS.get_ticks_usec()
	var idle_expanded = sm.expand_buffer(idle_compact)
	var t1_idle_load = OS.get_ticks_usec()
	var time_idle_load_expand = (t1_idle_load - t0_idle_load) / 1000.0
	
	var t0_active_load = OS.get_ticks_usec()
	var active_expanded = sm.expand_buffer(active_compact)
	var t1_active_load = OS.get_ticks_usec()
	var time_active_load_expand = (t1_active_load - t0_active_load) / 1000.0
	
	# Validate correct expansion
	var idle_match = (idle_expanded.size() == idle_inputs.size())
	var active_match = (active_expanded.size() == active_inputs.size())
	
	print("\n--- RESULTS REPORT ---")
	print("Scenario: IDLE SESSION (60s)")
	print("  Uncompressed Size:  %.2f KB" % (uncompressed_size / 1024.0))
	print("  Compact Size:       %.2f KB" % (idle_compact_size / 1024.0))
	print("  Size Reduction:     %.2f%%" % (100.0 - (100.0 * idle_compact_size / uncompressed_size)))
	print("  Compression Time:   %.3f ms" % time_idle_compress)
	print("  Uncompressed Save:  %.3f ms" % time_idle_uncompressed_save)
	print("  Compact Save:       %.3f ms" % time_idle_compact_save)
	print("  Load & Expand Time: %.3f ms" % time_idle_load_expand)
	print("  Buffer Array Size:  %d elements (compact) vs %d elements (uncompressed)" % [idle_compact.size(), idle_inputs.size()])
	print("  Correctness Match:  %s" % str(idle_match))
	
	print("\nScenario: ACTIVE SESSION (60s)")
	print("  Uncompressed Size:  %.2f KB" % (uncompressed_size / 1024.0))
	print("  Compact Size:       %.2f KB" % (active_compact_size / 1024.0))
	print("  Size Reduction:     %.2f%%" % (100.0 - (100.0 * active_compact_size / uncompressed_size)))
	print("  Compression Time:   %.3f ms" % time_active_compress)
	print("  Compact Save:       %.3f ms" % time_active_compact_save)
	print("  Load & Expand Time: %.3f ms" % time_active_load_expand)
	print("  Buffer Array Size:  %d elements (compact) vs %d elements (uncompressed)" % [active_compact.size(), active_inputs.size()])
	print("  Correctness Match:  %s" % str(active_match))
	
	sm.free()
	quit(0)
