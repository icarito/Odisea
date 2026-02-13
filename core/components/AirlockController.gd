extends Spatial
class_name AirlockController
tool

# AirlockController.gd - Deterministic Airlock Logic
# Manages a sequence of doors and pressurization state.

enum State {IDLE, ENTRY_OPEN, PRESSURIZING, EXIT_OPEN}

# --- EXPORTS ---
export(NodePath) var outer_door_path
export(NodePath) var inner_door_path
export(NodePath) var chamber_zone_path
export(float) var pressurize_time := 1.0
export(float) var reset_time := 3.0

# --- INTERNAL STATE ---
var state = State.IDLE
var timer := 0.0
var _is_cycling_in := true

var _outer_door: Node = null
var _inner_door: Node = null
var _chamber_zone: Area = null

func _ready():
	add_to_group("replay_sync")

	if outer_door_path: _outer_door = get_node(outer_door_path)
	if inner_door_path: _inner_door = get_node(inner_door_path)

	if chamber_zone_path:
		var node = get_node(chamber_zone_path)
		if node is Area:
			_chamber_zone = node
		elif node.has_node("Area"):
			_chamber_zone = node.get_node("Area")
		elif node.get_parent() is Area:
			_chamber_zone = node.get_parent()

	if _chamber_zone:
		# Force detection of player (all layers)
		_chamber_zone.monitoring = true
		_chamber_zone.collision_mask = 2147483647
		
		if not _chamber_zone.is_connected("body_entered", self, "_on_body_entered"):
			_chamber_zone.connect("body_entered", self, "_on_body_entered")

# --- INTERACTION API ---

func interact():
	interact_outer()

func interact_outer():
	if state == State.IDLE:
		_is_cycling_in = true
		_start_entry()

func interact_inner():
	if state == State.IDLE:
		_is_cycling_in = false
		_start_entry()

func _start_entry():
	state = State.ENTRY_OPEN
	if _is_cycling_in:
		if _outer_door and _outer_door.has_method("set_active"):
			_outer_door.set_active(true)
	else:
		if _inner_door and _inner_door.has_method("set_active"):
			_inner_door.set_active(true)

func _on_body_entered(body):
	if Engine.editor_hint: return

	if state == State.ENTRY_OPEN and body.is_in_group("player"):
		# Player entered chamber
		state = State.PRESSURIZING
		timer = pressurize_time

		# Close entry door
		if _is_cycling_in:
			if _outer_door and _outer_door.has_method("set_active"):
				_outer_door.set_active(false)
		else:
			if _inner_door and _inner_door.has_method("set_active"):
				_inner_door.set_active(false)

# --- DETERMINISTIC STEP ---

func step(dt: float):
	if Engine.editor_hint: return

	if state == State.PRESSURIZING:
		timer -= dt
		if timer <= 0:
			state = State.EXIT_OPEN
			timer = reset_time
			# Open exit door
			if _is_cycling_in:
				if _inner_door and _inner_door.has_method("set_active"):
					_inner_door.set_active(true)
			else:
				if _outer_door and _outer_door.has_method("set_active"):
					_outer_door.set_active(true)

	elif state == State.EXIT_OPEN:
		timer -= dt
		if timer <= 0:
			state = State.IDLE
			# Close exit door (auto reset)
			if _is_cycling_in:
				if _inner_door and _inner_door.has_method("set_active"):
					_inner_door.set_active(false)
			else:
				if _outer_door and _outer_door.has_method("set_active"):
					_outer_door.set_active(false)

func _physics_process(delta):
	step(delta)

# --- SNAPSHOT ---

func get_snapshot() -> Dictionary:
	return {
		"state": state,
		"timer": timer,
		"cycling_in": _is_cycling_in
	}

func restore_snapshot(data: Dictionary):
	state = data.get("state", State.IDLE)
	timer = data.get("timer", 0.0)
	_is_cycling_in = data.get("cycling_in", true)
