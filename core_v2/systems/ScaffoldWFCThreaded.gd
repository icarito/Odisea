extends Node
class_name ScaffoldWFCThreaded

# FD-050.2: Threaded WFC wrapper + progressive instancing

signal generation_done(chunk_key, grid_data)
signal generation_failed(chunk_key)
signal instancing_done(parent_node)

export(int, 1, 64) var instances_per_frame := 8 setget set_instances_per_frame
export(int, 1, 32) var max_pending_jobs := 4
export(int, 1, 16) var rebuilds_per_frame := 1

var _thread: Thread = null
var _mutex: Mutex = null
var _pending: Array = []
var _should_exit: bool = false
# Whether a real worker Thread actually runs here. Some HTML5 builds (the non-threads
# export) let Thread.start() return without ever running the worker — OS.has_feature
# ("threads") doesn't always distinguish them reliably across engine/browser combos.
# So instead of trusting the flag we PROBE: spin up a throwaway thread that sets a
# value, join it with a short budget, and check the value landed. If it didn't, threads
# are effectively unavailable and we fall back to solving grids synchronously on the
# main thread (a few per frame in _process so the frame doesn't stall). WFCSolverCore is
# a plain RefCounted, safe to run inline. Set by _probe_thread_support() in _init.
var _threads_supported: bool = false
var _probe_value: int = 0
# Synchronous-mode budget: how many grids to solve per frame when no worker thread.
const SYNC_GRIDS_PER_FRAME := 1

var _instance_queue: Array = []
var _rebuild_queue: Array = []  # nodes waiting for _rebuild(), processed 1 per frame
var _instance_pending_count: Dictionary = {}  # parent_node -> int, items still queued

func _init() -> void:
	_mutex = Mutex.new()
	set_process(false)
	_threads_supported = _probe_thread_support()

# Actually try to run a thread. OS.has_feature("threads") is NOT reliable here — it
# returns false on Godot 3.6 native/headless Linux builds where threads work fine, so
# trusting it forced MST on desktop. The only trustworthy signal is to spawn a thread
# and see if its body executed. Returns true only if it did.
func _probe_thread_support() -> bool:
	_probe_value = 0
	var probe := Thread.new()
	var err = probe.start(self, "_thread_probe_body", null)
	if err != OK:
		return false  # engine refused to start a thread → none available
	# Join (blocks until the body returns). Instant on a working build; on a real
	# no-threads build start() above would have errored.
	probe.wait_to_finish()
	return _probe_value == 1

func _thread_probe_body(_userdata) -> void:
	_probe_value = 1

# True if a real worker thread runs here (probed, not just feature-flagged).
func has_working_threads() -> bool:
	return _threads_supported

func _ready():
	if _threads_supported:
		_start_worker()
	else:
		# No worker thread; grids are solved inline in _process. Keep processing on
		# so queued generation jobs get drained.
		set_process(true)

func _exit_tree():
	stop()

func request_grid(chunk_key, params: Dictionary) -> void:
	if _threads_supported and (_thread == null or not _thread.is_active()):
		_start_worker()
	_mutex.lock()
	if _pending.size() >= max_pending_jobs:
		_mutex.unlock()
		call_deferred("emit_signal", "generation_failed", chunk_key)
		return
	_pending.append({"chunk_key": chunk_key, "params": params})
	_mutex.unlock()
	if not _threads_supported:
		set_process(true)  # ensure the inline solver drains the queue

func set_instances_per_frame(value: int) -> void:
	instances_per_frame = max(1, value)

func get_pending_job_count() -> int:
	_mutex.lock()
	var count = _pending.size()
	_mutex.unlock()
	return count

func _start_worker() -> void:
	if _thread and _thread.is_active():
		return
	_should_exit = false
	_thread = Thread.new()
	_thread.start(self, "_worker_loop", null)

func _worker_loop(_userdata) -> void:
	# We use a WFCSolverCore (plain RefCounted) so no scene-tree interaction
	# happens inside the thread. ScaffoldWFCGenerator (Spatial) must NEVER be
	# instantiated inside a worker thread in Godot 3.
	while not _should_exit:
		_mutex.lock()
		var job = null
		if not _pending.empty():
			job = _pending.pop_front()
		_mutex.unlock()

		if job == null:
			OS.delay_msec(4)
			continue

		var params = job.params
		var chunk_key = job.chunk_key
		var solver = WFCSolverCore.new()
		solver.apply_params(params)
		var grid = solver.generate_grid_data(params.get("seed", -1))
		if grid.empty():
			call_deferred("emit_signal", "generation_failed", chunk_key)
		else:
			call_deferred("emit_signal", "generation_done", chunk_key, grid)

func stop() -> void:
	_should_exit = true
	if _thread and _thread.is_active():
		_thread.wait_to_finish()
	_thread = null

func cancel_instancing_for(parent_node: Spatial) -> void:
	var i = _instance_queue.size() - 1
	while i >= 0:
		if _instance_queue[i].parent == parent_node:
			_instance_queue.remove(i)
		i -= 1
	_instance_pending_count.erase(parent_node)

# --- Progressive instancing ---

func enqueue_grid_for_instancing(parent_node: Spatial, grid: Array, grid_width: int, grid_depth: int, cell_size: float, generator_ref, chunk_offset: Vector3 = Vector3.ZERO) -> void:
	var count = 0
	for y in range(grid_depth):
		for x in range(grid_width):
			var state = grid[y * grid_width + x]
			var v = _state_variant(state)
			if state == null or v == null or _variant_id(v) == "EMPTY":
				continue
			_instance_queue.append({
				"parent": parent_node,
				"x": x,
				"y": y,
				"state": state,
				"gen": generator_ref,
				"grid_width": grid_width,
				"grid_depth": grid_depth,
				"cell_size": cell_size,
				"offset": chunk_offset
			})
			count += 1
	if count > 0:
		_instance_pending_count[parent_node] = _instance_pending_count.get(parent_node, 0) + count
	else:
		emit_signal("instancing_done", parent_node)
	set_process(true)

export(float, 1.0, 14.0) var rebuild_budget_ms := 8.0

func _solve_one_grid(job) -> void:
	var params = job.params
	var chunk_key = job.chunk_key
	var solver = WFCSolverCore.new()
	solver.apply_params(params)
	var grid = solver.generate_grid_data(params.get("seed", -1))
	if grid == null or grid.empty():
		emit_signal("generation_failed", chunk_key)
	else:
		emit_signal("generation_done", chunk_key, grid)

func _process(_delta) -> void:
	# Synchronous grid generation when no worker thread (non-threads HTML5). Solve a
	# small budget per frame so the queue drains without stalling.
	if not _threads_supported:
		var solved := 0
		while solved < SYNC_GRIDS_PER_FRAME:
			_mutex.lock()
			var job = null
			if not _pending.empty():
				job = _pending.pop_front()
			_mutex.unlock()
			if job == null:
				break
			_solve_one_grid(job)
			solved += 1

	var instance_count = 0
	while instance_count < instances_per_frame and not _instance_queue.empty():
		var entry = _instance_queue.pop_front()
		var parent = entry.parent
		_instance_one(entry)
		instance_count += 1
		if _instance_pending_count.has(parent):
			_instance_pending_count[parent] -= 1
			if _instance_pending_count[parent] <= 0:
				_instance_pending_count.erase(parent)
				emit_signal("instancing_done", parent)

	var rebuild_count = 0
	while rebuild_count < rebuilds_per_frame and not _rebuild_queue.empty():
		var node = _rebuild_queue.pop_front()
		if is_instance_valid(node):
			node.call("_rebuild")
		rebuild_count += 1

	# In synchronous mode keep processing while grids are still queued; otherwise stop
	# once the instancing/rebuild queues are drained.
	var sync_pending := false
	if not _threads_supported:
		_mutex.lock()
		sync_pending = not _pending.empty()
		_mutex.unlock()
	if _instance_queue.empty() and _rebuild_queue.empty() and not sync_pending:
		set_process(false)

func _instance_one(entry: Dictionary) -> void:
	var gen = entry.gen
	var state = entry.state
	var v = _state_variant(state)
	var x: int = entry.x
	var y: int = entry.y
	var cell_size: float = entry.cell_size
	var offset: Vector3 = entry.offset
	var parent: Spatial = entry.parent

	if v == null:
		push_warning("[ScaffoldWFC] _instance_one: null variant, skipping cell (%d,%d)" % [x, y])
		return
	if not is_instance_valid(parent) or not is_instance_valid(gen):
		return
	var vid = _variant_id(v)
	if not gen.modules.has(vid) or gen.modules[vid] == null:
		return

	var inst = gen.modules[vid].instance()
	parent.add_child(inst)
	var deck_local_y = inst.platform_height
	inst.translation = Vector3(
		offset.x + x * cell_size,
		offset.y + _state_base_height(state) - deck_local_y,
		offset.z + y * cell_size
	)
	inst.rotation_degrees.y = -_variant_rotation(v)
	inst.set("support_base_local_y", deck_local_y - _state_base_height(state))

	if vid == "W" or vid == "R" or vid == "G":
		gen._apply_local_dims(inst, gen._lane_width(), cell_size)
		gen._apply_rails_from_connections(inst, v)
		gen._apply_opening_widths_from_connections(inst, v)
	elif vid == "P":
		gen._apply_local_dims(inst, cell_size, cell_size)
		gen._apply_rails_from_connections(inst, v)
		gen._apply_opening_widths_from_connections(inst, v)
	elif vid == "S":
		gen._apply_local_dims(inst, gen._lane_width(), cell_size)
		gen._apply_port_heights_to_front_back(inst, v)
		gen._apply_rails_from_connections(inst, v)
		gen._apply_opening_widths_from_connections(inst, v)
	else:
		gen._apply_local_dims(inst, cell_size, cell_size)
		gen._apply_rails_from_connections(inst, v)
		gen._apply_opening_widths_from_connections(inst, v)

	if inst.has_method("_rebuild"):
		_rebuild_queue.append(inst)

func _state_variant(state):
	if state == null:
		return null
	if typeof(state) == TYPE_DICTIONARY:
		return state.get("variant", null)
	return state.variant

func _state_base_height(state) -> float:
	if typeof(state) == TYPE_DICTIONARY:
		return float(state.get("base_height", 0.0))
	return state.base_height

func _variant_id(v) -> String:
	if v == null:
		return ""
	if typeof(v) == TYPE_DICTIONARY:
		return String(v.get("id", ""))
	return v.id

func _variant_rotation(v) -> int:
	if typeof(v) == TYPE_DICTIONARY:
		return int(v.get("rotation", 0))
	return v.rotation
