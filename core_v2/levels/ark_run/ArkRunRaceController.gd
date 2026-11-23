extends Spatial
class_name ArkRunRaceController

# FD-324 F6 — cronometro determinista, reinicio instantaneo y fantasma del mejor
# intento desde replay. Presentacion pura: acumula delta de simulacion y poses;
# no toca fisica, no recarga la escena y no escribe .oys.

const EPSILON := 1e-9

signal race_started()
signal race_finished(summary)
signal best_improved(summary)
signal restart_requested()
signal ghost_saved(trace)

export(float) var engine_z_max := -940.0
export(float) var sample_interval := 0.1
export(float) var reference_time_sec := 0.0
export(float) var margin_threshold_pct := 25.0
export(bool) var build_ghost_visual := true

var t_run := 0.0
var running := false
var finished := false
var best_time_sec := INF
var last_time_sec := INF
var margin_pct := 0.0
var ghost_trace: Array = []
var _current_trace: Array = []
var _next_sample_time := 0.0
var _run_count := 0
var _ghost_mesh: MeshInstance = null
var _ghost_material: SpatialMaterial = null

func start_run() -> void:
	if not running:
		_begin()

func _begin() -> void:
	t_run = 0.0
	running = true
	finished = false
	last_time_sec = INF
	_current_trace = []
	_next_sample_time = 0.0
	_run_count += 1
	emit_signal("race_started")

# Avanza el cronometro, muestrea la pose y cierra si la posicion entra en Motor.
func tick(dt: float, pos: Vector3, basis: Basis = Basis.IDENTITY) -> Dictionary:
	if not running:
		return {"running": false, "t_run": t_run, "finished": finished}
	if dt > 0.0:
		t_run += dt
	if t_run + EPSILON >= _next_sample_time:
		_record_pose(t_run, pos, basis)
		_next_sample_time += max(sample_interval, 1e-3)
	if pos.z <= engine_z_max:
		return finish_run(basis)
	return {"running": true, "t_run": t_run, "finished": false}

func observe(pos: Vector3, basis: Basis = Basis.IDENTITY) -> Dictionary:
	if running and pos.z <= engine_z_max:
		return finish_run(basis)
	return {"running": running, "t_run": t_run, "finished": finished}

# Cierre por distancia al destino del Motor (centro de la placa 0), además del umbral z:
# el Motor es 100% alcanzable aunque el pilot no llegue a cruzar `engine_z_max`.
func observe_target(pos: Vector3, target: Vector3, radius: float,
		basis: Basis = Basis.IDENTITY) -> Dictionary:
	if running and pos.distance_to(target) <= max(radius, 0.0):
		return finish_run(basis)
	return {"running": running, "t_run": t_run, "finished": finished}

func finish_run(basis: Basis = Basis.IDENTITY) -> Dictionary:
	if not running:
		return _summary(false)
	last_time_sec = t_run
	running = false
	finished = true
	var improved := last_time_sec < best_time_sec
	if improved:
		best_time_sec = last_time_sec
		ghost_trace = _current_trace.duplicate(true)
		if build_ghost_visual:
			_ensure_ghost_visual()
	_update_margin()
	var summary := _summary(improved)
	if improved:
		emit_signal("best_improved", summary)
		emit_signal("ghost_saved", ghost_trace)
	emit_signal("race_finished", summary)
	return summary

# Reinicio instantaneo sin recargar la escena: conserva mejor tiempo y fantasma,
# pide reposicionar a Elias y rearma el cronometro en 0.
func restart_run() -> void:
	running = false
	finished = false
	t_run = 0.0
	last_time_sec = INF
	_current_trace = []
	_next_sample_time = 0.0
	emit_signal("restart_requested")
	_begin()

# --- Fantasma (replay del mejor intento) ---

func get_ghost_pose(t: float) -> Dictionary:
	if ghost_trace.empty():
		return {"available": false, "position": Vector3.ZERO, "basis": Basis.IDENTITY, "t": t}
	var first: Dictionary = ghost_trace[0]
	var last: Dictionary = ghost_trace[ghost_trace.size() - 1]
	if t <= float(first["t"]):
		return _pose_from(first, t)
	if t >= float(last["t"]):
		return _pose_from(last, t)
	for index in range(1, ghost_trace.size()):
		var next: Dictionary = ghost_trace[index]
		if float(next["t"]) < t:
			continue
		var prev: Dictionary = ghost_trace[index - 1]
		var span: float = float(next["t"]) - float(prev["t"])
		var f: float = 0.0 if span <= EPSILON else (t - float(prev["t"])) / span
		var pos: Vector3 = (prev["position"] as Vector3).linear_interpolate(next["position"], f)
		var basis: Basis = (prev["basis"] as Basis).slerp(next["basis"], f).orthonormalized()
		return {"available": true, "position": pos, "basis": basis, "t": t}
	return _pose_from(last, t)

func update_ghost_visual(t: float) -> bool:
	if ghost_trace.empty():
		_set_ghost_visible(false)
		return false
	_ensure_ghost_visual()
	var pose: Dictionary = get_ghost_pose(t)
	_ghost_mesh.global_transform = Transform(pose["basis"], pose["position"])
	_ghost_mesh.visible = true
	return true

func _pose_from(sample: Dictionary, t: float) -> Dictionary:
	return {"available": true, "position": sample["position"], "basis": sample["basis"], "t": t}

func _record_pose(time: float, pos: Vector3, basis: Basis) -> void:
	_current_trace.append({"t": time, "position": pos, "basis": basis.orthonormalized()})

func has_ghost_trace() -> bool:
	return not ghost_trace.empty()
func ghost_sample_count() -> int:
	return ghost_trace.size()
func has_ghost_visual() -> bool:
	return _ghost_mesh != null
func get_ghost_material() -> SpatialMaterial:
	return _ghost_material

func _ensure_ghost_visual() -> void:
	if _ghost_mesh != null:
		return
	_ghost_material = SpatialMaterial.new()
	_ghost_material.flags_unshaded = true
	_ghost_material.flags_transparent = true
	_ghost_material.albedo_color = Color(0.35, 0.95, 1.0, 0.32)
	_ghost_material.emission_enabled = true
	_ghost_material.emission = Color(0.2, 0.9, 1.0)
	_ghost_material.emission_energy = 1.1
	_ghost_mesh = MeshInstance.new()
	_ghost_mesh.name = "GhostVisual"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.mid_height = 1.1
	capsule.material = _ghost_material
	_ghost_mesh.mesh = capsule
	_ghost_mesh.visible = false
	add_child(_ghost_mesh)

func _set_ghost_visible(value: bool) -> void:
	if _ghost_mesh != null:
		_ghost_mesh.visible = value

# --- Margen vs. autonavegador (decision #7) ---

func set_reference_time(seconds: float) -> void:
	reference_time_sec = seconds
	_update_margin()

func _update_margin() -> void:
	margin_pct = 0.0
	if reference_time_sec > 0.0 and best_time_sec < INF:
		margin_pct = 100.0 * (reference_time_sec - best_time_sec) / reference_time_sec

func meets_margin() -> bool:
	return margin_pct >= margin_threshold_pct

func _summary(improved: bool) -> Dictionary:
	return {"t_run": last_time_sec, "last_time_sec": last_time_sec, "best_time_sec": best_time_sec,
		"margin_pct": margin_pct, "improved": improved, "meets_margin": meets_margin(),
		"samples": ghost_trace.size(), "run_count": _run_count}
