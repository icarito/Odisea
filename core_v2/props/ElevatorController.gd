extends PropBaseV2
class_name ElevatorController
tool

# ElevatorController.gd
# Manages elevator logic, queueing requests, and commanding the platform.

export(NodePath) var platform_path
export(float) var floor_height_step = 5.0

var requests = []
var current_floor = 0
var target_floor = -1
var is_moving = false

onready var platform = get_node(platform_path) if platform_path else null

func _ready():
    # Auto-connect child inputs
    for child in get_children():
        if child.has_signal("input_triggered"):
            if not child.is_connected("input_triggered", self, "_on_floor_request"):
                child.connect("input_triggered", self, "_on_floor_request")

    if platform:
        if not platform.is_connected("arrived_at_floor", self, "_on_arrived"):
            platform.connect("arrived_at_floor", self, "_on_arrived")
    else:
        print("[ElevatorController] Platform not found at path: ", platform_path)

func _on_floor_request(floor_idx):
    print("[ElevatorController] Request received for floor: ", floor_idx)
    # Log request
    if not requests.has(floor_idx):
        if floor_idx == current_floor and not is_moving:
            print("[ElevatorController] Already at floor ", floor_idx)
            # Already at floor, maybe open doors (omitted for now)
            return

        requests.append(floor_idx)
        # Sort for simple deterministic order (0->1->2)
        requests.sort()
        _process_queue()

func _process_queue():
    if is_moving or requests.empty() or not platform:
        return

    target_floor = requests.pop_front()
    print("[ElevatorController] Processing queue. Moving to floor: ", target_floor)
    var h = target_floor * floor_height_step
    platform.move_to(h)
    is_moving = true

func _on_arrived(height):
    is_moving = false
    current_floor = int(round(height / floor_height_step))
    print("[ElevatorController] Arrived at floor: ", current_floor)

    # Wait at floor
    if not Engine.editor_hint:
        yield(get_tree().create_timer(1.0), "timeout")
        _process_queue()
