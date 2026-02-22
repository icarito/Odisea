extends PropBaseV2
class_name ElevatorController
tool

# ElevatorController.gd
# Manages elevator logic, queueing requests, and commanding the platform.

export(NodePath) var platform_path
export(NodePath) var floors_path = NodePath("Floors")

var requests = []
var current_floor = 0
var target_floor = -1
var is_moving = false
var floor_nodes = {}

onready var platform = get_node(platform_path) if platform_path else null
onready var floors_container = get_node(floors_path) if floors_path else null

func _ready():
    # Discover and connect floor inputs
    if floors_container:
        for floor_node in floors_container.get_children():
            var f_idx = _find_floor_input(floor_node)
            if f_idx != -1:
                floor_nodes[f_idx] = floor_node


    # Connect internal "next" button if present on platform
    if platform:
        for child in platform.get_children():
            if child.has_signal("input_triggered") and child.get("floor_index") == -1:
                if not child.is_connected("input_triggered", self, "_on_floor_request"):
                    child.connect("input_triggered", self, "_on_floor_request")


    if platform:
        if not platform.is_connected("arrived_at_floor", self, "_on_arrived"):
            platform.connect("arrived_at_floor", self, "_on_arrived")
        pass

func _find_floor_input(node: Node) -> int:
    for child in node.get_children():
        if child.has_signal("input_triggered"):
            if not child.is_connected("input_triggered", self, "_on_floor_request"):
                child.connect("input_triggered", self, "_on_floor_request")
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
        var target_height = floor_nodes[target_floor].global_transform.origin.y

        platform.move_to(target_height)
        is_moving = true
    else:
        is_moving = false
        requests.pop_front()
        _process_queue()

func _on_arrived(height):
    is_moving = false
    
    # Identify which floor we arrived at based on height
    current_floor = -1
    for f_idx in floor_nodes.keys():
        if abs(floor_nodes[f_idx].global_transform.origin.y - height) < 0.1:
            current_floor = f_idx
            break
            

    # Wait at floor
    if not Engine.editor_hint:
        yield (get_tree().create_timer(1.0), "timeout")
        _process_queue()
