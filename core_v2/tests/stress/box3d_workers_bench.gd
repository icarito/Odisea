extends SceneTree
# Benchmark de physics/3d/box3d_workers (scheduler multihilo de Box3D).
#
# Arma STACKS pilas de PER cajas RigidBody sobre un piso estatico: islas grandes,
# que es donde b3ParallelFor tiene trabajo que repartir. Corre WARMUP frames de
# calentamiento y mide TIME_PHYSICS_PROCESS promedio en los MEASURE siguientes.
#
# El worker count se lee al crear el world (arranque del motor), asi que se fija
# por override.cfg, no en runtime:
#
#   printf '[physics]\n3d/box3d_workers=4\n' > override.cfg
#   godot --headless --no-window --audio-driver Dummy --path . \
#         --script res://core_v2/tests/stress/box3d_workers_bench.gd
#
# Escribe un JSON a $BOX3D_BENCH_OUT (default user://box3d_workers_bench.json).

const WARMUP := 90
const MEASURE := 300
const STACKS := 24
const PER := 14

var _frames := 0
var _acc := 0.0
var _max := 0.0
var _bodies := 0


func _box(root: Spatial, pos: Vector3, half: float, is_static: bool) -> void:
	var body: PhysicsBody
	if is_static:
		body = StaticBody.new()
	else:
		body = RigidBody.new()
	var cs := CollisionShape.new()
	var bs := BoxShape.new()
	bs.extents = Vector3(half, half, half)
	cs.shape = bs
	body.add_child(cs)
	body.translation = pos
	root.add_child(body)


func _write_json(workers, phys_avg: float, phys_max: float) -> void:
	var out := OS.get_environment("BOX3D_BENCH_OUT")
	if out == "":
		out = "user://box3d_workers_bench.json"
	var data := {
		"tag": "box3d_workers_%s" % str(workers),
		"workers": workers,
		"phys_avg_ms": round(phys_avg * 1000.0) / 1000.0,
		"phys_max_ms": round(phys_max * 1000.0) / 1000.0,
		"bodies": _bodies,
		"frames": MEASURE,
		"cores": OS.get_processor_count(),
		"engine": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
	}
	var f := File.new()
	if f.open(out, File.WRITE) == OK:
		f.store_string(JSON.print(data) + "\n")
		f.close()
	print("[box3d-bench] %s" % JSON.print(data))


func _init():
	print("[box3d-bench] workers=%s engine=%s cores=%d" % [
		str(ProjectSettings.get_setting("physics/3d/box3d_workers")),
		str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		OS.get_processor_count()])
	var root := Spatial.new()
	root.name = "Box3DBench"
	get_root().add_child(root)
	_box(root, Vector3(0, -0.5, 0), 60.0, true)
	for sx in range(STACKS):
		for i in range(PER):
			var px := float(sx % 6) * 1.3 - 3.25
			var pz := float(sx / 6) * 1.3 - 2.6
			_box(root, Vector3(px, 0.45 + float(i) * 0.84, pz), 0.4, false)
			_bodies += 1


func _iteration(_delta: float) -> bool:
	_frames += 1
	if _frames <= WARMUP:
		return false
	var ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_acc += ms
	if ms > _max:
		_max = ms
	if _frames >= WARMUP + MEASURE:
		var avg := _acc / float(MEASURE)
		_write_json(ProjectSettings.get_setting("physics/3d/box3d_workers"), avg, _max)
		print("[box3d-bench] bodies=%d phys_avg=%.2f ms phys_max=%.2f ms" % [_bodies, avg, _max])
		return true
	return false
