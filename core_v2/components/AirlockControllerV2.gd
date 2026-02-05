extends Node
class_name AirlockControllerV2

# AirlockControllerV2.gd - Sequencer for airlock chambers
# Manages Inner and Outer doors and cycling logic.

enum State { IDLE, CYCLING_IN, CYCLING_OUT, BUSY_IN, BUSY_OUT }

# --- EXPORTED TUNING ---
export(NodePath) var outer_door_path
export(NodePath) var inner_door_path
export(NodePath) var cycle_zone_path
export(float) var pressurize_duration := 1.0

# --- STATE ---
var current_state = State.IDLE
var timer := 0.0

onready var outer_door = get_node_or_null(outer_door_path)
onready var inner_door = get_node_or_null(inner_door_path)
onready var cycle_zone = get_node_or_null(cycle_zone_path)

func _ready():
	add_to_group("replay_sync")
	if cycle_zone:
		if not cycle_zone.is_connected("body_entered", self, "_on_zone_entered"):
			cycle_zone.connect("body_entered", self, "_on_zone_entered")

func interact_outer():
	if current_state == State.IDLE:
		if outer_door: outer_door.set_active(true)
		if inner_door: inner_door.set_active(false)
		current_state = State.CYCLING_IN

func interact_inner():
	if current_state == State.IDLE:
		if inner_door: inner_door.set_active(true)
		if outer_door: outer_door.set_active(false)
		current_state = State.CYCLING_OUT

func _on_zone_entered(body: Node):
	if body.is_in_group("player"):
		if current_state == State.CYCLING_IN:
			if outer_door: outer_door.set_active(false)
			timer = pressurize_duration
			current_state = State.BUSY_IN
		elif current_state == State.CYCLING_OUT:
			if inner_door: inner_door.set_active(false)
			timer = pressurize_duration
			current_state = State.BUSY_OUT

func step(dt: float):
	if current_state == State.BUSY_IN or current_state == State.BUSY_OUT:
		timer -= dt
		if timer <= 0:
			if current_state == State.BUSY_IN:
				if inner_door: inner_door.set_active(true)
			else:
				if outer_door: outer_door.set_active(true)
			current_state = State.IDLE

func _physics_process(delta):
	if not SessionManager.is_manual_mode:
		step(delta)

# --- REPLAY SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"state": current_state,
		"timer": timer
	}

func restore_snapshot(data: Dictionary):
	current_state = data.get("state", State.IDLE)
	timer = data.get("timer", 0.0)

	# Visuals are driven by doors, which are also snapshotted.
