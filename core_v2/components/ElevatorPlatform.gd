extends KinematicBody
class_name ElevatorPlatform
tool

# ElevatorPlatform.gd
# Handles smooth vertical movement and passenger velocity propagation.

signal arrived_at_floor(floor_height)
signal stopped()

export(float) var speed = 5.0
export(float) var acceleration = 5.0
export(float) var deceleration = 5.0
export(NodePath) var passenger_area_path
export(bool) var debug_passengers := false

var target_height: float = 0.0
var current_velocity_y: float = 0.0
var is_moving: bool = false
var passengers := []
onready var passenger_area: Area = get_node(passenger_area_path) if passenger_area_path else null
var _pending_snapshot = null
var _snapshot_applied := false

func _init():
    add_to_group("replay_sync")

func _ready():
    if passenger_area:
        if not passenger_area.is_connected("body_entered", self, "_on_passenger_entered"):
            passenger_area.connect("body_entered", self, "_on_passenger_entered")
        if not passenger_area.is_connected("body_exited", self, "_on_passenger_exited"):
            passenger_area.connect("body_exited", self, "_on_passenger_exited")
    if _pending_snapshot != null:
        _apply_snapshot(_pending_snapshot)
        _pending_snapshot = null
    elif not _snapshot_applied:
        target_height = global_transform.origin.y
        set_physics_process(is_moving)

func move_to(height: float):
    target_height = height
    is_moving = true
    set_physics_process(true) # Ensure process is running

func step(dt: float):
    # Compatibility with SessionManager deterministic loop
    _physics_process(dt)

func _physics_process(delta: float):
    if not is_moving:
        return

    var current_y = global_transform.origin.y
    var diff = target_height - current_y
    var dist = abs(diff)
    var direction = sign(diff)

    # Check arrival
    if dist < 0.05 and abs(current_velocity_y) < 0.1:
        global_transform.origin.y = target_height
        current_velocity_y = 0.0
        is_moving = false
        emit_signal("arrived_at_floor", target_height)
        emit_signal("stopped")
        _update_passengers(Vector3.ZERO)
        return

    # Calculate target speed based on braking distance
    var braking_speed = sqrt(2.0 * deceleration * dist)
    var target_speed = min(speed, braking_speed)

    # Accelerate/Decelerate towards target_speed * direction
    current_velocity_y = move_toward(current_velocity_y, target_speed * direction, acceleration * delta)

    # Apply movement
    var move_step = current_velocity_y * delta

    # Prevent overshoot
    if abs(move_step) > dist:
        move_step = diff # Snap to target

    global_transform.origin.y += move_step

    _update_passengers(Vector3(0, current_velocity_y, 0))

func _update_passengers(velocity: Vector3):
    var current_passengers = []
    if passenger_area:
        current_passengers = passenger_area.get_overlapping_bodies()
    else:
        current_passengers = passengers

    for body in current_passengers:
        if body == self or body.get_parent() == self:
            continue
        if body.has_method("_update_platform_tracking"):
            continue
        if body.has_method("set_external_velocity"):
            body.set_external_velocity(velocity)
            if body.has_method("set_external_source_is_static"):
                body.set_external_source_is_static(true)

func _on_passenger_entered(body):
    if body and not passengers.has(body):
        passengers.append(body)

func _on_passenger_exited(body):
    if body:
        passengers.erase(body)

func get_snapshot() -> Dictionary:
    return {
        "position": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
        "target_height": target_height,
        "current_velocity_y": current_velocity_y,
        "is_moving": is_moving,
        "speed": speed,
        "acceleration": acceleration,
        "deceleration": deceleration,
        "debug_passengers": debug_passengers
    }

func restore_snapshot(data: Dictionary) -> void:
    if not is_inside_tree():
        _pending_snapshot = data.duplicate(true)
        return
    _apply_snapshot(data)

func _apply_snapshot(data: Dictionary) -> void:
    _snapshot_applied = true
    passengers.clear()
    if data.has("speed"):
        speed = float(data["speed"])
    if data.has("acceleration"):
        acceleration = float(data["acceleration"])
    if data.has("deceleration"):
        deceleration = float(data["deceleration"])
    if data.has("debug_passengers"):
        debug_passengers = bool(data["debug_passengers"])
    if data.has("position"):
        var pos = data["position"]
        global_transform.origin = Vector3(pos[0], pos[1], pos[2])
    target_height = float(data.get("target_height", global_transform.origin.y))
    current_velocity_y = float(data.get("current_velocity_y", 0.0))
    is_moving = bool(data.get("is_moving", false))
    force_update_transform()
    set_physics_process(is_moving)
