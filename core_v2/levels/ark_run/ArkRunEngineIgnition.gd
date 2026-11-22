extends Spatial

# FD-324 F5 — encendido de motores del Ark-Run (decisiones #3, #4, #5, #9).
# Trigger determinista: arma al pasar proa (z >= bridge_arm_z) y dispara
# EXACTAMENTE al cruzar z = 0 de regreso (prev_z > 0 ∧ z <= 0), nunca por reloj.
# IDLE -> WARNING -> RAMP (3 s) -> SUSTAINED (30 s) -> COOLDOWN. Al encender:
# industria -> AXIAL y falla estática determinista por hash(seed, índice); cada
# pieza fallida hace un colapso cinemático de 1 s sin RigidBody y queda fija.
# El plan de fallas y el colapso viven en ArkRunCollapseAnim (helper <200).
# Sin randf()/randomize().

const CollapseScript = preload("res://core_v2/levels/ark_run/ArkRunCollapseAnim.gd")
const SLICE_SEED := 32401
const IGNITION_Z := 0.0
const ELEVATOR_FAIL_PERCENT := 380

enum State { IDLE, WARNING, RAMP, SUSTAINED, COOLDOWN }
const STATE_NAMES := ["IDLE", "WARNING", "RAMP", "SUSTAINED", "COOLDOWN"]

signal warning_started(z)
signal ignition_triggered(time_since_arm)
signal state_changed(state)
signal deterministic_failures_applied(summary)
signal collapse_started(key)
signal collapse_completed(key)

export(float) var bridge_arm_z := 600.0
export(float) var warning_z := 200.0
export(float) var warning_duration := 3.0
export(float) var peak_accel := 9.8
export(float) var ramp_sec := 3.0
export(float) var sustain_sec := 30.0
export(int) var seed_value := SLICE_SEED
export(int) var elevator_fail_percent := ELEVATOR_FAIL_PERCENT
export(NodePath) var pilot_path := NodePath("")

var state: int = State.IDLE
var armed := false
var ignited := false
var countdown := 0.0
var _sim_t := 0.0
var _ignite_t := -1.0
var _warning_t := -1.0
var _prev_z := 0.0
var _has_prev := false
var _pilot = null
var _industry_streamer = null
var _elevators: Array = []
var _failure_summary: Dictionary = {}
var _collapse = CollapseScript.new()

func _ready() -> void:
	if pilot_path != NodePath(""):
		_pilot = get_node_or_null(pilot_path)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if _pilot == null or not is_instance_valid(_pilot):
		_resolve_pilot()
	var z := 0.0
	if _pilot != null and is_instance_valid(_pilot):
		z = _pilot.global_transform.origin.z
	advance(delta, z)

func _resolve_pilot() -> void:
	var parent := get_parent()
	if parent != null:
		_pilot = parent.get_node_or_null("../Pilot")
	if _pilot == null and is_inside_tree():
		var players := get_tree().get_nodes_in_group("player")
		if not players.empty():
			_pilot = players[0]

func set_industry_streamer(s) -> void: _industry_streamer = s
func add_elevator(e) -> void:
	if e != null and is_instance_valid(e):
		_elevators.append(e)

# --- Perfil axial puro (decisión #3) ---
static func sample_axial_accel(
	t: float, p_peak: float = 9.8, p_ramp: float = 3.0, p_sustain: float = 30.0
) -> float:
	if t <= 0.0:
		return 0.0
	if p_ramp <= 0.0:
		return p_peak if t <= p_sustain else 0.0
	if t < p_ramp:
		return p_peak * (t / p_ramp)
	if t <= p_ramp + p_sustain:
		return p_peak
	return 0.0

# Falla determinista (decisión #9): hash(seed, índice) en el helper de colapso.
static func should_fail_index(p_seed: int, index: int, percent: int = ELEVATOR_FAIL_PERCENT) -> bool:
	return CollapseScript.should_fail_index(p_seed, index, percent)

# --- Paso determinista: `delta` fijo + z del Pilot ---
func advance(delta: float, z: float) -> void:
	_sim_t += max(delta, 0.0)
	var prev_z: float = _prev_z
	if not _has_prev:
		prev_z = z
		_has_prev = true
	if not armed and z >= bridge_arm_z:
		armed = true
	if armed and not ignited:
		if state == State.IDLE and z > IGNITION_Z and z <= warning_z:
			_enter_warning()
		if prev_z > IGNITION_Z and z <= IGNITION_Z and z <= prev_z:
			_ignite()
	_update_state_timing()
	_update_countdown()
	_advance_collapses(delta)
	_prev_z = z

func _enter_warning() -> void:
	state = State.WARNING
	_warning_t = _sim_t
	emit_signal("warning_started", _prev_z)

func _ignite() -> void:
	ignited = true
	_ignite_t = _sim_t
	_set_state(State.RAMP)
	emit_signal("ignition_triggered", _sim_t)
	apply_deterministic_failures()

func _update_state_timing() -> void:
	if not ignited:
		return
	var t := _sim_t - _ignite_t
	if t < ramp_sec:
		_set_state(State.RAMP)
	elif t <= ramp_sec + sustain_sec:
		_set_state(State.SUSTAINED)
	else:
		_set_state(State.COOLDOWN)

func _update_countdown() -> void:
	if state == State.WARNING:
		countdown = max(0.0, warning_duration - max(0.0, _sim_t - _warning_t))
	elif state == State.RAMP:
		countdown = max(0.0, ramp_sec - (_sim_t - _ignite_t))
	elif state == State.SUSTAINED:
		countdown = max(0.0, ramp_sec + sustain_sec - (_sim_t - _ignite_t))
	else:
		countdown = 0.0

func _set_state(next_state: int) -> void:
	if state == next_state:
		return
	state = next_state
	emit_signal("state_changed", state)

# --- Reacople + falla estática (decisión #9) ---
func apply_deterministic_failures() -> Dictionary:
	var result: Dictionary = _collapse.plan_failures(
		_elevators, _industry_streamer, seed_value, elevator_fail_percent)
	for key in result["started"]:
		emit_signal("collapse_started", key)
	_failure_summary = result["summary"]
	emit_signal("deterministic_failures_applied", _failure_summary)
	return _failure_summary

func _advance_collapses(delta: float) -> void:
	for key in _collapse.advance(delta):
		emit_signal("collapse_completed", key)

# --- Getters deterministas para Suit OS / audio / predictor / tests ---
func get_axial_accel() -> float:
	return sample_axial_accel(_sim_t - _ignite_t, peak_accel, ramp_sec, sustain_sec) if ignited else 0.0
func get_state() -> int: return state
func get_state_name() -> String: return String(STATE_NAMES[state])
func get_ignition_state() -> String:
	if state == State.WARNING: return "WARNING"
	if ignited and state != State.COOLDOWN: return "ACTIVE"
	return "IDLE"
func get_countdown() -> float: return countdown
func is_armed() -> bool: return armed
func is_ignited() -> bool: return ignited
func get_time_since_ignite() -> float: return (_sim_t - _ignite_t) if ignited else -1.0
func get_warning_remaining() -> float: return countdown if state == State.WARNING else 0.0
func is_warning_active() -> bool: return state == State.WARNING
func get_failure_summary() -> Dictionary: return _failure_summary.duplicate(true)
func get_elevator_decisions() -> Array:
	return (_failure_summary.get("decisions", []) as Array).duplicate(true)
func get_collapse_keys() -> Array: return _collapse.get_keys()
func get_collapse_state(key: String) -> Dictionary: return _collapse.get_state(key)

# Reinicio instantáneo (F6/F7): rearma sin recargar la escena.
func reset() -> void:
	state = State.IDLE; armed = false; ignited = false; countdown = 0.0
	_sim_t = 0.0; _ignite_t = -1.0; _warning_t = -1.0; _prev_z = 0.0; _has_prev = false
	_failure_summary = {}; _collapse = CollapseScript.new()
