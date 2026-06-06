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

export(NodePath) var beacon_path
export(NodePath) var pressurize_sfx_path

const DOOR_CLOSED_EPSILON := 0.05

# --- INTERNAL STATE ---
var state = State.IDLE setget _set_state
var timer := 0.0
var _is_cycling_in := true
var _current_exit_door_name := ""

var _outer_door: Node = null
var _inner_door: Node = null
var _chamber_zone: Area = null
var _beacon: Node = null
var _pressurize_sfx: Node = null

func _ready():
	add_to_group("replay_sync")

	if outer_door_path:
		_outer_door = get_node_or_null(outer_door_path)
	if inner_door_path:
		_inner_door = get_node_or_null(inner_door_path)
	_configure_managed_doors()

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

	if beacon_path:
		_beacon = get_node_or_null(beacon_path)
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
	if not _beacon:
		return

	# IDLE: puertas cerradas -> apagado
	# ENTRY_OPEN: puerta abierta, nadie adentro -> rojo
	# PRESSURIZING / EXIT_OPEN: alguien adentro -> verde
	if state == State.IDLE:
		_beacon.set_active(false)
	elif state == State.ENTRY_OPEN:
		_beacon.set_active(true)
		_beacon.set_beacon_color(Color.red)
	else:
		# PRESSURIZING o EXIT_OPEN
		_beacon.set_active(true)
		_beacon.set_beacon_color(Color.green)

	if state == State.PRESSURIZING:
		if _pressurize_sfx and _pressurize_sfx.has_method("play") and not _pressurize_sfx.playing:
			_pressurize_sfx.play()
	else:
		if _pressurize_sfx and _pressurize_sfx.has_method("stop"):
			_pressurize_sfx.stop()

# --- INTERACTION API ---

func interact():
	if state != State.IDLE:
		return
	interact_outer()

func request_door_interaction(door_name: String) -> bool:
	var normalized := door_name.strip_edges().to_lower()
	if normalized != "inner":
		normalized = "outer"

	if state == State.IDLE:
		if normalized == "inner":
			interact_inner()
		else:
			interact_outer()
		return true

	if state == State.EXIT_OPEN:
		return open_exit_door(normalized, false)

	return false

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
	var exit_door = _outer_door if normalized == "inner" else _inner_door
	_is_cycling_in = normalized != "inner"
	_current_exit_door_name = ""
	_set_door_active(entry_door, false)
	_set_door_active(exit_door, false)
	# Enter PRESSURIZING so the beacon lights up as the entry door closes.
	# Use a large timer so step() never auto-finishes — open_exit_door() is called
	# explicitly by SessionManager when the player arrives in the destination scene.
	self.state = State.PRESSURIZING
	timer = 9999.0
	emit_signal("airlock_cycle_started")
	return true

func abort_transition_cycle(entry_door_name: String = "outer") -> bool:
	if Engine.editor_hint:
		return false
	if state != State.PRESSURIZING:
		return false

	var normalized := entry_door_name.strip_edges().to_lower()
	var entry_door = _inner_door if normalized == "inner" else _outer_door
	var exit_door = _outer_door if normalized == "inner" else _inner_door
	_is_cycling_in = normalized != "inner"
	_current_exit_door_name = ""
	_set_door_active(exit_door, false)
	_set_door_active(entry_door, true)
	timer = max(reset_time, 0.0)
	self.state = State.ENTRY_OPEN
	return true

func is_airlock_ready() -> bool:
	return state == State.EXIT_OPEN

func is_pressurizing() -> bool:
	return state == State.PRESSURIZING

func get_open_exit_door_name() -> String:
	return _current_exit_door_name if state == State.EXIT_OPEN else ""

func is_transition_entry_sealed(entry_door_name: String = "outer") -> bool:
	var normalized := entry_door_name.strip_edges().to_lower()
	var entry_door = _inner_door if normalized == "inner" else _outer_door
	return _is_door_closed(entry_door)

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

	# Opening one side is allowed from inside the airlock, but it must always be
	# exclusive. Direct door interaction is disabled; only this controller chooses.
	_set_door_active(other_door, false, immediate)
	var opened := _set_door_active(door, true, immediate)
	self.state = State.EXIT_OPEN
	_current_exit_door_name = normalized if opened else ""
	timer = max(reset_time, 0.0)
	if opened:
		emit_signal("airlock_ready")
	return opened

func interact_outer():
	if state == State.IDLE:
		_is_cycling_in = true
		_start_entry()

func interact_inner():
	if state == State.IDLE:
		_is_cycling_in = false
		_start_entry()

func _start_entry():
	self.state = State.ENTRY_OPEN
	_current_exit_door_name = ""
	timer = max(reset_time, 0.0)
	if _is_cycling_in:
		_set_door_active(_inner_door, false)
		_set_door_active(_outer_door, true)
	else:
		_set_door_active(_outer_door, false)
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

	if state == State.ENTRY_OPEN:
		timer -= dt
		if timer <= 0:
			self.state = State.IDLE
			_current_exit_door_name = ""
			if _is_cycling_in:
				_set_door_active(_outer_door, false)
			else:
				_set_door_active(_inner_door, false)
			emit_signal("airlock_cycle_completed")

	elif state == State.PRESSURIZING:
		timer -= dt
		if timer <= 0:
			_finish_pressurization()

	elif state == State.EXIT_OPEN:
		timer -= dt
		if timer <= 0:
			self.state = State.IDLE
			_current_exit_door_name = ""
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
		_current_exit_door_name = "inner"
		_set_door_active(_outer_door, false)
		_set_door_active(_inner_door, true)
	else:
		_current_exit_door_name = "outer"
		_set_door_active(_inner_door, false)
		_set_door_active(_outer_door, true)
	emit_signal("airlock_ready")
	if timer <= 0.0:
		self.state = State.IDLE
		_current_exit_door_name = ""
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

func _configure_managed_doors() -> void:
	_mark_controller_owned_door(_outer_door, "outer")
	_mark_controller_owned_door(_inner_door, "inner")

func _mark_controller_owned_door(door: Node, door_name: String) -> void:
	if not is_instance_valid(door):
		return
	var pending: Array = [door]
	while not pending.empty():
		var node = pending.pop_front()
		if not is_instance_valid(node):
			continue
		if node.has_method("interact"):
			node.set_meta("airlock_controller_owned", true)
			node.set_meta("airlock_controller_owner_path", get_path())
			node.set_meta("airlock_door_name", door_name)
		if "is_interactable" in node:
			node.set("is_interactable", true)
		if node.has_method("interact") and not node.is_in_group("interactable"):
			node.add_to_group("interactable")
		for child in node.get_children():
			pending.push_back(child)

func _is_door_closed(door: Node) -> bool:
	var state_node := _find_door_state_node(door)
	if not is_instance_valid(state_node):
		return true
	if "is_active" in state_node and bool(state_node.get("is_active")):
		return false
	if "anim_progress" in state_node:
		return float(state_node.get("anim_progress")) <= DOOR_CLOSED_EPSILON
	if "target_progress" in state_node:
		return float(state_node.get("target_progress")) <= DOOR_CLOSED_EPSILON
	return true

func _find_door_state_node(door: Node) -> Node:
	if not is_instance_valid(door):
		return null
	if "is_active" in door or "anim_progress" in door or "target_progress" in door:
		return door
	var pending: Array = [door]
	while not pending.empty():
		var node = pending.pop_front()
		if not is_instance_valid(node):
			continue
		if node != door and ("is_active" in node or "anim_progress" in node or "target_progress" in node):
			return node
		for child in node.get_children():
			pending.push_back(child)
	return null

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
