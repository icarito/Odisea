extends Node
class_name StressTestRunner

# StressTestRunner.gd (rewrite)
#
# Genera carga sintética y mide performance promediada por fase sobre la
# telemetría actual (Performance.* / PerformanceMonitor). Reemplaza al runner
# borrado en el cleanup del 1-jun-2026, que escribía una muestra instantánea
# (ruidosa en runners de CI compartidos).
#
# Se maneja vía OYS:
#   CALL StressTestRunner "run_saturation_test" 100
#   ... WAIT ...
#   CALL StressTestRunner "end_phase" "saturation_end"
#
# Cada fase mide FPS/process/physics/node_count promediados durante su ventana
# y al cerrarla emite un snapshot con el tag que espera scripts/check_regression.py
# (saturation_end, spawning_end, pathfinding_end, hierarchy_end, physics_box_end).

const DRONE_SCENE := preload("res://core_v2/actors/CargolDroneV2.tscn")

# Tags que check_regression.py conoce; el orden refleja la secuencia del OYS.
const PHASE_TAGS := ["saturation_end", "spawning_end", "pathfinding_end", "hierarchy_end", "physics_box_end"]

var _active_test := ""
var _spawned := []
var _hierarchy_root: Spatial = null

# Spawning churn (crear/destruir continuamente).
var _spawn_timer := 0.0
var _spawn_rate := 50.0 # por segundo
var _spawn_cap := 200

# Acumuladores de muestreo de la fase activa.
var _sampling := false
var _sample_count := 0
var _acc_fps := 0.0
var _acc_process_ms := 0.0
var _acc_physics_ms := 0.0
var _acc_nodes := 0
# Ignorar las primeras muestras de cada fase para no contar el warmup del spawn.
var _warmup_frames_left := 0
const PHASE_WARMUP_FRAMES := 20

func _ready() -> void:
	var sm := get_node_or_null("/root/SessionManager")
	if sm and sm.has_method("register_oys_actor"):
		sm.register_oys_actor("StressTestRunner", self)
	# En headless el render por software domina el frame (~2-3 FPS) y enmascara el
	# costo real de la carga (spawn/física/AI). Lo desactivamos para que las métricas
	# reflejen el trabajo de lógica, no el render. OYS_FORCE_RENDER lo conserva para
	# depuración visual. (Misma técnica que el fix de los tests de determinismo.)
	if OS.get_environment("OYS_FORCE_RENDER") == "":
		var vp := get_tree().get_root()
		if vp:
			vp.render_target_update_mode = Viewport.UPDATE_DISABLED
			print("[StressTestRunner] Render disabled for stress sampling (set OYS_FORCE_RENDER=1 to keep).")
	print("[StressTestRunner] Ready. Use OYS CALL to run phases.")

func _exit_tree() -> void:
	var sm := get_node_or_null("/root/SessionManager")
	if sm and sm.has_method("unregister_oys_actor"):
		sm.unregister_oys_actor("StressTestRunner")

func _process(delta: float) -> void:
	if _active_test == "spawning":
		_process_spawning(delta)
	elif _active_test == "hierarchy" and is_instance_valid(_hierarchy_root):
		_hierarchy_root.rotate_y(delta * 2.0)

	if _sampling:
		if _warmup_frames_left > 0:
			_warmup_frames_left -= 1
		else:
			_acc_fps += Performance.get_monitor(Performance.TIME_FPS)
			_acc_process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			_acc_physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			_acc_nodes += int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
			_sample_count += 1

# --- Control de muestreo por fase ---

func _begin_sampling() -> void:
	_sampling = true
	_sample_count = 0
	_acc_fps = 0.0
	_acc_process_ms = 0.0
	_acc_physics_ms = 0.0
	_acc_nodes = 0
	_warmup_frames_left = PHASE_WARMUP_FRAMES

# Cierra la fase activa: promedia las muestras, emite el snapshot y limpia la carga.
func end_phase(tag: String) -> void:
	if not (tag in PHASE_TAGS):
		printerr("[StressTestRunner] end_phase tag desconocido para check_regression: '%s'" % tag)
	var n := max(_sample_count, 1)
	var entry := {
		"tag": tag,
		"timestamp": OS.get_unix_time(),
		"fps": _acc_fps / n,
		"process_time_ms": _acc_process_ms / n,
		"physics_time_ms": _acc_physics_ms / n,
		"draw_calls": Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME),
		"objects_in_frame": Performance.get_monitor(Performance.RENDER_OBJECTS_IN_FRAME),
		"vertices_in_frame": Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME),
		"node_count": int(round(float(_acc_nodes) / n)),
		"samples": _sample_count
	}
	_sampling = false
	_write_snapshot(entry)
	stop_test()
	print("[StressTestRunner] Phase '%s' -> fps=%.1f process=%.2fms physics=%.2fms nodes=%d (%d samples)" % [
		tag, entry["fps"], entry["process_time_ms"], entry["physics_time_ms"], entry["node_count"], _sample_count])

# Escribe en el mismo archivo/formato que consume el workflow y check_regression.py.
func _write_snapshot(entry: Dictionary) -> void:
	var path := "user://performance_snapshots.json"
	var data := []
	var f := File.new()
	if f.file_exists(path):
		f.open(path, File.READ)
		var p := JSON.parse(f.get_as_text())
		if p.error == OK and typeof(p.result) == TYPE_ARRAY:
			data = p.result
		f.close()
	data.append(entry)
	f.open(path, File.WRITE)
	f.store_string(JSON.print(data, "  "))
	f.close()

# --- Fases de carga ---

func run_saturation_test(count: int) -> void:
	_cleanup()
	print("[StressTestRunner] Saturation: %d drones" % count)
	for i in range(count):
		var drone = DRONE_SCENE.instance()
		add_child(drone)
		var angle := i * 0.1
		var radius := 5.0 + (i * 0.05)
		drone.translation = Vector3(cos(angle) * radius, 2.0, sin(angle) * radius)
		if drone.has_method("move_to"):
			drone.move_to(Vector3(-drone.translation.x, 2.0, -drone.translation.z))
		_spawned.append(drone)
		if i % 50 == 0:
			yield (get_tree(), "idle_frame")
	_active_test = "saturation"
	_begin_sampling()

func run_spawning_test() -> void:
	_cleanup()
	print("[StressTestRunner] Spawning churn")
	_active_test = "spawning"
	_spawn_timer = 0.0
	_begin_sampling()

func _process_spawning(delta: float) -> void:
	_spawn_timer += delta
	var to_spawn := int(_spawn_timer * _spawn_rate)
	if to_spawn <= 0:
		return
	_spawn_timer -= float(to_spawn) / _spawn_rate
	for i in range(to_spawn):
		var drone = DRONE_SCENE.instance()
		add_child(drone)
		drone.translation = Vector3(rand_range(-20, 20), 5, rand_range(-20, 20))
		_spawned.append(drone)
	# Mantener el conteo acotado destruyendo los más viejos (churn create/destroy).
	while _spawned.size() > _spawn_cap:
		var old = _spawned.pop_front()
		if is_instance_valid(old):
			old.queue_free()

func run_pathfinding_test(agents: int) -> void:
	_cleanup()
	print("[StressTestRunner] Pathfinding: %d agentes" % agents)
	for i in range(agents):
		var drone = DRONE_SCENE.instance()
		add_child(drone)
		drone.translation = Vector3(rand_range(-15, 15), 2.0, rand_range(-15, 15))
		if drone.has_method("move_to"):
			# Destino opuesto para forzar cruces y recomputo de movimiento.
			drone.move_to(Vector3(-drone.translation.x, 2.0, -drone.translation.z))
		_spawned.append(drone)
		if i % 25 == 0:
			yield (get_tree(), "idle_frame")
	_active_test = "pathfinding"
	_begin_sampling()

func run_hierarchy_test(depth: int) -> void:
	_cleanup()
	print("[StressTestRunner] Hierarchy: profundidad %d" % depth)
	_hierarchy_root = Spatial.new()
	add_child(_hierarchy_root)
	var current: Spatial = _hierarchy_root
	for i in range(depth):
		var child := Spatial.new()
		child.translation = Vector3(0, 1, 0)
		current.add_child(child)
		# Ramas anchas además de profundas para estresar la propagación de transforms.
		for _b in range(3):
			var leaf := Spatial.new()
			leaf.translation = Vector3(rand_range(-1, 1), 0, rand_range(-1, 1))
			child.add_child(leaf)
		current = child
	_active_test = "hierarchy"
	_begin_sampling()

func run_physics_box_test(count: int) -> void:
	_cleanup()
	print("[StressTestRunner] Physics: %d cajas" % count)
	for i in range(count):
		var body := RigidBody.new()
		var col := CollisionShape.new()
		var shape := BoxShape.new()
		shape.extents = Vector3(0.5, 0.5, 0.5)
		col.shape = shape
		body.add_child(col)
		var mesh := MeshInstance.new()
		mesh.mesh = CubeMesh.new()
		body.add_child(mesh)
		body.translation = Vector3(rand_range(-5, 5), 3.0 + i * 0.3, rand_range(-5, 5))
		add_child(body)
		_spawned.append(body)
		if i % 25 == 0:
			yield (get_tree(), "idle_frame")
	_active_test = "physics_box"
	_begin_sampling()

func stop_test() -> void:
	_active_test = ""
	_sampling = false
	_cleanup()

func finish() -> void:
	stop_test()
	print("[StressTestRunner] Finished.")

func _cleanup() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	if is_instance_valid(_hierarchy_root):
		_hierarchy_root.queue_free()
	_hierarchy_root = null
