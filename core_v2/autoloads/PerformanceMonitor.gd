extends Node

# PerformanceMonitor.gd
# Global Singleton for Telemetry, Profiling and Debugging
# Part of OdiseaOS Telemetry System

const LOG_FILE_PATH := "user://performance_log.json"
const SNAPSHOT_FILE_PATH := "user://performance_snapshots.json"
const CAPTURE_FILE_PATH := "user://performance_captures.json"
const LAG_SPIKE_THRESHOLD_FPS := 20.0
const CPU_BUDGET_MS := 16.6
const LOG_TRIGGER_PERCENT := 0.70 # 70% of CPU Budget
const CPU_WARNING_INTERVAL_SEC := 5.0
const LAG_LOG_INTERVAL_SEC := 5.0
const REPORT_WRITE_INTERVAL_SEC := 8.0
const REPORT_WRITE_INTERVAL_HYPER_LOW_SEC := 20.0
const REPORT_DROP_BYPASS_DELTA := 12.0
const DETAILED_NODE_PROFILING_ENV := "ODISEA_DETAILED_NODE_PROFILING"

# --- Debug Flags ---
var debug_freeze_logic := false setget set_debug_freeze_logic
var debug_cull_distance_enabled := false
var debug_cull_radius := 50.0
var debug_step_mode := false # Managed via freeze logic + manual step
var debug_disable_ai := false setget set_debug_disable_ai
var debug_collision_shapes := false setget set_debug_collision_shapes

# --- Metrics State ---
var _frame_start_time := 0
var _last_process_tick_usec := 0
var _last_frame_gap_ms := 0.0
var _last_fps := 60.0
var _monitored_nodes := [] # Array of WeakRef
var _node_profiling_accumulators := {} # { node_id: accumulated_usec }
var _node_profiling_calls := {} # { node_id: call_count }
var _node_measurement_start := {} # { node_id: start_usec }
var _profiled_node_names := {} # { node_id: node.name }
var _profiled_node_paths := {} # { node_id: String(node.get_path()) }
var _suppress_runtime_logs := false
var _disabled := false
var _capture_active := false
var _capture_tag := ""
var _capture_start_usec := 0
var _capture_samples := []
var _last_cpu_warning_time := 0.0
var _last_lag_log_time_msec := 0
var _last_report_write_time_msec := 0
var _last_saved_drop := 0.0
var _suppressed_report_count := 0
var _detailed_node_profiling_enabled := false

# --- Signals ---
signal lag_spike_detected(fps, drop)

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS # Always run, even when tree is paused
	_suppress_runtime_logs = _is_test_environment()
	_detailed_node_profiling_enabled = OS.get_environment(DETAILED_NODE_PROFILING_ENV).to_lower() in ["1", "true", "yes", "on"]
	_disabled = _is_disabled_for_current_run()
	if _disabled:
		set_process(false)
		if not _suppress_runtime_logs:
			print("[PerformanceMonitor] Disabled for this run")
		return
	print("[PerformanceMonitor] Initialized")

func _is_test_environment() -> bool:
	if OS.get_environment("ODISEA_QUIET_PERFMON").to_lower() in ["1", "true", "yes", "on"]:
		return true
	if Engine.has_singleton("GdUnit3"):
		return Engine.get_singleton("GdUnit3").is_test_suite()
	return false

func _is_disabled_for_current_run() -> bool:
	var hard_disable = OS.get_environment("ODISEA_DISABLE_PERFMON").to_lower()
	if hard_disable in ["1", "true", "yes", "on"]:
		return true
	var in_rl = OS.get_environment("ANNA_RL_MODE").to_lower() in ["1", "true", "yes", "on"]
	var disable_in_rl = OS.get_environment("ODISEA_DISABLE_PERFMON_IN_RL")
	if disable_in_rl == "":
		disable_in_rl = "1"
	var disable_rl = disable_in_rl.to_lower() in ["1", "true", "yes", "on"]
	return in_rl and disable_rl

func _process(_delta):
	# Optimization for HTML5/Mobile: throttle metric gathering to 10Hz
	if OS.get_name() == "HTML5" or OS.has_touchscreen_ui_hint():
		if Engine.get_idle_frames() % 6 != 0:
			return

	var now_usec := OS.get_ticks_usec()
	_frame_start_time = now_usec
	var frame_gap_ms := 0.0
	if _last_process_tick_usec > 0:
		frame_gap_ms = float(now_usec - _last_process_tick_usec) / 1000.0
	_last_process_tick_usec = now_usec
	_last_frame_gap_ms = frame_gap_ms

	# 1. Gather Global Metrics
	var fps = Performance.get_monitor(Performance.TIME_FPS)
	var process_time = Performance.get_monitor(Performance.TIME_PROCESS)
	var physics_time = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var draw_calls = 0
	if Performance.get("RENDER_DRAW_CALLS") != null:
		draw_calls = Performance.get_monitor(Performance.RENDER_DRAW_CALLS)
	var node_count = 0
	if Performance.get("OBJECT_NODE_COUNT") != null:
		node_count = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)

	if _capture_active:
		_capture_samples.append({
			"fps": fps,
			"process_ms": process_time * 1000.0,
			"physics_ms": physics_time * 1000.0,
			"frame_gap_ms": frame_gap_ms,
			"draw_calls": draw_calls,
			"node_count": node_count
		})

	# 2. Lag Spike Detection
	if _last_fps - fps > LAG_SPIKE_THRESHOLD_FPS:
		_report_lag_spike(fps, _last_fps, process_time, physics_time, draw_calls, node_count, frame_gap_ms)
	_last_fps = fps

	# 3. CPU Budget Check (throttled)
	if process_time > (CPU_BUDGET_MS * LOG_TRIGGER_PERCENT * 0.001):
		if not _suppress_runtime_logs:
			var current_time = OS.get_ticks_msec()
			if current_time - _last_cpu_warning_time > (CPU_WARNING_INTERVAL_SEC * 1000.0):
				_last_cpu_warning_time = current_time
				print("[PerformanceMonitor] WARNING: CPU Budget > 70%% (%.4f ms)" % (process_time * 1000.0))

	# 4. Debug Logic: Cull Distance
	if debug_cull_distance_enabled:
		_apply_cull_distance()

	# 5. Clear profiling accumulators for next frame
	_node_profiling_accumulators.clear()
	_node_profiling_calls.clear()

	# 6. Cleanup Dead References
	if Engine.get_frames_drawn() % 600 == 0: # Every ~10 seconds
		_cleanup_monitored_nodes()
		_cleanup_measurement_cache()

# --- Instrumentation API ---

func register_monitored_node(node: Node):
	if not is_instance_valid(node): return
	_monitored_nodes.append(weakref(node))
	# Also ensure it's in relevant groups for other debug switches
	if node.name.match("*Drone*") or node.name.match("*Enemy*") or node.name.match("*AI*"):
		if not node.is_in_group("ai_agents"):
			node.add_to_group("ai_agents")

func save_performance_snapshot(tag: String):
	# Save current average metrics to a list
	var fps = Performance.get_monitor(Performance.TIME_FPS)
	var process_t = Performance.get_monitor(Performance.TIME_PROCESS)
	var physics_t = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var draw_c = 0
	if Performance.get("RENDER_DRAW_CALLS") != null:
		draw_c = Performance.get_monitor(Performance.RENDER_DRAW_CALLS)
	var node_c = 0
	if Performance.get("OBJECT_NODE_COUNT") != null:
		node_c = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)

	var entry = {
		"tag": tag,
		"timestamp": OS.get_unix_time(),
		"fps": fps,
		"process_time_ms": process_t * 1000.0,
		"physics_time_ms": physics_t * 1000.0,
		"draw_calls": draw_c,
		"node_count": node_c
	}

	_append_snapshot(entry)

func _append_snapshot(entry: Dictionary):
	var data = []
	var file = File.new()
	if file.file_exists(SNAPSHOT_FILE_PATH):
		file.open(SNAPSHOT_FILE_PATH, File.READ)
		var content = file.get_as_text()
		var p = JSON.parse(content)
		if p.error == OK and typeof(p.result) == TYPE_ARRAY:
			data = p.result
		file.close()

	data.append(entry)

	file.open(SNAPSHOT_FILE_PATH, File.WRITE)
	file.store_string(JSON.print(data, "  "))
	file.close()
	print("[PerformanceMonitor] Snapshot saved for tag '%s'" % entry["tag"])

func _cleanup_monitored_nodes():
	var valid_nodes = []
	for wr in _monitored_nodes:
		if wr.get_ref():
			valid_nodes.append(wr)
	_monitored_nodes = valid_nodes

func _cleanup_measurement_cache():
	var stale_measurements := []
	for node_id in _node_measurement_start.keys():
		if not _node_profiling_accumulators.has(node_id) and not _node_profiling_calls.has(node_id):
			stale_measurements.append(node_id)
	for node_id in stale_measurements:
		_node_measurement_start.erase(node_id)

func measure_start(node: Object, _tag: String = ""):
	# Store start time for this node instance
	if not _detailed_node_profiling_enabled:
		return
	if not is_instance_valid(node):
		return
	var node_id = int(node.get_instance_id())
	_profiled_node_names[node_id] = String(node.name)
	if node is Node and node.is_inside_tree():
		_profiled_node_paths[node_id] = str(node.get_path())
	else:
		_profiled_node_paths[node_id] = ""
	_node_measurement_start[node_id] = OS.get_ticks_usec()

func measure_end(node: Object, _tag: String = ""):
	if not _detailed_node_profiling_enabled:
		return
	if not is_instance_valid(node):
		return
	var node_id = int(node.get_instance_id())
	if not _node_measurement_start.has(node_id):
		return

	var start = _node_measurement_start[node_id]
	var end = OS.get_ticks_usec()
	var duration = end - start

	if not _node_profiling_accumulators.has(node_id):
		_node_profiling_accumulators[node_id] = 0
		_node_profiling_calls[node_id] = 0

	_node_profiling_accumulators[node_id] += duration
	_node_profiling_calls[node_id] += 1
	_node_measurement_start.erase(node_id)

func _exit_tree():
	_monitored_nodes.clear()
	_node_profiling_accumulators.clear()
	_node_profiling_calls.clear()
	_node_measurement_start.clear()
	_profiled_node_names.clear()
	_profiled_node_paths.clear()
	_capture_active = false
	_capture_samples.clear()

# --- Debug Actions ---

func set_debug_freeze_logic(value: bool):
	debug_freeze_logic = value
	get_tree().paused = value
	print("[PerformanceMonitor] Debug Freeze Logic: ", value)

func step_frame():
	if get_tree().paused:
		get_tree().paused = false
		yield(get_tree(), "idle_frame")
		get_tree().paused = true
		print("[PerformanceMonitor] Stepped 1 frame")

func set_debug_cull_distance(enabled: bool, radius: float = 50.0):
	debug_cull_distance_enabled = enabled
	debug_cull_radius = radius
	print("[PerformanceMonitor] Cull Distance: ", enabled, " Radius: ", radius)
	if not enabled:
		# Restore visibility
		_restore_visibility()

func set_debug_disable_ai(value: bool):
	debug_disable_ai = value
	var agents = get_tree().get_nodes_in_group("ai_agents")
	for agent in agents:
		if agent.has_method("set_process"):
			agent.set_process(not value)
		if agent.has_method("set_physics_process"):
			agent.set_physics_process(not value)
		if agent.has_method("stop") and value:
			agent.stop()
	print("[PerformanceMonitor] Disable AI: ", value)

func set_debug_collision_shapes(value: bool):
	debug_collision_shapes = value
	get_tree().debug_collisions_hint = value
	print("[PerformanceMonitor] Show Collision Shapes: ", value)

# --- Internal Helpers ---

func _apply_cull_distance():
	var camera = get_viewport().get_camera()
	if not is_instance_valid(camera): return

	var cam_pos = camera.global_transform.origin

	# Iterate monitored nodes (and maybe scan others?)
	# For now, stick to monitored nodes to avoid traversing the whole tree
	for wr in _monitored_nodes:
		var node = wr.get_ref()
		if is_instance_valid(node) and node is Spatial:
			var dist = node.global_transform.origin.distance_to(cam_pos)
			var should_be_visible = dist <= debug_cull_radius
			if node.visible != should_be_visible:
				node.visible = should_be_visible
				# Also disable processing for culled nodes?
				if node.has_method("set_process"): node.set_process(should_be_visible)
				if node.has_method("set_physics_process"): node.set_physics_process(should_be_visible)

func _restore_visibility():
	for wr in _monitored_nodes:
		var node = wr.get_ref()
		if is_instance_valid(node) and node is Spatial:
			node.visible = true
			if node.has_method("set_process"): node.set_process(true)
			if node.has_method("set_physics_process"): node.set_physics_process(true)

func _report_lag_spike(fps, prev_fps, process_t, physics_t, draw_c, node_c, frame_gap_ms: float):
	var now_msec := OS.get_ticks_msec()
	var drop: float = float(prev_fps) - float(fps)
	if not _suppress_runtime_logs and _should_log_lag_spike(now_msec, drop):
		print("[PerformanceMonitor] LAG SPIKE DETECTED! FPS dropped from %.1f to %.1f" % [prev_fps, fps])
		_last_lag_log_time_msec = now_msec
	emit_signal("lag_spike_detected", fps, drop)

	var report = {
		"timestamp": OS.get_unix_time(),
		"fps": fps,
		"drop": drop,
		"process_time_ms": process_t * 1000.0,
		"physics_time_ms": physics_t * 1000.0,
		"frame_gap_ms": frame_gap_ms,
		"draw_calls": draw_c,
		"node_count": node_c,
		"heavy_nodes": _get_top_heavy_nodes()
	}

	_save_report_throttled(report, now_msec)

func _should_log_lag_spike(now_msec: int, drop: float) -> bool:
	if _last_lag_log_time_msec <= 0:
		return true
	if drop >= LAG_SPIKE_THRESHOLD_FPS * 2.0:
		return true
	var interval_msec := int(LAG_LOG_INTERVAL_SEC * 1000.0)
	return now_msec - _last_lag_log_time_msec >= interval_msec

func _get_top_heavy_nodes() -> Array:
	var list = []
	for node_id in _node_profiling_accumulators.keys():
		list.append({
			"name": _profiled_node_names.get(node_id, "node_%s" % str(node_id)),
			"path": _profiled_node_paths.get(node_id, ""),
			"time_usec": _node_profiling_accumulators[node_id],
			"calls": _node_profiling_calls.get(node_id, 0)
		})

	list.sort_custom(self, "_sort_by_time_desc")

	# Return Top 10
	var result = []
	for i in range(min(list.size(), 10)):
		result.append(list[i])
	return result

func _sort_by_time_desc(a, b):
	return a["time_usec"] > b["time_usec"]

func _save_report(data: Dictionary):
	var file = File.new()
	file.open(LOG_FILE_PATH, File.WRITE)
	file.store_string(JSON.print(data, "  "))
	file.close()
	print("[PerformanceMonitor] Report saved to ", LOG_FILE_PATH)

func _save_report_throttled(data: Dictionary, now_msec: int) -> void:
	var drop := float(data.get("drop", 0.0))
	var interval_msec := _get_report_write_interval_msec()
	var should_write := false

	if _last_report_write_time_msec <= 0:
		should_write = true
	elif now_msec - _last_report_write_time_msec >= interval_msec:
		should_write = true
	elif drop >= _last_saved_drop + REPORT_DROP_BYPASS_DELTA:
		# Persist immediately if current spike is significantly worse than last saved one.
		should_write = true

	if not should_write:
		_suppressed_report_count += 1
		return

	var payload := data.duplicate(true)
	if _suppressed_report_count > 0:
		payload["suppressed_reports"] = _suppressed_report_count
	_suppressed_report_count = 0
	_last_report_write_time_msec = now_msec
	_last_saved_drop = drop
	call_deferred("_save_report", payload)

func _get_report_write_interval_msec() -> int:
	var interval_sec := REPORT_WRITE_INTERVAL_SEC
	return int(interval_sec * 1000.0)

func start_capture(tag: String = "capture") -> void:
	_capture_active = true
	_capture_tag = tag
	_capture_start_usec = OS.get_ticks_usec()
	_capture_samples.clear()

func stop_capture(extra_tag: String = "") -> Dictionary:
	if not _capture_active:
		return {}

	var final_tag := _capture_tag
	if extra_tag != "":
		final_tag = extra_tag

	var elapsed_sec := max(0.0, float(OS.get_ticks_usec() - _capture_start_usec) / 1000000.0)
	var summary := _build_capture_summary(final_tag, elapsed_sec, _capture_samples)
	_capture_active = false
	_capture_tag = ""
	_capture_samples.clear()
	_append_capture_summary(summary)

	print("[PerformanceMonitor][CAPTURE] ", JSON.print(summary))
	return summary

func _build_capture_summary(tag: String, duration_sec: float, samples: Array) -> Dictionary:
	if samples.empty():
		return {
			"tag": tag,
			"timestamp": OS.get_unix_time(),
			"duration_sec": duration_sec,
			"sample_count": 0
		}

	var fps_values := []
	var process_values := []
	var physics_values := []
	var frame_gap_values := []
	var draw_values := []
	var node_values := []

	var sum_fps := 0.0
	var sum_process := 0.0
	var sum_physics := 0.0
	var sum_frame_gap := 0.0
	var sum_draw := 0.0
	var sum_nodes := 0.0
	var frames_lt_30 := 0
	var frames_lt_50 := 0

	for sample in samples:
		var fps := float(sample.get("fps", 0.0))
		var process_ms := float(sample.get("process_ms", 0.0))
		var physics_ms := float(sample.get("physics_ms", 0.0))
		var frame_gap_ms := float(sample.get("frame_gap_ms", 0.0))
		var draw_calls := int(sample.get("draw_calls", 0))
		var node_count := int(sample.get("node_count", 0))

		fps_values.append(fps)
		process_values.append(process_ms)
		physics_values.append(physics_ms)
		frame_gap_values.append(frame_gap_ms)
		draw_values.append(draw_calls)
		node_values.append(node_count)

		sum_fps += fps
		sum_process += process_ms
		sum_physics += physics_ms
		sum_frame_gap += frame_gap_ms
		sum_draw += draw_calls
		sum_nodes += node_count
		if fps < 30.0:
			frames_lt_30 += 1
		if fps < 50.0:
			frames_lt_50 += 1

	fps_values.sort()
	process_values.sort()
	physics_values.sort()
	frame_gap_values.sort()
	draw_values.sort()
	node_values.sort()

	var count := float(samples.size())
	return {
		"tag": tag,
		"timestamp": OS.get_unix_time(),
		"duration_sec": duration_sec,
		"sample_count": samples.size(),
		"avg_fps": sum_fps / count,
		"min_fps": float(fps_values[0]),
		"p1_fps": _percentile(fps_values, 1.0),
		"p5_fps": _percentile(fps_values, 5.0),
		"avg_process_ms": sum_process / count,
		"p95_process_ms": _percentile(process_values, 95.0),
		"avg_physics_ms": sum_physics / count,
		"p95_physics_ms": _percentile(physics_values, 95.0),
		"avg_frame_gap_ms": sum_frame_gap / count,
		"p95_frame_gap_ms": _percentile(frame_gap_values, 95.0),
		"max_frame_gap_ms": float(frame_gap_values[frame_gap_values.size() - 1]),
		"avg_draw_calls": sum_draw / count,
		"p95_draw_calls": _percentile(draw_values, 95.0),
		"avg_node_count": sum_nodes / count,
		"max_node_count": int(node_values[node_values.size() - 1]),
		"frames_lt_30": frames_lt_30,
		"frames_lt_50": frames_lt_50
	}

func _percentile(sorted_values: Array, percentile: float) -> float:
	if sorted_values.empty():
		return 0.0
	var p := clamp(percentile, 0.0, 100.0) / 100.0
	var idx := int(round((sorted_values.size() - 1) * p))
	return float(sorted_values[idx])

func _append_capture_summary(entry: Dictionary) -> void:
	var data := []
	var file := File.new()
	if file.file_exists(CAPTURE_FILE_PATH):
		if file.open(CAPTURE_FILE_PATH, File.READ) == OK:
			var content := file.get_as_text()
			file.close()
			var parsed := JSON.parse(content)
			if parsed.error == OK and typeof(parsed.result) == TYPE_ARRAY:
				data = parsed.result

	data.append(entry)

	if file.open(CAPTURE_FILE_PATH, File.WRITE) != OK:
		printerr("[PerformanceMonitor] Failed to write capture file: ", CAPTURE_FILE_PATH)
		return
	file.store_string(JSON.print(data, "  "))
	file.close()

func scan_scene():
	# Helper to find relevant nodes in the current scene and register them
	var root = get_tree().current_scene
	if not root: return
	_recursive_scan(root)

func _recursive_scan(node: Node):
	if node is KinematicBody or node.has_method("step") or node.is_in_group("interactable"):
		register_monitored_node(node)

	for child in node.get_children():
		_recursive_scan(child)
