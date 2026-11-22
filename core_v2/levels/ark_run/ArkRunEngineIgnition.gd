extends Spatial

# FD-324 F5 — encendido de motores del Ark-Run (decisiones #3, #4, #5, #9).
# Trigger determinista: arma al pasar proa (z >= bridge_arm_z) y dispara
# EXACTAMENTE al cruzar z = 0 de regreso (prev_z > 0 ∧ z <= 0), nunca por reloj.
# IDLE -> WARNING -> RAMP (3 s) -> SUSTAINED (30 s) -> COOLDOWN. Al encender:
# industria -> AXIAL y falla estática determinista por hash(seed, índice); cada
# pieza fallida (ascensor o compuerta) hace un colapso cinemático de 1 s sin
# RigidBody y queda fija. Sin randf()/randomize().

const Catalog = preload("res://core_v2/levels/ark_run/ArkRunIndustryChunk.gd")
const ConversionScript = preload("res://core_v2/levels/ark_run/ArkRunTerraceConversion.gd")
const SLICE_SEED := 32401
const IGNITION_Z := 0.0
const ELEVATOR_FAIL_PERCENT := 380
const COLLAPSE_DURATION := 1.0

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
var _sim_t := 0.0
var _ignite_t := -1.0
var _warning_t := -1.0
var _prev_z := 0.0
var _has_prev := false
var _pilot = null
var _industry_streamer = null
var _elevators: Array = []
var _elevator_decisions: Array = []
var _collapses: Array = []
var _failure_summary: Dictionary = {}

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

# --- Falla determinista (decisión #9): hash(seed, índice) ---
static func should_fail_index(p_seed: int, index: int, percent: int = ELEVATOR_FAIL_PERCENT) -> bool:
	return (_hash_index(p_seed, index) % 1000) < int(clamp(percent, 0, 1000))

static func _hash_index(p_seed: int, index: int) -> int:
	var h := (p_seed * 2654435761 + index * 40503 + 0x9E3779B1) & 0x7fffffff
	h = (h ^ (h >> 13)) & 0x7fffffff
	h = (h * 1274126177 + 12345) & 0x7fffffff
	return (h ^ (h >> 16)) & 0x7fffffff

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

func _set_state(next_state: int) -> void:
	if state == next_state:
		return
	state = next_state
	emit_signal("state_changed", state)

# --- Reacople + falla estática (decisión #9) ---
func apply_deterministic_failures() -> Dictionary:
	var mode := Catalog.GRAVITY_AXIAL
	if _industry_streamer != null and is_instance_valid(_industry_streamer) \
			and _industry_streamer.has_method("apply_gravity_mode"):
		_industry_streamer.apply_gravity_mode(mode)
	var sorted := _sorted_elevators()
	_elevator_decisions.clear()
	var failed := 0
	for index in range(sorted.size()):
		var elevator = sorted[index]["node"]
		if elevator == null or not is_instance_valid(elevator):
			continue
		var fails := should_fail_index(seed_value, index, elevator_fail_percent)
		if elevator.has_method("set_operational"):
			elevator.set_operational(not fails)
		if fails:
			failed += 1
			_start_collapse(elevator, "elevator:" + str(sorted[index]["key"]), index)
		_elevator_decisions.append({
			"key": str(sorted[index]["key"]), "index": index, "failed": fails, "operational": not fails,
		})
	_start_connection_collapses()
	_failure_summary = {
		"mode": mode, "elevators": _elevator_decisions.size(), "failed": failed,
		"hash": ((seed_value * 31 + _elevator_decisions.size() * 7919 + failed * 104729) ^ (_elevator_decisions.size() * 17)) & 0x7fffffff,
		"decisions": _elevator_decisions.duplicate(true),
	}
	emit_signal("deterministic_failures_applied", _failure_summary)
	return _failure_summary

# Compuertas de conexión bloqueadas por AXIAL: colapso cinemático de cada una.
func _start_connection_collapses() -> void:
	if _industry_streamer == null or not is_instance_valid(_industry_streamer):
		return
	var gates = _industry_streamer.get("_gate_shapes")
	var route = _industry_streamer.get("_route_state")
	if typeof(gates) != TYPE_DICTIONARY or typeof(route) != TYPE_DICTIONARY:
		return
	var keys: Array = gates.keys()
	keys.sort()
	for i in range(keys.size()):
		var gkey := str(keys[i])
		var decision: Dictionary = route.get(gkey, {})
		if decision.empty() or bool(decision.get("relinked", false)):
			continue
		_start_collapse(gates[keys[i]], "conn:" + gkey, 1000 + i)

func _start_collapse(node, key: String, hash_index: int) -> void:
	if node == null or not is_instance_valid(node):
		return
	for entry in _collapses:
		if entry["node"] == node:
			return
	var h := _hash_index(seed_value, hash_index)
	_collapses.append({
		"node": node, "key": key, "base": _world_xf(node),
		"direction": Vector3(0.0, 0.0, -1.0 if (h & 1) == 0 else 1.0),
		"angle": deg2rad(8.0 + float(h % 7)), "drop": 0.4 + float((h >> 3) % 5) * 0.1,
		"elapsed": 0.0, "u": 0.0, "done": false,
	})
	emit_signal("collapse_started", key)

func _advance_collapses(delta: float) -> void:
	var dt := max(delta, 0.0)
	for entry in _collapses:
		if bool(entry["done"]):
			continue
		entry["elapsed"] = float(entry["elapsed"]) + dt
		var u: float = ConversionScript.collapse_progress(float(entry["elapsed"]), COLLAPSE_DURATION)
		entry["u"] = u
		_set_world_xf(entry["node"], ConversionScript.sample_collapse(
			entry["base"], u, entry["direction"], entry["angle"], entry["drop"]))
		if u >= 1.0:
			entry["done"] = true
			emit_signal("collapse_completed", entry["key"])

func _world_xf(node) -> Transform:
	return node.global_transform if node.is_inside_tree() else node.transform

func _set_world_xf(node, xform: Transform) -> void:
	if node.is_inside_tree():
		node.global_transform = xform
	else:
		node.transform = xform

func _sorted_elevators() -> Array:
	var entries := []
	for index in range(_elevators.size()):
		var elevator = _elevators[index]
		if elevator == null or not is_instance_valid(elevator):
			continue
		var parent = elevator.get_parent()
		var key := ("%s/%s" % [str(parent.name), str(elevator.name)]) if parent != null else ("e%03d" % index)
		entries.append({"key": key, "node": elevator})
	entries.sort_custom(self, "_sort_entry")
	return entries

func _sort_entry(a, b) -> bool: return str(a["key"]) < str(b["key"])

# --- Getters deterministas para Suit OS / audio / predictor / tests ---
func get_axial_accel() -> float:
	return sample_axial_accel(_sim_t - _ignite_t, peak_accel, ramp_sec, sustain_sec) if ignited else 0.0
func get_state() -> int: return state
func get_state_name() -> String: return String(STATE_NAMES[state])
func is_armed() -> bool: return armed
func is_ignited() -> bool: return ignited
func get_time_since_ignite() -> float: return (_sim_t - _ignite_t) if ignited else -1.0
func get_warning_remaining() -> float: return max(0.0, warning_duration - max(0.0, _sim_t - _warning_t)) if _warning_t >= 0.0 else 0.0
func is_warning_active() -> bool: return state == State.WARNING
func get_failure_summary() -> Dictionary: return _failure_summary.duplicate(true)
func get_elevator_decisions() -> Array: return _elevator_decisions.duplicate(true)
func get_collapse_keys() -> Array:
	var keys := []
	for entry in _collapses:
		keys.append(str(entry["key"]))
	return keys
func get_collapse_state(key: String) -> Dictionary:
	for entry in _collapses:
		if str(entry["key"]) == key:
			return {
				"node": entry["node"], "base": entry["base"], "direction": entry["direction"],
				"angle": entry["angle"], "drop": entry["drop"], "u": entry["u"], "done": entry["done"],
			}
	return {}
