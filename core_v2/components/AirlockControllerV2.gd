extends Spatial
class_name AirlockControllerV2
tool

# AirlockControllerV2.gd - Deterministic Airlock Logic
# Manages a sequence of doors and pressurization state.

enum State {IDLE, ENTRY_OPEN, PRESSURIZING, EXIT_OPEN}

signal airlock_cycle_started()
signal airlock_ready()
signal airlock_cycle_completed()

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

	if outer_door_path:
		_outer_door = get_node_or_null(outer_door_path)
	if inner_door_path:
		_inner_door = get_node_or_null(inner_door_path)

	if chamber_zone_path:
		var node = get_node_or_null(chamber_zone_path)
		if node == null:
			return
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
	print("[AirlockControllerV2] interact() called, _outer_door=", _outer_door)
	# Reset state to IDLE to ensure interaction works (handles stale replay state)
	if state != State.IDLE:
		state = State.IDLE
		_set_door_active(_outer_door, false, true)
	interact_outer()

func start_cycle(cycling_in: bool = true) -> bool:
	if Engine.editor_hint:
		return false
	if state != State.IDLE:
		return false

	_is_cycling_in = cycling_in
	state = State.PRESSURIZING
	timer = max(pressurize_time, 0.0)
	_set_door_active(_outer_door, false)
	_set_door_active(_inner_door, false)
	emit_signal("airlock_cycle_started")

	if timer <= 0.0:
		_finish_pressurization()
	return true

func is_airlock_ready() -> bool:
	return state == State.EXIT_OPEN

func open_exit_door(door_name: String = "outer", immediate: bool = false) -> bool:
	var normalized := door_name.strip_edges().to_lower()
	if normalized == "none":
		return false

	var door = _outer_door
	var other_door = _inner_door
	_is_cycling_in = false
	if normalized == "inner":
		door = _inner_door
		other_door = _outer_door
		_is_cycling_in = true

	state = State.EXIT_OPEN
	timer = max(reset_time, 0.0)
	_set_door_active(other_door, false, immediate)
	var opened := _set_door_active(door, true, immediate)
	if opened:
		emit_signal("airlock_ready")
	return opened

func interact_outer():
	print("[AirlockControllerV2] interact_outer() called, state=", state)
	if state == State.IDLE:
		_is_cycling_in = true
		_start_entry()

func interact_inner():
	if state == State.IDLE:
		_is_cycling_in = false
		_start_entry()

func _start_entry():
	print("[AirlockControllerV2] _start_entry() called, _outer_door=", _outer_door)
	state = State.ENTRY_OPEN
	if _is_cycling_in:
		print("[AirlockControllerV2] Opening outer door")
		_set_door_active(_outer_door, true)
	else:
		print("[AirlockControllerV2] Opening inner door")
		_set_door_active(_inner_door, true)

func _on_body_entered(body):
	if Engine.editor_hint: return

	if state == State.ENTRY_OPEN and body.is_in_group("player"):
		# Player entered chamber
		state = State.PRESSURIZING
		timer = pressurize_time

		# Close entry door
		if _is_cycling_in:
			_set_door_active(_outer_door, false)
		else:
			_set_door_active(_inner_door, false)

# --- DETERMINISTIC STEP ---

func step(dt: float):
	if Engine.editor_hint: return

	if state == State.PRESSURIZING:
		timer -= dt
		if timer <= 0:
			_finish_pressurization()

	elif state == State.EXIT_OPEN:
		timer -= dt
		if timer <= 0:
			state = State.IDLE
			# Close exit door (auto reset)
			if _is_cycling_in:
				_set_door_active(_inner_door, false)
			else:
				_set_door_active(_outer_door, false)
			emit_signal("airlock_cycle_completed")

func _finish_pressurization() -> void:
	state = State.EXIT_OPEN
	timer = max(reset_time, 0.0)
	if _is_cycling_in:
		_set_door_active(_inner_door, true)
	else:
		_set_door_active(_outer_door, true)
	emit_signal("airlock_ready")
	if timer <= 0.0:
		state = State.IDLE
		_set_door_active(_outer_door, false)
		_set_door_active(_inner_door, false)
		emit_signal("airlock_cycle_completed")

func _set_door_active(door: Node, value: bool, immediate: bool = false) -> bool:
	if not is_instance_valid(door):
		return false
	if door.has_method("set_active"):
		door.call("set_active", value, immediate)
		return true
	var pending: Array = [door]
	while not pending.empty():
		var node = pending.pop_front()
		if not is_instance_valid(node):
			continue
		if node != door and node.has_method("set_active"):
			node.call("set_active", value, immediate)
			return true
		for child in node.get_children():
			pending.push_back(child)
	return false

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
