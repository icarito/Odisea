extends Spatial
class_name PlasmaConduit

# PlasmaConduit.gd - Deterministic state machine for plasma conduit hazard cycle (FD-257 / FD-255).
# Manages NOMINAL -> OVERHEATING -> VENTING -> REROUTED state transitions and hazard intensity.

# --- STATE MACHINE ---
enum State { NOMINAL, OVERHEATING, VENTING, REROUTED }

# --- EXPORTED PROPERTIES ---
# If true, the conduit starts overheating on _ready()
export(bool) var starts_overheating: bool = false
# Duration in seconds of pipe warning phase before plasma vents
export(float) var warning_duration: float = 3.0
# Duration in seconds for hazard intensity to ramp up from 0 to 1
export(float) var ramp_up_duration: float = 1.5
# Duration in seconds for hazard intensity to dissipate from current value to 0 when rerouted
export(float) var shutdown_duration: float = 2.0

# --- SIGNALS ---
signal state_changed(new_state)
signal overheat_started()
signal vent_started()
signal flow_rerouted()

# --- INTERNAL STATE ---
var _state: int = State.NOMINAL
var _state_timer: float = 0.0
var _hazard_intensity: float = 0.0
var _start_intensity: float = 0.0
var _warning_progress: float = 0.0


func _ready() -> void:
	add_to_group("replay_sync")
	if starts_overheating:
		trigger_overheat()


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return

	match _state:
		State.NOMINAL:
			_hazard_intensity = 0.0
			_warning_progress = 0.0

		State.OVERHEATING:
			_hazard_intensity = 0.0
			_state_timer += delta
			if warning_duration > 0.0:
				_warning_progress = clamp(_state_timer / warning_duration, 0.0, 1.0)
			else:
				_warning_progress = 1.0

			if _state_timer >= warning_duration:
				_set_state(State.VENTING)

		State.VENTING:
			_warning_progress = 1.0
			_state_timer += delta
			if ramp_up_duration > 0.0:
				var progress: float = clamp(_state_timer / ramp_up_duration, 0.0, 1.0)
				_hazard_intensity = lerp(_start_intensity, 1.0, progress)
			else:
				_hazard_intensity = 1.0

		State.REROUTED:
			_warning_progress = 0.0
			_state_timer += delta
			if shutdown_duration > 0.0:
				var progress: float = clamp(_state_timer / shutdown_duration, 0.0, 1.0)
				_hazard_intensity = lerp(_start_intensity, 0.0, progress)
			else:
				_hazard_intensity = 0.0

			if _hazard_intensity <= 0.0 or _state_timer >= shutdown_duration:
				_hazard_intensity = 0.0
				_set_state(State.NOMINAL)


# --- PUBLIC API ---

func get_state() -> int:
	return _state


func get_warning_progress() -> float:
	return _warning_progress


func get_hazard_intensity() -> float:
	return _hazard_intensity


func trigger_overheat() -> void:
	if _state != State.NOMINAL and _state != State.REROUTED:
		return
	_set_state(State.OVERHEATING)


func reroute() -> void:
	if _state == State.OVERHEATING or _state == State.VENTING:
		_set_state(State.REROUTED)


func set_active(value: bool) -> void:
	if value:
		trigger_overheat()
	else:
		reroute()


func reset() -> void:
	_hazard_intensity = 0.0
	_start_intensity = 0.0
	_warning_progress = 0.0
	_state_timer = 0.0
	_state = State.NOMINAL
	emit_signal("state_changed", _state)


# --- INTERNAL HELPERS ---

func _set_state(new_state: int) -> void:
	if _state == new_state:
		return
	_state = new_state
	_state_timer = 0.0
	_start_intensity = _hazard_intensity

	emit_signal("state_changed", _state)

	match _state:
		State.OVERHEATING:
			emit_signal("overheat_started")
		State.VENTING:
			emit_signal("vent_started")
		State.REROUTED:
			emit_signal("flow_rerouted")
		State.NOMINAL:
			pass


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"state": _state,
		"state_timer": _state_timer,
		"hazard_intensity": _hazard_intensity,
		"start_intensity": _start_intensity,
		"warning_progress": _warning_progress
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("state"):
		_state = int(data["state"])
	if data.has("state_timer"):
		_state_timer = float(data["state_timer"])
	if data.has("hazard_intensity"):
		_hazard_intensity = float(data["hazard_intensity"])
	if data.has("start_intensity"):
		_start_intensity = float(data["start_intensity"])
	if data.has("warning_progress"):
		_warning_progress = float(data["warning_progress"])
