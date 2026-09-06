extends SceneTree

# Valida el controlador del andador: marcha, articulacion y determinismo.
# Corre dos simulaciones de 3.0s con el walker bajo un padre escalado 0.01
# (como en el nivel) y compara el snapshot final.

const WALKER := "res://core_v2/props/machinery/walking_cargo_transporter_rig.tscn"
const SIM_SECONDS := 3.0

var _runs := 0
var _results := []
var _walker: Node
var _foot: Spatial
var _frames := 0
var _foot_min := Vector3.ZERO
var _foot_max := Vector3.ZERO
var _foot_init := false

func _spawn() -> void:
	_frames = 0
	_foot_min = Vector3.ZERO
	_foot_max = Vector3.ZERO
	_foot_init = false
	var packed: PackedScene = load(WALKER)
	var scaled := Spatial.new()
	scaled.scale = Vector3(0.01, 0.01, 0.01)
	root.add_child(scaled)
	_walker = packed.instance()
	scaled.add_child(_walker)
	_foot = _walker.find_node("FootL", true, false)

func _idle(_delta: float) -> bool:
	if _walker == null:
		_spawn()
		return false
	_frames += 1
	var fw: Vector3 = _foot.global_transform.origin
	if not _foot_init:
		_foot_min = fw
		_foot_max = fw
		_foot_init = true
	_foot_min.y = min(_foot_min.y, fw.y)
	_foot_max.y = max(_foot_max.y, fw.y)
	if _walker._time >= SIM_SECONDS:
		_results.append(_walker.get_snapshot())
		_walker.get_parent().queue_free()
		_walker = null
		_runs += 1
		if _runs < 2:
			_spawn()
			return false
		_report()
		return true
	return false

func _report() -> void:
	var a: Dictionary = _results[0]
	var b: Dictionary = _results[1]
	var drift := 0.0
	drift = max(drift, abs(a.time - b.time))
	for i in range(3):
		drift = max(drift, abs(a.origin[i] - b.origin[i]))
	for i in range(a.planted.size()):
		for k in range(3):
			drift = max(drift, abs(a.planted[i][k] - b.planted[i][k]))
			drift = max(drift, abs(a.swing_from[i][k] - b.swing_from[i][k]))
	print("[WctVal] tiempo_sim=%.3f avance_z=%.4f drift_snapshot=%.9f" % [float(a.time), float(a.origin[2]), drift])
	print("[WctVal] rango_vertical_pie=%.3f m (esperado >= 0.20 si el IK articula)" % float(_foot_max.y - _foot_min.y))
	quit(0)
