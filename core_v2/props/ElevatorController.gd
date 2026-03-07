extends PropBaseV2
class_name ElevatorController
tool

# ElevatorController.gd
# Manages elevator logic, queueing requests, and commanding the platform.

signal door_opened(floor_idx)
signal door_closed(floor_idx)

export(NodePath) var platform_path
export(NodePath) var floors_path = NodePath("Floors")
export(float) var door_open_wait := 2.0 # seconds door stays open

var requests = []
var current_floor = 0
var target_floor = -1
var is_moving = false
var floor_nodes = {}
var floor_doors = {} # floor_idx -> door node (DualSlidingObjectV2)
var _sfx_move: SFXComponentV2 = null
var _sfx_arrival: SFXComponentV2 = null

onready var platform = get_node(platform_path) if platform_path else null
onready var floors_container = get_node(floors_path) if floors_path else null

func _ready():
    _cache_sfx_nodes()

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

    # Process any pending requests after a brief pause
    if not Engine.editor_hint:
        yield (get_tree().create_timer(1.0), "timeout")
        _process_queue()

func _on_platform_stopped():
    _stop_move_sfx()

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
