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
export(float) var reset_time := 10.0

export(NodePath) var beacon_path
export(NodePath) var pressurize_sfx_path
export(NodePath) var transition_button_path
export(NodePath) var outer_status_light_path
export(NodePath) var inner_status_light_path
export(NodePath) var status_label_path

const DOOR_CLOSED_EPSILON := 0.05
const STATUS_OFF := Color(0.05, 0.08, 0.08, 1.0)
const STATUS_READY := Color(0.0, 1.0, 0.18, 1.0)
const STATUS_BLOCKED := Color(1.0, 0.05, 0.02, 1.0)

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
var _transition_button: Node = null
var _outer_status_light: Node = null
var _inner_status_light: Node = null
var _status_label: Node = null
var _pressurize_active := false
var _transition_ready := false
var _waiting_entry_door_name := ""
var _label_linger_timer := 0.0
var _label_linger_text := ""
const LABEL_LINGER_SECONDS := 1.5

func _ready():
	add_to_group("replay_sync")
	add_to_group("airlock_chamber")

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
	if transition_button_path:
		_transition_button = get_node_or_null(transition_button_path)
	if outer_status_light_path:
		_outer_status_light = get_node_or_null(outer_status_light_path)
	if inner_status_light_path:
		_inner_status_light = get_node_or_null(inner_status_light_path)
	if status_label_path:
		_status_label = get_node_or_null(status_label_path)
	_configure_transition_button()

	if _chamber_zone:
		# Force detection of player (all layers)
		_chamber_zone.monitoring = true
		_chamber_zone.collision_mask = 2147483647

		if not _chamber_zone.is_connected("body_entered", self, "_on_body_entered"):
			_chamber_zone.connect("body_entered", self, "_on_body_entered")
	_update_physics_processing()

func _set_state(new_state):
	if state != new_state:
		state = new_state
		_update_beacons()
		_update_physics_processing()

func _update_beacons():
	if not is_instance_valid(_beacon):
		_beacon = null
		_update_airlock_affordances()
		return

	# Beacon only lights during active pressurization cycle.
	# Status lights on the wall (via _update_airlock_affordances) handle door state readouts.
	var beacon_on: bool = state == State.PRESSURIZING and _pressurize_active
	_beacon.set_active(beacon_on)
	if beacon_on:
		_beacon.set_beacon_color(Color.green)

	if beacon_on:
		if _pressurize_sfx and _pressurize_sfx.has_method("play") and not _pressurize_sfx.playing:
			_pressurize_sfx.play()
	else:
		if _pressurize_sfx and _pressurize_sfx.has_method("stop"):
			_pressurize_sfx.stop()

	_update_airlock_affordances()

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

	if state == State.PRESSURIZING and not _pressurize_active and not _transition_ready:
		if normalized == _entry_door_name_for_cycle():
			return abort_transition_cycle(normalized)
		return false

	if state == State.EXIT_OPEN:
		# While one side is open, the opposite door must remain locked. The next
		# transition is armed by AirlockZoneV2 when the player commits through the
		# chamber, not by manually switching doors.
		return normalized == _current_exit_door_name

	return false

func request_transition_pressurization(entry_door_name: String = "") -> bool:
	if _pressurize_active or _transition_ready:
		return false
	if state != State.PRESSURIZING:
		var normalized := entry_door_name.strip_edges().to_lower()
		if normalized != "inner" and normalized != "outer":
			normalized = _entry_door_name_for_cycle()
		if not start_transition_cycle(normalized, true):
			return false
	# The progress threshold is authoritative. If a door is still open when the
	# player commits, seal both sides immediately and continue.
	_set_door_active(_outer_door, false, true)
	_set_door_active(_inner_door, false, true)
	_pressurize_active = true
	_transition_ready = false
	timer = max(pressurize_time, 0.0)
	if is_instance_valid(_transition_button) and _transition_button.has_method("set_active") and "is_active" in _transition_button and not bool(_transition_button.get("is_active")):
		_transition_button.set_active(true, true)
	_update_beacons()
	if timer <= 0.0:
		_finish_transition_pressurization()
	_update_physics_processing()
	return true

func start_cycle(cycling_in: bool = true) -> bool:
	if Engine.editor_hint:
		return false
	if state != State.IDLE:
		return false

	_is_cycling_in = cycling_in
	_waiting_entry_door_name = "outer" if _is_cycling_in else "inner"
	_pressurize_active = true
	_transition_ready = false
	self.state = State.PRESSURIZING  # calls _update_beacons() with _pressurize_active already true
	timer = max(pressurize_time, 0.0)
	_set_door_active(_outer_door, false)
	_set_door_active(_inner_door, false)
	emit_signal("airlock_cycle_started")

	if timer <= 0.0:
		_finish_pressurization()
	_update_physics_processing()
	return true

func start_transition_cycle(entry_door_name: String = "outer", immediate_close: bool = false) -> bool:
	if Engine.editor_hint:
		return false
	if not _can_start_transition_cycle():
		return false
	var normalized := entry_door_name.strip_edges().to_lower()
	var entry_door = _inner_door if normalized == "inner" else _outer_door
	var exit_door = _outer_door if normalized == "inner" else _inner_door
	_is_cycling_in = normalized != "inner"
	_waiting_entry_door_name = normalized
	_current_exit_door_name = ""
	_pressurize_active = false
	_transition_ready = false
	_set_door_active(entry_door, false, immediate_close)
	_set_door_active(exit_door, false, immediate_close)
	self.state = State.PRESSURIZING
	timer = 0.0
	emit_signal("airlock_cycle_started")
	_update_physics_processing()
	return true

func _can_start_transition_cycle() -> bool:
	if state == State.IDLE:
		return true
	if state == State.EXIT_OPEN:
		return true
	if state == State.PRESSURIZING and not _pressurize_active and not _transition_ready:
		return true
	return false

func abort_transition_cycle(entry_door_name: String = "outer") -> bool:
	if Engine.editor_hint:
		return false

	var normalized := entry_door_name.strip_edges().to_lower()
	if normalized != "inner":
		normalized = "outer"
	var entry_door = _inner_door if normalized == "inner" else _outer_door
	var exit_door = _outer_door if normalized == "inner" else _inner_door

	if state == State.EXIT_OPEN or state == State.ENTRY_OPEN:
		_reset_to_idle_with_entry_open(normalized, entry_door, exit_door)
		return true

	if state != State.PRESSURIZING:
		return false

	_is_cycling_in = normalized != "inner"
	_waiting_entry_door_name = normalized
	_current_exit_door_name = ""
	_pressurize_active = false
	_transition_ready = false
	_set_door_active(exit_door, false)
	_set_door_active(entry_door, true)
	timer = max(reset_time, 0.0)
	self.state = State.ENTRY_OPEN
	_update_physics_processing()
	return true

func _reset_to_idle_with_entry_open(entry_door_name: String, entry_door: Node, exit_door: Node) -> void:
	_is_cycling_in = entry_door_name != "inner"
	_current_exit_door_name = ""
	_waiting_entry_door_name = ""
	_pressurize_active = false
	_transition_ready = false
	_label_linger_timer = 0.0
	timer = 0.0
	_reset_transition_button()
	_set_door_active(exit_door, false, true)
	_set_door_active(entry_door, true, true)
	self.state = State.IDLE
	emit_signal("airlock_cycle_completed")
	_update_physics_processing()

func is_airlock_ready() -> bool:
	return state == State.EXIT_OPEN

func is_pressurizing() -> bool:
	return state == State.PRESSURIZING

func is_transition_requested() -> bool:
	return _transition_ready

func get_open_exit_door_name() -> String:
	return _current_exit_door_name if state == State.EXIT_OPEN else ""

func is_transition_entry_sealed(entry_door_name: String = "outer") -> bool:
	var normalized := entry_door_name.strip_edges().to_lower()
	var entry_door = _inner_door if normalized == "inner" else _outer_door
	return _is_door_closed(entry_door)

func open_exit_door(door_name: String = "outer", immediate: bool = false, hold_open: bool = false) -> bool:
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
	_waiting_entry_door_name = normalized

	# Opening one side is allowed from inside the airlock, but it must always be
	# exclusive. Direct door interaction is disabled; only this controller chooses.
	_set_door_active(other_door, false, immediate)
	var opened := _set_door_active(door, true, immediate)
	self.state = State.EXIT_OPEN
	_current_exit_door_name = normalized if opened else ""
	_pressurize_active = false
	_transition_ready = false
	# Show "PRESURIZANDO" briefly on arrival for continuity from the previous scene.
	_label_linger_text = "PRESURIZANDO"
	_label_linger_timer = LABEL_LINGER_SECONDS
	timer = -1.0 if hold_open else max(reset_time, 0.0)
	if opened:
		_prepare_zones_for_open_exit(normalized)
		emit_signal("airlock_ready")
	_update_physics_processing()
	return opened

func resume_exit_open_auto_reset() -> void:
	if state == State.EXIT_OPEN and timer < 0.0:
		timer = max(reset_time, 0.0)
		_update_physics_processing()

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
	_waiting_entry_door_name = _entry_door_name_for_cycle()
	_pressurize_active = false
	_transition_ready = false
	timer = max(reset_time, 0.0)
	if _is_cycling_in:
		_set_door_active(_inner_door, false)
		_set_door_active(_outer_door, true)
	else:
		_set_door_active(_outer_door, false)
		_set_door_active(_inner_door, true)
	_update_physics_processing()

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
		_update_physics_processing()

# --- DETERMINISTIC STEP ---

func step(dt: float):
	if Engine.editor_hint: return

	if _label_linger_timer > 0.0:
		_label_linger_timer -= dt
		if _label_linger_timer <= 0.0:
			_label_linger_timer = 0.0
			_update_airlock_affordances()
			_update_physics_processing()

	if state == State.ENTRY_OPEN:
		timer -= dt
		if timer <= 0:
			self.state = State.IDLE
			_current_exit_door_name = ""
			_waiting_entry_door_name = ""
			_pressurize_active = false
			_transition_ready = false
			_label_linger_timer = 0.0
			_reset_transition_button()
			if _is_cycling_in:
				_set_door_active(_outer_door, false)
			else:
				_set_door_active(_inner_door, false)
			emit_signal("airlock_cycle_completed")
			_update_physics_processing()

	elif state == State.PRESSURIZING:
		if _pressurize_active:
			timer -= dt
			if timer <= 0:
				_finish_transition_pressurization()

	elif state == State.EXIT_OPEN:
		if timer < 0.0:
			return
		timer -= dt
		if timer <= 0:
			self.state = State.PRESSURIZING
			_current_exit_door_name = ""
			_pressurize_active = false
			_transition_ready = false
			_label_linger_timer = 0.0
			_reset_transition_button()
			# Close exit door (auto reset)
			if _is_cycling_in:
				_set_door_active(_inner_door, false)
			else:
				_set_door_active(_outer_door, false)
			emit_signal("airlock_cycle_completed")
			_update_physics_processing()

func _finish_transition_pressurization() -> void:
	_pressurize_active = false
	_transition_ready = true
	_label_linger_text = "PRESURIZANDO"
	_label_linger_timer = LABEL_LINGER_SECONDS
	timer = 0.0
	_update_beacons()
	emit_signal("airlock_ready")
	_update_physics_processing()

func _finish_pressurization() -> void:
	self.state = State.EXIT_OPEN
	timer = max(reset_time, 0.0)
	_pressurize_active = false
	_transition_ready = false
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
		_waiting_entry_door_name = ""
		_pressurize_active = false
		_transition_ready = false
		_reset_transition_button()
		_set_door_active(_outer_door, false)
		_set_door_active(_inner_door, false)
		emit_signal("airlock_cycle_completed")
	_update_physics_processing()

func _update_physics_processing() -> void:
	if Engine.editor_hint:
		return
	var should_process := _label_linger_timer > 0.0
	if state == State.ENTRY_OPEN:
		should_process = should_process or timer > 0.0
	elif state == State.PRESSURIZING:
		should_process = should_process or (_pressurize_active and timer > 0.0)
	elif state == State.EXIT_OPEN:
		should_process = should_process or timer > 0.0
	set_physics_process(should_process)

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

func _prepare_zones_for_open_exit(open_exit_door_name: String) -> void:
	var pending: Array = [self]
	while not pending.empty():
		var node: Node = pending.pop_front()
		if node != self and node.has_method("prepare_for_open_exit"):
			node.call("prepare_for_open_exit", open_exit_door_name)
		for child in node.get_children():
			pending.push_back(child)

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

func _configure_transition_button() -> void:
	if not is_instance_valid(_transition_button):
		return
	# momentary=true: every press emits activated regardless of prior is_active state,
	# so the button fires immediately on each interaction without toggling.
	if "momentary" in _transition_button:
		_transition_button.set("momentary", true)
	if "auto_interact" in _transition_button:
		_transition_button.set("auto_interact", false)
	if "one_off" in _transition_button:
		_transition_button.set("one_off", false)
	if "interaction_text" in _transition_button:
		_transition_button.set("interaction_text", "Presurizar")
	if not _transition_button.is_in_group("interactable"):
		_transition_button.add_to_group("interactable")
	if _transition_button.has_signal("activated") and not _transition_button.is_connected("activated", self, "_on_transition_button_activated"):
		_transition_button.connect("activated", self, "_on_transition_button_activated")
	_reset_transition_button()

func _on_transition_button_activated() -> void:
	request_transition_pressurization()

func _reset_transition_button() -> void:
	if is_instance_valid(_transition_button) and _transition_button.has_method("set_active"):
		_transition_button.set_active(false, true)

func _update_button_interactable() -> void:
	if not is_instance_valid(_transition_button):
		return
	# Button stays interactable so player gets immediate feedback on press.
	# request_transition_pressurization() validates the preconditions internally
	# and shows the label if doors aren't sealed yet.
	if "is_interactable" in _transition_button:
		_transition_button.set("is_interactable", true)

func _entry_door_name_for_cycle() -> String:
	if _waiting_entry_door_name != "":
		return _waiting_entry_door_name
	return "outer" if _is_cycling_in else "inner"

func _exit_door_name_for_cycle() -> String:
	return "inner" if _entry_door_name_for_cycle() == "outer" else "outer"

func _update_airlock_affordances() -> void:
	var outer_color := STATUS_OFF
	var inner_color := STATUS_OFF
	var label_text := ""
	var label_visible := false

	if state == State.ENTRY_OPEN:
		if _entry_door_name_for_cycle() == "outer":
			outer_color = STATUS_READY
			inner_color = STATUS_BLOCKED
		else:
			inner_color = STATUS_READY
			outer_color = STATUS_BLOCKED
	elif state == State.PRESSURIZING:
		if _pressurize_active or _label_linger_timer > 0.0:
			label_text = "PRESURIZANDO" if _pressurize_active else _label_linger_text
			label_visible = true
			outer_color = STATUS_BLOCKED
			inner_color = STATUS_BLOCKED
		else:
			if _entry_door_name_for_cycle() == "outer":
				outer_color = STATUS_READY
				inner_color = STATUS_BLOCKED
			else:
				inner_color = STATUS_READY
				outer_color = STATUS_BLOCKED
	elif state == State.EXIT_OPEN:
		if _label_linger_timer > 0.0:
			label_text = _label_linger_text
			label_visible = true
		if _current_exit_door_name == "outer":
			outer_color = STATUS_READY
			inner_color = STATUS_BLOCKED
		elif _current_exit_door_name == "inner":
			inner_color = STATUS_READY
			outer_color = STATUS_BLOCKED

	_apply_status_light(_outer_status_light, outer_color, outer_color != STATUS_OFF)
	_apply_status_light(_inner_status_light, inner_color, inner_color != STATUS_OFF)
	_set_status_label(label_text, label_visible)
	_update_button_interactable()

func _apply_status_light(node: Node, color: Color, enabled: bool) -> void:
	if not is_instance_valid(node):
		return
	# Prefer set_status_color() — updates light + bulb + indicator LED in one call
	if node.has_method("set_status_color"):
		node.call("set_status_color", color)
	elif "light_color" in node:
		node.set("light_color", color)
		if node.has_method("_apply_settings"):
			node.call("_apply_settings")
	if node.has_method("set_active"):
		node.call("set_active", enabled, true)
	elif node is OmniLight:
		(node as OmniLight).light_color = color
		(node as OmniLight).light_energy = 2.5 if enabled else 0.0

func _set_status_label(text: String, visible: bool) -> void:
	var used_overlay := _set_status_overlay(text, visible)
	if not is_instance_valid(_status_label):
		return
	if "text" in _status_label:
		_status_label.set("text", text)
	if "visible" in _status_label:
		_status_label.set("visible", visible and not used_overlay)

func _set_status_overlay(text: String, visible: bool) -> bool:
	var hints = get_node_or_null("/root/PlayerHintManager")
	if not is_instance_valid(hints):
		return false
	if visible and text.strip_edges() != "":
		var duration := max(_label_linger_timer, 0.35)
		if _pressurize_active:
			duration = max(duration, pressurize_time)
		if hints.has_method("show_status_hint"):
			hints.show_status_hint(text, duration)
			return true
		if hints.has_method("show_manual_hint"):
			hints.show_manual_hint(text, duration)
			return true
	if hints.has_method("clear_status_hint"):
		hints.clear_status_hint()
	return false

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
		"cycling_in": _is_cycling_in,
		"pressurize_active": _pressurize_active,
		"transition_ready": _transition_ready,
		"waiting_entry_door_name": _waiting_entry_door_name,
		"current_exit_door_name": _current_exit_door_name
	}

func restore_snapshot(data: Dictionary):
	self.state = data.get("state", State.IDLE)
	timer = data.get("timer", 0.0)
	_is_cycling_in = data.get("cycling_in", true)
	_pressurize_active = data.get("pressurize_active", false)
	_transition_ready = data.get("transition_ready", false)
	_waiting_entry_door_name = String(data.get("waiting_entry_door_name", ""))
	_current_exit_door_name = String(data.get("current_exit_door_name", ""))
	_label_linger_timer = 0.0
