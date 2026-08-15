extends Spatial
class_name AuxPowerBus

# AuxPowerBus.gd - Deterministic Auxiliary Power Bus controller (FD-259 / FD-255).
# Manages emergency sector power status: OFFLINE -> RESTORING -> POWERED.

# --- STATE MACHINE ---
enum State { POWERED, OFFLINE, RESTORING }

# --- EXPORTED PROPERTIES ---
# If true, bus starts without power in OFFLINE state.
export(bool) var starts_offline: bool = true
# Duration in seconds for power level to ramp from current value to 1.0 during RESTORING phase.
export(float) var restore_duration: float = 2.5
# Period in seconds for deterministic flicker calculation when OFFLINE.
export(float) var flicker_period: float = 0.8

# --- SIGNALS ---
signal state_changed(new_state)
signal power_restored()
signal power_lost()

# --- INTERNAL STATE ---
var _state: int = State.OFFLINE
var _state_timer: float = 0.0
var _power_level: float = 0.0
var _start_power_level: float = 0.0


func _ready() -> void:
	add_to_group("replay_sync")

	if starts_offline:
		_state = State.OFFLINE
		_power_level = 0.0
	else:
		_state = State.POWERED
		_power_level = 1.0

	_state_timer = 0.0
	_start_power_level = _power_level


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return

	_state_timer += delta

	match _state:
		State.OFFLINE:
			_power_level = 0.0

		State.RESTORING:
			if restore_duration > 0.0:
				var progress: float = clamp(_state_timer / restore_duration, 0.0, 1.0)
				_power_level = lerp(_start_power_level, 1.0, progress)
			else:
				_power_level = 1.0

			if _power_level >= 1.0 or _state_timer >= restore_duration:
				_power_level = 1.0
				_set_state(State.POWERED)

		State.POWERED:
			_power_level = 1.0


# --- PUBLIC API ---

func get_state() -> int:
	return _state


func get_power_level() -> float:
	return _power_level


func is_powered() -> bool:
	return _state == State.POWERED


func request_restore() -> void:
	if _state == State.POWERED or _state == State.RESTORING:
		return

	if restore_duration <= 0.0:
		_power_level = 1.0
		_set_state(State.POWERED)
	else:
		_set_state(State.RESTORING)


func cut_power() -> void:
	if _state == State.OFFLINE:
		return

	_power_level = 0.0
	_set_state(State.OFFLINE)


func set_active(value: bool) -> void:
	if value:
		request_restore()
	else:
		cut_power()


func get_flicker_phase() -> float:
	if _state == State.OFFLINE:
		if flicker_period > 0.0:
			return fmod(_state_timer, flicker_period) / flicker_period
		return 0.0
	return 0.0


# --- INTERNAL HELPERS ---

func _set_state(new_state: int) -> void:
	if _state == new_state:
		return

	_state = new_state
	_state_timer = 0.0
	_start_power_level = _power_level

	emit_signal("state_changed", _state)

	match _state:
		State.POWERED:
			emit_signal("power_restored")
		State.OFFLINE:
			emit_signal("power_lost")
		State.RESTORING:
			pass


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"state": _state,
		"state_timer": _state_timer,
		"power_level": _power_level,
		"start_power_level": _start_power_level
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("state"):
		_state = int(data["state"])
	if data.has("state_timer"):
		_state_timer = float(data["state_timer"])
	if data.has("power_level"):
		_power_level = float(data["power_level"])
	if data.has("start_power_level"):
		_start_power_level = float(data["start_power_level"])
