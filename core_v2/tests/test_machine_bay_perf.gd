extends GdUnitTestSuite

# Medición puntual de la Bahía de máquinas (FD-320 pulido de perf).
# NO es un test de regresión con umbral: imprime métricas de render y costo de tick
# por estación para construir la tabla antes/después. Con el rasterizer dummy
# (CI headless) force_draw/get_render_info devuelven 0 y el caso se saltea.
#
# Correr con el render real:
#   ./runtest.sh --show -a ./core_v2/tests/test_machine_bay_perf.gd
#   STREAMING=0 ./runtest.sh --show -a ./core_v2/tests/test_machine_bay_perf.gd

const BayScene = preload("res://core_v2/levels/machines/MachineBay.tscn")

const POSES := [
	{"name": "spawn",    "pos": Vector3(0, 0.6, -2.0)},
	{"name": "station1", "pos": Vector3(0, 0.6, 7.9)},
	{"name": "station2", "pos": Vector3(0, 6.7, 26.0)},
	{"name": "station3", "pos": Vector3(0, 4.0, 47.0)},
	{"name": "station4", "pos": Vector3(0, 13.2, 66.0)},
	{"name": "station5", "pos": Vector3(0, 10.0, 88.0)},
	{"name": "exit",     "pos": Vector3(0, 10.5, 130.0)},
]

var _bay: Node = null

func _load_bay() -> Node:
	_bay = BayScene.instance()
	get_tree().root.add_child(_bay)
	var pilot: KinematicBody = _bay.get_node("Pilot")
	var session = get_node_or_null("/root/SessionManager")
	if session != null:
		session.player = pilot
	return pilot

func _free_bay() -> void:
	if is_instance_valid(_bay):
		_bay.queue_free()
	_bay = null
	yield(get_tree(), "idle_frame")

func _measure_at(cam: Camera, pilot: KinematicBody, pos: Vector3) -> Dictionary:
	pilot.translation = pos
	cam.global_transform = Transform(Basis.IDENTITY, pos + Vector3(0.0, 1.6, 0.0))
	cam.look_at(pos + Vector3(0.0, 1.0, 60.0), Vector3.UP)
	# Discard warm-up (shaders/streaming).
	for _i in range(12):
		yield(get_tree(), "physics_frame")
	var draws_sum := 0
	var objs_sum := 0
	var verts_sum := 0
	var phys_max := 0.0
	var samples := 6
	for _i in range(samples):
		yield(get_tree(), "physics_frame")
		VisualServer.force_draw()
		draws_sum += int(VisualServer.get_render_info(VisualServer.INFO_DRAW_CALLS_IN_FRAME))
		objs_sum += int(VisualServer.get_render_info(VisualServer.INFO_OBJECTS_IN_FRAME))
		verts_sum += int(VisualServer.get_render_info(VisualServer.INFO_VERTICES_IN_FRAME))
		phys_max = max(phys_max, float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)))
	return {
		"draws": int(round(float(draws_sum) / samples)),
		"objects": int(round(float(objs_sum) / samples)),
		"vertices": int(round(float(verts_sum) / samples)),
		"physics_ms_max": phys_max * 1000.0,
	}

func test_measure_stations() -> void:
	var streaming := OS.get_environment("STREAMING") != "0"
	var pilot := _load_bay()
	var level: Node = _bay.get_node("Level")
	if level.has_method("set_station_streaming_enabled"):
		level.set_station_streaming_enabled(streaming)
	# Un chunk de proximidad por estación (>0): la clave es "station", no las 4 máquinas.
	assert_int(level.get_station_ids().size()).is_greater(0)
	var streamer = level.get_station_streamer()
	if streaming and streamer != null:
		assert_int(streamer.get_chunk_count()).is_equal(level.get_station_ids().size() - 1)
	var cam := Camera.new()
	cam.fov = 75.0
	add_child(cam)
	cam.make_current()
	# Warm-up global.
	for _i in range(20):
		yield(get_tree(), "physics_frame")
	var rows: Array = []
	var any_render := false
	for pose in POSES:
		var r: Dictionary = yield(_measure_at(cam, pilot, pose["pos"]), "completed")
		if r["draws"] > 0:
			any_render = true
		r["pose"] = pose["name"]
		r["streaming"] = streaming
		rows.append(r)
		print("[MEASURE] ", JSON.print(r))
	print("[MEASURE_SUMMARY] streaming=", streaming, " rows=", JSON.print(rows))
	if not any_render:
		print("[MEASURE] rasterizer dummy (sin render): caso salteado")
	yield(_free_bay(), "completed")
