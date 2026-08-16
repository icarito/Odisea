extends Spatial
class_name PressureSection

# PressureSection.gd - Deterministic state machine for sector atmospheric pressure (FD-258 / FD-255).
# Manages NOMINAL -> RISING -> CRITICAL -> blowout -> VENTED -> NOMINAL cycle.

enum State { NOMINAL, RISING, CRITICAL, VENTED }

# If true, pressure starts rising in _ready().
export(bool) var starts_rising: bool = false
# Duration in seconds of warning phase (RISING) before reaching critical pressure.
export(float) var warning_duration: float = 8.0
# Duration in seconds of spark phase (CRITICAL) before blowout.
export(float) var spark_duration: float = 2.5
# Duration in seconds for pressure to recover back to 1.0 during VENTED state.
export(float) var recover_duration: float = 3.0
# Critical overpressure value reached at peak.
# Si es true, la presión NO sube sola durante RISING: sube solo mientras algo la inyecta
# (la bomba manual). Es lo que hace legible la relación entre el mando y el manómetro:
# bombeo y la aguja trepa, suelto y se queda. Con false, RISING corre por tiempo, que es
# el comportamiento para una fuga que se descontrola sola.
export(bool) var rise_needs_input: bool = false
export(float) var critical_pressure: float = 2.4
# Radius in meters for the blowout explosion event.
export(float) var blowout_radius: float = 6.0
# Force magnitude for the blowout explosion impulse.
export(float) var blowout_force: float = 12.0

signal state_changed(new_state)
signal alarm_started()
signal spark_started()
signal blowout(radius, force)
signal pressure_stabilized()

var _state: int = State.NOMINAL
var _state_timer: float = 0.0
var _pressure: float = 1.0
var _start_pressure: float = 1.0
var _has_blown_out: bool = false


func _ready() -> void:
	add_to_group("replay_sync")
	if starts_rising:
		raise_pressure()


func _physics_process(delta: float) -> void:
	if Engine.editor_hint:
		return

	match _state:
		State.NOMINAL:
			_pressure = 1.0

		State.RISING:
			if not rise_needs_input:
				_state_timer += delta
			if warning_duration > 0.0:
				var progress: float = clamp(_state_timer / warning_duration, 0.0, 1.0)
				_pressure = lerp(1.0, critical_pressure, progress)
			else:
				_pressure = critical_pressure

			if _state_timer >= warning_duration:
				_set_state(State.CRITICAL)

		State.CRITICAL:
			_pressure = critical_pressure
			_state_timer += delta
			if _state_timer >= spark_duration:
				if not _has_blown_out:
					_has_blown_out = true
					emit_signal("blowout", blowout_radius, blowout_force)
				_set_state(State.VENTED)

		State.VENTED:
			_state_timer += delta
			if recover_duration > 0.0:
				var progress: float = clamp(_state_timer / recover_duration, 0.0, 1.0)
				_pressure = lerp(_start_pressure, 1.0, progress)
			else:
				_pressure = 1.0

			if _state_timer >= recover_duration or _pressure <= 1.0:
				_pressure = 1.0
				_has_blown_out = false
				_set_state(State.NOMINAL)


func get_state() -> int:
	return _state


func get_pressure() -> float:
	return _pressure


func is_sealed() -> bool:
	return _state != State.NOMINAL


func get_alarm_phase() -> float:
	match _state:
		State.RISING:
			if warning_duration > 0.0:
				return clamp(_state_timer / warning_duration, 0.0, 1.0)
			return 1.0
		State.CRITICAL:
			return 1.0
		_:
			return 0.0


func raise_pressure() -> void:
	if _state == State.NOMINAL:
		_has_blown_out = false
		_set_state(State.RISING)


func inject(seconds: float) -> void:
	"""Bombear: mete presión al sector. El argumento es tiempo de bombeo, así la escala
	del manómetro sigue siendo la misma que cuando la presión sube sola."""
	if _state == State.NOMINAL:
		raise_pressure()
	if _state == State.RISING:
		_state_timer += max(seconds, 0.0)


func purge() -> void:
	if _state == State.RISING or _state == State.CRITICAL:
		emit_signal("pressure_stabilized")
		_set_state(State.VENTED)


func set_active(value: bool) -> void:
	if value:
		raise_pressure()
	else:
		purge()


func reset() -> void:
	_has_blown_out = false
	_pressure = 1.0
	_start_pressure = 1.0
	_state_timer = 0.0
	_state = State.NOMINAL
	emit_signal("state_changed", _state)


func _set_state(new_state: int) -> void:
	if _state == new_state:
		return
	_state = new_state
	_state_timer = 0.0
	_start_pressure = _pressure

	emit_signal("state_changed", _state)

	match _state:
		State.RISING:
			emit_signal("alarm_started")
		State.CRITICAL:
			emit_signal("spark_started")
		State.VENTED:
			pass
		State.NOMINAL:
			pass


func get_snapshot() -> Dictionary:
	return {
		"state": _state,
		"state_timer": _state_timer,
		"pressure": _pressure,
		"start_pressure": _start_pressure,
		"has_blown_out": _has_blown_out
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("state"):
		_state = int(data["state"])
	if data.has("state_timer"):
		_state_timer = float(data["state_timer"])
	if data.has("pressure"):
		_pressure = float(data["pressure"])
	if data.has("start_pressure"):
		_start_pressure = float(data["start_pressure"])
	if data.has("has_blown_out"):
		_has_blown_out = bool(data["has_blown_out"])
