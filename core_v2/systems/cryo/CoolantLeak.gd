extends Spatial
class_name CoolantLeak

# CoolantLeak.gd - Deterministic state machine for cryocoolant leak cycle (FD-256 / FD-255 / FD-266).
# Manages HEALTHY -> WARNING -> LEAKING -> DEPRESSURIZED / SEALED state transitions and leak intensity.

# --- STATE MACHINE ---
# DEPRESSURIZED: El tramo no tiene caudal porque la válvula aguas arriba está cerrada.
# Se diferencia de SEALED porque la fisura física no ha sido reparada; reabrir la
# válvula sin haber aplicado un parche firme volverá a soltar el refrigerante.
enum State { HEALTHY, WARNING, LEAKING, SEALED, DEPRESSURIZED }

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
# Optional NodePath to a PipeValve node; if set, closing valve depressurizes
export(NodePath) var valve_path: NodePath
# Optional NodePath to a Room3D environmental aggregator
export(NodePath) var room_path: NodePath
export(float) var leak_temp_rate: float = 5.0
export(float) var leak_contam_rate: float = 0.1

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
var _is_provisionally_patched: bool = false


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
			if _is_provisionally_patched:
				if dissipate_duration > 0.0:
					var progress: float = clamp(_state_timer / dissipate_duration, 0.0, 1.0)
					_leak_intensity = lerp(_start_intensity, 0.0, progress)
				else:
					_leak_intensity = 0.0
			else:
				if ramp_up_duration > 0.0:
					var progress: float = clamp(_state_timer / ramp_up_duration, 0.0, 1.0)
					_leak_intensity = lerp(_start_intensity, 1.0, progress)
				else:
					_leak_intensity = 1.0

		State.DEPRESSURIZED:
			_state_timer += delta
			if dissipate_duration > 0.0:
				var progress: float = clamp(_state_timer / dissipate_duration, 0.0, 1.0)
				_leak_intensity = lerp(_start_intensity, 0.0, progress)
			else:
				_leak_intensity = 0.0

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

	_apply_room_deltas(delta)


# --- PUBLIC API ---

func get_state() -> int:
	return _state


func get_leak_intensity() -> float:
	return _leak_intensity


func is_depressurized() -> bool:
	return _state == State.DEPRESSURIZED


func set_provisionally_patched(value: bool) -> void:
	if _is_provisionally_patched == value:
		return
	_is_provisionally_patched = value
	_start_intensity = _leak_intensity
	_state_timer = 0.0


func trigger_leak() -> void:
	if valve_path != null and not valve_path.is_empty():
		var valve = get_node_or_null(valve_path)
		if valve != null and "is_active" in valve and not bool(valve.get("is_active")):
			_set_state(State.DEPRESSURIZED)
			return

	# Reabrir mientras está despresurizado vuelve a la fuga sin pasar por el aviso:
	# el caño sigue roto, no hay nada que anticipar de nuevo.
	if _state == State.DEPRESSURIZED:
		_set_state(State.LEAKING)
		return
	if _state == State.SEALED:
		_set_state(State.LEAKING)
		return
	if _state != State.HEALTHY:
		return
	if _has_been_sealed and not auto_restart:
		return
	_set_state(State.WARNING)


func seal() -> void:
	_is_provisionally_patched = false
	if _state == State.WARNING:
		_has_been_sealed = true
		_set_state(State.HEALTHY)
		_leak_intensity = 0.0
		emit_signal("leak_sealed")
	elif _state == State.LEAKING or _state == State.DEPRESSURIZED:
		_set_state(State.SEALED)


func set_active(value: bool) -> void:
	# El grafo OCLS llama set_active() sobre cada nodo PROP cuando cambia la energia
	# aguas arriba (LogicCircuitManager). Para una fisura eso significa lo mismo que
	# cerrar la valvula: se corta el caudal, el cano sigue roto. Sellar aca reparaba
	# la averia sola cada vez que el circuito se apagaba — la misma semantica que
	# FD-266 vino a eliminar, entrando por la otra puerta.
	if value:
		trigger_leak()
	else:
		depressurize()


func depressurize() -> void:
	# Unico camino a DEPRESSURIZED: la valvula y el grafo entran los dos por aca para
	# que no se vuelvan a desincronizar.
	if _state == State.WARNING or _state == State.LEAKING:
		_set_state(State.DEPRESSURIZED)


func reset() -> void:
	_has_been_sealed = false
	_is_provisionally_patched = false
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
		State.DEPRESSURIZED, State.HEALTHY:
			pass


func _apply_room_deltas(delta: float) -> void:
	if _leak_intensity <= 0.0 or room_path == null or room_path.is_empty():
		return
	var room = get_node_or_null(room_path)
	if room != null:
		if room.has_method("add_temperature"):
			room.call("add_temperature", -leak_temp_rate * _leak_intensity * delta)
		if room.has_method("add_contamination"):
			room.call("add_contamination", leak_contam_rate * _leak_intensity * delta)


func _on_valve_state_changed(is_open: bool) -> void:
	# La válvula corta el caudal, no repara el caño: mientras la fuga no esté arreglada,
	# abrirla vuelve a soltar coolant y cerrarla despresuriza el tramo.
	if is_open:
		trigger_leak()
	else:
		depressurize()


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"state": _state,
		"state_timer": _state_timer,
		"leak_intensity": _leak_intensity,
		"start_intensity": _start_intensity,
		"has_been_sealed": _has_been_sealed,
		"is_provisionally_patched": _is_provisionally_patched
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
	if data.has("is_provisionally_patched"):
		_is_provisionally_patched = bool(data["is_provisionally_patched"])
