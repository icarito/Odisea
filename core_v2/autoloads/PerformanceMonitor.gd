extends Node

# PerformanceMonitor.gd
# Global Singleton for Telemetry, Profiling and Debugging
# Part of OdiseaOS Telemetry System

const LOG_FILE_PATH := "user://performance_log.json"
const SNAPSHOT_FILE_PATH := "user://performance_snapshots.json"
const LAG_SPIKE_THRESHOLD_FPS := 20.0
const CPU_BUDGET_MS := 16.6
const LOG_TRIGGER_PERCENT := 0.70 # 70% of CPU Budget

# --- Debug Flags ---
var debug_freeze_logic := false setget set_debug_freeze_logic
var debug_cull_distance_enabled := false
var debug_cull_radius := 50.0
var debug_step_mode := false # Managed via freeze logic + manual step
var debug_disable_ai := false setget set_debug_disable_ai
var debug_collision_shapes := false setget set_debug_collision_shapes

# --- Metrics State ---
var _frame_start_time := 0
var _last_fps := 60.0
var _monitored_nodes := [] # Array of WeakRef
var _node_profiling_accumulators := {} # { node_ref: accumulated_usec }
var _node_profiling_calls := {} # { node_ref: call_count }
var _node_measurement_start := {} # { node_ref: start_usec }

# --- Signals ---
signal lag_spike_detected(fps, drop)

func _ready():
	pause_mode = Node.PAUSE_MODE_PROCESS # Always run, even when tree is paused
	print("[PerformanceMonitor] Initialized")

func _process(delta):
	_frame_start_time = OS.get_ticks_usec()

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

	# 2. Lag Spike Detection
	if _last_fps - fps > LAG_SPIKE_THRESHOLD_FPS:
		_report_lag_spike(fps, _last_fps, process_time, physics_time, draw_calls, node_count)
	_last_fps = fps

	# 3. CPU Budget Check
	if process_time > (CPU_BUDGET_MS * LOG_TRIGGER_PERCENT * 0.001):
		# Trigger logging if sustainable budget is exceeded
		# We throttle this to avoid spamming logs every frame
		if Engine.get_frames_drawn() % 60 == 0:
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
	var stale_keys := []
	for node in _node_measurement_start.keys():
		if not is_instance_valid(node):
			stale_keys.append(node)
	for key in stale_keys:
		_node_measurement_start.erase(key)

func measure_start(node: Object, _tag: String = ""):
	# Store start time for this node instance
	_node_measurement_start[node] = OS.get_ticks_usec()

func measure_end(node: Object, _tag: String = ""):
	if not _node_measurement_start.has(node): return

	var start = _node_measurement_start[node]
	var end = OS.get_ticks_usec()
	var duration = end - start

	if not _node_profiling_accumulators.has(node):
		_node_profiling_accumulators[node] = 0
		_node_profiling_calls[node] = 0

	_node_profiling_accumulators[node] += duration
	_node_profiling_calls[node] += 1
	_node_measurement_start.erase(node)

func _exit_tree():
	_monitored_nodes.clear()
	_node_profiling_accumulators.clear()
	_node_profiling_calls.clear()
	_node_measurement_start.clear()

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

func _report_lag_spike(fps, prev_fps, process_t, physics_t, draw_c, node_c):
	print("[PerformanceMonitor] LAG SPIKE DETECTED! FPS dropped from %.1f to %.1f" % [prev_fps, fps])
	emit_signal("lag_spike_detected", fps, prev_fps - fps)

	var report = {
		"timestamp": OS.get_unix_time(),
		"fps": fps,
		"drop": prev_fps - fps,
		"process_time_ms": process_t * 1000.0,
		"physics_time_ms": physics_t * 1000.0,
		"draw_calls": draw_c,
		"node_count": node_c,
		"heavy_nodes": _get_top_heavy_nodes()
	}

	_save_report(report)

func _get_top_heavy_nodes() -> Array:
	var list = []
	for node in _node_profiling_accumulators:
		if is_instance_valid(node):
			list.append({
				"name": node.name,
				"path": str(node.get_path()),
				"time_usec": _node_profiling_accumulators[node],
				"calls": _node_profiling_calls[node]
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
