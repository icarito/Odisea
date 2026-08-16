extends PropBaseV2
class_name ElevatorController
tool

# ElevatorController.gd
# Manages elevator logic, queueing requests, and commanding the platform.

signal door_opened(floor_idx)
signal door_closed(floor_idx)
# Where the car is and where it is headed. For display only (cabin panel): the
# elevator never reads it back, so it stays outside the deterministic path.
signal floor_state_changed(current_floor, target_floor, is_moving)

export(NodePath) var platform_path
export(NodePath) var floors_path = NodePath("Floors")
export(float) var door_open_wait := 2.0 # seconds door stays open

# Floor stops as explicit local heights — the single source of truth for the
# layout. The prop used to infer it from its own node structure (one authored
# Floor child per stop, doors scanning their siblings to find the next one), so
# retargeting it to a building with different storey spacing meant editing the
# scene tree. With this filled in, the first Floors/* child acts as the template
# and every stop is cloned from it. Empty keeps the authored children untouched.
export(Array, float) var floor_heights := []
# Fence enclosing the shaft. Its height follows the topmost stop instead of being
# authored by hand, so it can never come up short of the last floor.
export(NodePath) var shaft_fence_path = NodePath("MetalFence")
export(NodePath) var shaft_cap_path = NodePath("MetalFence/Path2/CSGCylinder")
export(float) var shaft_fence_headroom := 5.5

var requests = []
var current_floor = 0
var target_floor = -1
var is_moving = false
var floor_nodes = {}
var floor_doors = {} # floor_idx -> door node (DualSlidingObjectV2)
var _sfx_move: SFXComponentV2 = null
var _sfx_arrival: SFXComponentV2 = null
var _pending_snapshot = null
var _stop_heights := []  # World Y per stop, index-aligned. See _cache_stop_heights().

onready var platform = get_node(platform_path) if platform_path else null
onready var floors_container = get_node(floors_path) if floors_path else null

func _ready():
	_cache_sfx_nodes()
	_sync_floors()

	# Discover and connect floor inputs
	if floors_container:
		for floor_node in floors_container.get_children():
			var f_idx = _find_floor_input(floor_node)
			if f_idx != -1:
				floor_nodes[f_idx] = floor_node
				# Discover door child if present
				var door = floor_node.get_node_or_null("Door")
				if door:
					floor_doors[f_idx] = door


	# Connect internal "next" button if present on platform
	if platform:
		for child in platform.get_children():
			if child.has_signal("input_triggered") and child.get("floor_index") == -1:
				if not child.is_connected("input_triggered", self , "_on_floor_request"):
					child.connect("input_triggered", self , "_on_floor_request")


	if platform:
		if not platform.is_connected("arrived_at_floor", self , "_on_arrived"):
			platform.connect("arrived_at_floor", self , "_on_arrived")
		if platform.has_signal("stopped") and not platform.is_connected("stopped", self , "_on_platform_stopped"):
			platform.connect("stopped", self , "_on_platform_stopped")

	# Open door at starting floor
	if not Engine.editor_hint:
		_open_door(current_floor)
	_cache_stop_heights()
	if not Engine.editor_hint:
		call_deferred("_refresh_occlusion")
	if _pending_snapshot != null:
		_apply_snapshot(_pending_snapshot)
		_pending_snapshot = null
	if not Engine.editor_hint:
		_emit_floor_state()

# The stops are cloned during _ready, so the copies land after PropDitherManager
# has already swept the scene, and ElevatorDoor rebuilds its shaft fittings later
# still. That left the authored floor's shaft poles solid while every clone
# faded. One sweep once the shaft is final settles the whole prop.
func _refresh_occlusion() -> void:
	var dither = get_node_or_null("/root/PropDitherManager")
	if dither and dither.has_method("refresh_occlusion_for_node"):
		dither.refresh_occlusion_for_node(self)


# Lays the Floors container out from floor_heights, cloning the first authored
# child as the template. Each stop is told its own index and the exact distance to
# the one above, so no node has to look at its siblings to work out where it sits.
func _sync_floors() -> void:
	if floor_heights.empty() or floors_container == null:
		return
	if floors_container.get_child_count() == 0:
		push_warning("ElevatorController: Floors needs one authored child to use as the stop template.")
		return

	var template: Spatial = floors_container.get_child(0) as Spatial
	if template == null:
		return

	while floors_container.get_child_count() > floor_heights.size():
		var extra: Node = floors_container.get_child(floors_container.get_child_count() - 1)
		floors_container.remove_child(extra)
		extra.free()
	while floors_container.get_child_count() < floor_heights.size():
		floors_container.add_child(template.duplicate())

	for index in range(floor_heights.size()):
		var stop: Spatial = floors_container.get_child(index) as Spatial
		if stop == null:
			continue
		stop.name = "Floor%d" % index
		var stop_xform: Transform = stop.transform
		stop_xform.origin.y = float(floor_heights[index])
		stop.transform = stop_xform

		var input: Node = stop.get_node_or_null("Input")
		if input:
			input.set("floor_index", index)
		var door: Node = stop.get_node_or_null("Door")
		if door and door.has_method("set_shaft_span"):
			var is_top: bool = index >= floor_heights.size() - 1
			door.set_shaft_span(0.0 if is_top else float(floor_heights[index + 1]) - float(floor_heights[index]))

	_fit_shaft_fence()

# The shaft fence and its cap have to clear the topmost stop, not sit at a height
# typed in by hand — that is how the fence ended up topping out below the last
# floor. ElevatorDoor reads the cap to clamp the top floor's shaft, so both move
# together.
func _fit_shaft_fence() -> void:
	if floor_heights.empty():
		return
	var base: float = float(floor_heights[0])
	var top: float = base
	for height in floor_heights:
		base = min(base, float(height))
		top = max(top, float(height))

	var fence: Node = get_node_or_null(shaft_fence_path)
	if fence:
		fence.set("height", top - base + shaft_fence_headroom)
	var cap: Spatial = get_node_or_null(shaft_cap_path) as Spatial
	if cap:
		var cap_xform: Transform = cap.transform
		cap_xform.origin.y = top + shaft_fence_headroom
		cap.transform = cap_xform

# --- Public API for cabin controls ---
# The internal call button used to be the only rider-facing input and it could
# only say "next floor", so it wired itself in through input_triggered(-1). A
# panel that names the stops needs to ask for one directly.

func request_floor(floor_idx: int) -> void:
	_on_floor_request(floor_idx)


func get_floor_count() -> int:
	if not floor_nodes.empty():
		return floor_nodes.size()
	return floor_heights.size()


func get_current_floor() -> int:
	return current_floor


# Where the car actually is, in stop units: 2.5 means exactly between the third
# and fourth stop. A cabin display needs this — current_floor only changes on
# arrival, so on its own it cannot show a car in motion.
func get_exact_floor() -> float:
	if platform == null or _stop_heights.size() < 2:
		return float(current_floor)
	var y: float = platform.global_transform.origin.y
	var top: int = _stop_heights.size() - 1
	if y <= float(_stop_heights[0]):
		return 0.0
	if y >= float(_stop_heights[top]):
		return float(top)
	for i in range(top):
		var low: float = float(_stop_heights[i])
		var high: float = float(_stop_heights[i + 1])
		if y >= low and y <= high and high > low:
			return float(i) + (y - low) / (high - low)
	return float(current_floor)


# Stop heights never move once the shaft is laid out, so they are read once
# instead of walking six global_transforms every frame.
func _cache_stop_heights() -> void:
	_stop_heights.clear()
	for i in range(floor_nodes.size()):
		if floor_nodes.has(i):
			_stop_heights.append(floor_nodes[i].global_transform.origin.y)


func is_car_moving() -> bool:
	return is_moving


func _find_floor_input(node: Node) -> int:
	for child in node.get_children():
		if child.has_signal("input_triggered"):
			if not child.is_connected("input_triggered", self , "_on_floor_request"):
				child.connect("input_triggered", self , "_on_floor_request")
			return child.get("floor_index")
	return -1

func _on_floor_request(floor_idx):
	var actual_floor = floor_idx
	if floor_idx == -1:
		var max_f = 0
		for f in floor_nodes.keys():
			if f > max_f:
				max_f = f
		actual_floor = current_floor + 1
		if actual_floor > max_f:
			actual_floor = 0
			

	# Log request
	if not requests.has(actual_floor):
		if actual_floor == current_floor and not is_moving:
			# Already at floor, maybe open doors (omitted for now)
			return

		requests.append(actual_floor)
		# Sort for simple deterministic order (0->1->2)
		requests.sort()
		_process_queue()

func _process_queue():
	if is_moving or requests.empty() or not platform:
		return

	target_floor = requests.pop_front()
	
	if floor_nodes.has(target_floor):
		# Close door at current floor before departing
		if current_floor != -1 and current_floor != target_floor:
			_close_door(current_floor)
			if not Engine.editor_hint:
				yield (get_tree().create_timer(0.9), "timeout")
		var target_height = floor_nodes[target_floor].global_transform.origin.y
		_start_move_sfx()
		platform.move_to(target_height)
		is_moving = true
		_emit_floor_state()
	else:
		is_moving = false
		_stop_move_sfx()
		requests.pop_front()
		_process_queue()

func _on_arrived(height):
	is_moving = false
	_stop_move_sfx()
	_play_arrival_sfx()
	
	# Identify which floor we arrived at based on height
	current_floor = -1
	for f_idx in floor_nodes.keys():
		if abs(floor_nodes[f_idx].global_transform.origin.y - height) < 0.1:
			current_floor = f_idx
			break

	# Open door at this floor (stays open until elevator departs)
	_open_door(current_floor)
	target_floor = current_floor
	_emit_floor_state()

	# Process any pending requests after a brief pause
	if not Engine.editor_hint:
		yield (get_tree().create_timer(1.0), "timeout")
		_process_queue()

func _on_platform_stopped():
	_stop_move_sfx()


func _emit_floor_state() -> void:
	emit_signal("floor_state_changed", current_floor, target_floor, is_moving)

func _cache_sfx_nodes() -> void:
	_sfx_move = get_node_or_null("Platform/SFX Move")
	_sfx_arrival = get_node_or_null("Platform/SFX Arrival")

func _start_move_sfx() -> void:
	if Engine.editor_hint:
		return
	if _sfx_move and not _sfx_move.playing:
		_sfx_move.play_sfx()

func _stop_move_sfx() -> void:
	if _sfx_move and _sfx_move.playing:
		_sfx_move.stop_sfx()

func _play_arrival_sfx() -> void:
	if Engine.editor_hint:
		return
	if _sfx_arrival:
		_sfx_arrival.play_sfx()

func _open_door(floor_idx: int) -> void:
	if floor_doors.has(floor_idx):
		var door = floor_doors[floor_idx]
		if door.has_method("set_active"):
			door.set_active(true)
			emit_signal("door_opened", floor_idx)

func _close_door(floor_idx: int) -> void:
	if floor_doors.has(floor_idx):
		var door = floor_doors[floor_idx]
		if door.has_method("set_active"):
			door.set_active(false)
			emit_signal("door_closed", floor_idx)

func get_snapshot() -> Dictionary:
	var snap = .get_snapshot()
	snap["requests"] = requests.duplicate(true)
	snap["current_floor"] = current_floor
	snap["target_floor"] = target_floor
	snap["is_moving"] = is_moving
	return snap

func restore_snapshot(data: Dictionary) -> void:
	if not is_inside_tree():
		_pending_snapshot = data.duplicate(true)
		return
	_apply_snapshot(data)

func _apply_snapshot(data: Dictionary) -> void:
	var restored_requests = data.get("requests", [])
	requests = restored_requests.duplicate(true) if typeof(restored_requests) == TYPE_ARRAY else []
	current_floor = int(data.get("current_floor", current_floor))
	target_floor = int(data.get("target_floor", target_floor))
	is_moving = bool(data.get("is_moving", is_moving))
	.restore_snapshot(data)
	if is_moving:
		_start_move_sfx()
	else:
		_stop_move_sfx()
