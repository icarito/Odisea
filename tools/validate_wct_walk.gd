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
var _knee: Spatial
var _frames := 0
var _foot_min := Vector3.ZERO
var _foot_max := Vector3.ZERO
var _foot_init := false
var _knee_min := 0.0
var _knee_max := 0.0

func _spawn() -> void:
	_frames = 0
	_foot_min = Vector3.ZERO
	_foot_max = Vector3.ZERO
	_foot_init = false
	_knee_min = 0.0
	_knee_max = 0.0
	var packed: PackedScene = load(WALKER)
	var scaled := Spatial.new()
	scaled.scale = Vector3(0.01, 0.01, 0.01)
	root.add_child(scaled)
	_walker = packed.instance()
	scaled.add_child(_walker)
	_foot = _walker.find_node("FootL", true, false)
	_knee = _walker.find_node("KneeL", true, false)

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
	# el perno (la primera rodilla) tiene que doblar: si queda clavado en 0 los
	# huesos 1 y 2 volvieron a ser un triangulo rigido (dos huesos, no tres).
	var knee_x: float = _knee.rotation.x
	_knee_min = min(_knee_min, knee_x)
	_knee_max = max(_knee_max, knee_x)
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
	var foot_range: float = _foot_max.y - _foot_min.y
	var knee_range: float = _knee_max - _knee_min
	print("[WctVal] tiempo_sim=%.3f avance_z=%.4f drift_snapshot=%.9f" % [float(a.time), float(a.origin[2]), drift])
	print("[WctVal] rango_vertical_pie=%.3f m  rango_perno=%.3f rad" % [foot_range, knee_range])
	var fails := []
	if drift > 1e-6:
		fails.append("no determinista (drift %.9f)" % drift)
	if foot_range < 0.20:
		fails.append("el pie casi no levanta (%.3f m): el IK no articula" % foot_range)
	if knee_range < 0.05:
		fails.append("el perno no dobla (%.3f rad): la cadena degenero en dos huesos" % knee_range)
	fails += _check_chain()
	for f in fails:
		print("[WctVal] FALLA: %s" % f)
	print("[WctVal] %s" % ("OK" if fails.empty() else "%d fallas" % fails.size()))
	quit(0 if fails.empty() else 1)

# Cada malla se hornea alrededor del pivote de su propia articulacion: por eso
# el pivote del hijo tiene que caer dentro de la malla del padre. Si no, la
# pieza se dibuja desprendida aunque el IK cierre.
func _check_chain() -> Array:
	var out := []
	var w: Node = load(WALKER).instance()
	for s in ["L", "R"]:
		var chain := ["Hip" + s, "Knee" + s, "Shin" + s, "Foot" + s]
		for i in range(chain.size() - 1):
			var parent: MeshInstance = w.find_node(chain[i], true, false)
			var child: MeshInstance = w.find_node(chain[i + 1], true, false)
			if not parent.mesh.get_aabb().grow(80.0).has_point(child.translation):
				out.append("%s esta desprendido de %s (pivote %s fuera de la malla)" % [
					chain[i + 1], chain[i], child.translation])
	w.free()
	return out
