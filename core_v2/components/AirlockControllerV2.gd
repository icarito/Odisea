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

export(NodePath) var outer_beacon_path
export(NodePath) var inner_beacon_path
export(NodePath) var pressurize_sfx_path

# --- INTERNAL STATE ---
var state = State.IDLE setget _set_state
var timer := 0.0
var _is_cycling_in := true

var _outer_door: Node = null
var _inner_door: Node = null
var _chamber_zone: Area = null
var _outer_beacon: Node = null
var _inner_beacon: Node = null
var _pressurize_sfx: Node = null

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

	if outer_beacon_path:
		_outer_beacon = get_node_or_null(outer_beacon_path)
	if inner_beacon_path:
		_inner_beacon = get_node_or_null(inner_beacon_path)
	if pressurize_sfx_path:
		_pressurize_sfx = get_node_or_null(pressurize_sfx_path)

	if _chamber_zone:
		# Force detection of player (all layers)
		_chamber_zone.monitoring = true
		_chamber_zone.collision_mask = 2147483647
		
		if not _chamber_zone.is_connected("body_entered", self, "_on_body_entered"):
			_chamber_zone.connect("body_entered", self, "_on_body_entered")

func _set_state(new_state):
	if state != new_state:
		state = new_state
		_update_beacons()

func _update_beacons():
	if not _outer_beacon and not _inner_beacon: return
	
	var outer_color = Color.black
	var inner_color = Color.black
	var outer_active = false
	var inner_active = false

	if state == State.IDLE:
		outer_active = false
		inner_active = false
	elif state == State.PRESSURIZING:
		outer_active = true
		inner_active = true
		outer_color = Color.yellow
		inner_color = Color.yellow
		if _pressurize_sfx and _pressurize_sfx.has_method("play") and not _pressurize_sfx.playing:
			_pressurize_sfx.play()
	elif state == State.ENTRY_OPEN:
		outer_active = true
		inner_active = true
		if _is_cycling_in:
			outer_color = Color.green
			inner_color = Color.red
		else:
			outer_color = Color.red
			inner_color = Color.green
	elif state == State.EXIT_OPEN:
		outer_active = true
		inner_active = true
		if _is_cycling_in:
			inner_color = Color.green
			outer_color = Color.red
		else:
			inner_color = Color.red
			outer_color = Color.green
			
	if state != State.PRESSURIZING and _pressurize_sfx and _pressurize_sfx.has_method("stop"):
		_pressurize_sfx.stop()

	if _outer_beacon:
		_outer_beacon.set_active(outer_active)
		if outer_active: _outer_beacon.set_beacon_color(outer_color)
	if _inner_beacon:
		_inner_beacon.set_active(inner_active)
		if inner_active: _inner_beacon.set_beacon_color(inner_color)

# --- INTERACTION API ---

func interact():
	print("[AirlockControllerV2] interact() called, _outer_door=", _outer_door)
	# Reset state to IDLE to ensure interaction works (handles stale replay state)
	if state != State.IDLE:
		self.state = State.IDLE
		_set_door_active(_outer_door, false, true)
	interact_outer()

func start_cycle(cycling_in: bool = true) -> bool:
	if Engine.editor_hint:
		return false
	if state != State.IDLE:
		return false

	_is_cycling_in = cycling_in
	self.state = State.PRESSURIZING
	timer = max(pressurize_time, 0.0)
	_set_door_active(_outer_door, false)
	_set_door_active(_inner_door, false)
	emit_signal("airlock_cycle_started")

	if timer <= 0.0:
		_finish_pressurization()
	return true

func start_transition_cycle(entry_door_name: String = "outer") -> bool:
	if Engine.editor_hint:
		return false
	var normalized := entry_door_name.strip_edges().to_lower()
	var entry_door = _inner_door if normalized == "inner" else _outer_door
	_is_cycling_in = normalized != "inner"
	_set_door_active(entry_door, false)
	self.state = State.IDLE
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

	self.state = State.EXIT_OPEN
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
	self.state = State.ENTRY_OPEN
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
		self.state = State.PRESSURIZING
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
			self.state = State.IDLE
			# Close exit door (auto reset)
			if _is_cycling_in:
				_set_door_active(_inner_door, false)
			else:
				_set_door_active(_outer_door, false)
			emit_signal("airlock_cycle_completed")

func _finish_pressurization() -> void:
	self.state = State.EXIT_OPEN
	timer = max(reset_time, 0.0)
	if _is_cycling_in:
		_set_door_active(_inner_door, true)
	else:
		_set_door_active(_outer_door, true)
	emit_signal("airlock_ready")
	if timer <= 0.0:
		self.state = State.IDLE
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
	self.state = data.get("state", State.IDLE)
	timer = data.get("timer", 0.0)
	_is_cycling_in = data.get("cycling_in", true)
