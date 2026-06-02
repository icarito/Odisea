extends Node
class_name ScaffoldWFCThreaded

# FD-050.2: Threaded WFC wrapper + progressive instancing

signal generation_done(chunk_key, grid_data)
signal generation_failed(chunk_key)

export(int, 1, 64) var instances_per_frame := 8 setget set_instances_per_frame
export(int, 1, 32) var max_pending_jobs := 4

var _thread: Thread = null
var _mutex: Mutex = null
var _pending: Array = []
var _should_exit: bool = false

var _instance_queue: Array = []
var _rebuild_queue: Array = []  # nodes waiting for _rebuild(), processed 1 per frame

func _init() -> void:
	_mutex = Mutex.new()
	set_process(false)

func _ready():
	_start_worker()

func _exit_tree():
	stop()

func request_grid(chunk_key, params: Dictionary) -> void:
	if _thread == null or not _thread.is_active():
		_start_worker()
	_mutex.lock()
	if _pending.size() >= max_pending_jobs:
		_mutex.unlock()
		call_deferred("emit_signal", "generation_failed", chunk_key)
		return
	_pending.append({"chunk_key": chunk_key, "params": params})
	_mutex.unlock()

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
			OS.delay_msec(16)
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

# --- Progressive instancing ---

func enqueue_grid_for_instancing(parent_node: Spatial, grid: Array, grid_width: int, grid_depth: int, cell_size: float, generator_ref, chunk_offset: Vector3 = Vector3.ZERO) -> void:
	for y in range(grid_depth):
		for x in range(grid_width):
			var state = grid[y * grid_width + x]
			if state == null or state.variant == null or state.variant.id == "EMPTY":
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
	set_process(true)

func _process(_delta) -> void:
	# If rebuilds are pending, do one and skip instancing this frame.
	# Each _rebuild call can take 200-600ms, so we never do both in the same frame.
	if not _rebuild_queue.empty():
		var node = _rebuild_queue.pop_front()
		if is_instance_valid(node):
			node.call("_rebuild")
		return

	if _instance_queue.empty():
		set_process(false)
		return
	var count = 0
	while count < instances_per_frame and not _instance_queue.empty():
		var entry = _instance_queue.pop_front()
		_instance_one(entry)
		count += 1

func _instance_one(entry: Dictionary) -> void:
	var gen = entry.gen
	var state = entry.state
	var v = state.variant
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
	if not gen.modules.has(v.id) or gen.modules[v.id] == null:
		return

	var inst = gen.modules[v.id].instance()
	parent.add_child(inst)
	var deck_local_y = inst.platform_height
	inst.translation = Vector3(
		offset.x + x * cell_size,
		offset.y + state.base_height - deck_local_y,
		offset.z + y * cell_size
	)
	inst.rotation_degrees.y = -v.rotation
	inst.set("support_base_local_y", deck_local_y - state.base_height)

	var vid = v.id
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
