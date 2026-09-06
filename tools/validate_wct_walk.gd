extends SceneTree

# Valida el controlador del andador: sin errores, marcha avanza y
# determinismo (compara el snapshot final a 3.0s de simulacion).

const WALKER := "res://core_v2/props/machinery/walking_cargo_transporter_rig.tscn"
const SIM_SECONDS := 3.0

var _runs := 0
var _results := []
var _walker: Node
var _frames := 0

func _spawn() -> void:
	_frames = 0
	var packed: PackedScene = load(WALKER)
	_walker = packed.instance()
	root.add_child(_walker)

func _idle(_delta: float) -> bool:
	if _walker == null:
		_spawn()
		return false
	_frames += 1
	if _walker._time >= SIM_SECONDS:
		_results.append(_walker.get_snapshot())
		root.remove_child(_walker)
		_walker.queue_free()
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
	print("[WctVal] tiempo_sim=%.3f origen_z=%.4f drift_snapshot=%.9f" % [float(a.time), float(a.origin[2]), drift])
	quit(0)
