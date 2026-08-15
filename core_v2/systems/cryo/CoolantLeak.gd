extends Spatial
class_name CoolantLeak

# CoolantLeak.gd - Deterministic state machine for cryocoolant leak cycle (FD-256 / FD-255).
# Manages HEALTHY -> WARNING -> LEAKING -> SEALED state transitions and leak intensity.

# --- STATE MACHINE ---
enum State { HEALTHY, WARNING, LEAKING, SEALED }

# --- EXPORTED PROPERTIES ---
# If true, the system starts leaking (in WARNING state) on _ready()
export(bool) var starts_leaking: bool = false
# Duration in seconds of condensation warning phase before leak starts
export(float) var warning_duration: float = 4.0
# Duration in seconds for leak intensity to ramp up from 0 to 1
export(float) var ramp_up_duration: float = 3.0
# Duration in seconds for leak intensity to dissipate from current value to 0
export(float) var dissipate_duration: float = 5.0
# If true, leak can be re-triggered after SEALED -> HEALTHY transition
export(bool) var auto_restart: bool = false
# Optional NodePath to a PipeValve node; if set, closing valve calls seal()
export(NodePath) var valve_path: NodePath

# --- SIGNALS ---
signal state_changed(new_state)
signal warning_started()
signal leak_started()
signal leak_sealed()

# --- INTERNAL STATE ---
var _state: int = State.HEALTHY
var _state_timer: float = 0.0
var _leak_intensity: float = 0.0
var _start_intensity: float = 0.0
var _has_been_sealed: bool = false


func _ready() -> void:
	add_to_group("replay_sync")

	if valve_path != null and not valve_path.is_empty():
		var valve = get_node_or_null(valve_path)
		if valve and valve.has_signal("valve_state_changed"):
			valve.connect("valve_state_changed", self, "_on_valve_state_changed")

	if starts_leaking:
		trigger_leak()


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return

	match _state:
		State.HEALTHY:
			_leak_intensity = 0.0

		State.WARNING:
			_leak_intensity = 0.0
			_state_timer += delta
			if _state_timer >= warning_duration:
				_set_state(State.LEAKING)

		State.LEAKING:
			_state_timer += delta
			if ramp_up_duration > 0.0:
				var progress: float = clamp(_state_timer / ramp_up_duration, 0.0, 1.0)
				_leak_intensity = lerp(_start_intensity, 1.0, progress)
			else:
				_leak_intensity = 1.0

		State.SEALED:
			_state_timer += delta
			if dissipate_duration > 0.0:
				var progress: float = clamp(_state_timer / dissipate_duration, 0.0, 1.0)
				_leak_intensity = lerp(_start_intensity, 0.0, progress)
			else:
				_leak_intensity = 0.0

			if _leak_intensity <= 0.0 or _state_timer >= dissipate_duration:
				_leak_intensity = 0.0
				_has_been_sealed = true
				_set_state(State.HEALTHY)


# --- PUBLIC API ---

func get_state() -> int:
	return _state


func get_leak_intensity() -> float:
	return _leak_intensity


func trigger_leak() -> void:
	if _state != State.HEALTHY:
		return
	if _has_been_sealed and not auto_restart:
		return
	_set_state(State.WARNING)


func seal() -> void:
	if _state == State.WARNING:
		_set_state(State.HEALTHY)
		_leak_intensity = 0.0
		emit_signal("leak_sealed")
	elif _state == State.LEAKING:
		_set_state(State.SEALED)


func set_active(value: bool) -> void:
	if value:
		trigger_leak()
	else:
		seal()


func reset() -> void:
	_has_been_sealed = false
	_leak_intensity = 0.0
	_start_intensity = 0.0
	_state_timer = 0.0
	_state = State.HEALTHY
	emit_signal("state_changed", _state)


# --- INTERNAL HELPERS ---

func _set_state(new_state: int) -> void:
	if _state == new_state:
		return
	_state = new_state
	_state_timer = 0.0
	_start_intensity = _leak_intensity

	emit_signal("state_changed", _state)

	match _state:
		State.WARNING:
			emit_signal("warning_started")
		State.LEAKING:
			emit_signal("leak_started")
		State.SEALED:
			emit_signal("leak_sealed")
		State.HEALTHY:
			pass


func _on_valve_state_changed(is_open: bool) -> void:
	if not is_open:
		seal()


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"state": _state,
		"state_timer": _state_timer,
		"leak_intensity": _leak_intensity,
		"start_intensity": _start_intensity,
		"has_been_sealed": _has_been_sealed
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("state"):
		_state = int(data["state"])
	if data.has("state_timer"):
		_state_timer = float(data["state_timer"])
	if data.has("leak_intensity"):
		_leak_intensity = float(data["leak_intensity"])
	if data.has("start_intensity"):
		_start_intensity = float(data["start_intensity"])
	if data.has("has_been_sealed"):
		_has_been_sealed = bool(data["has_been_sealed"])
