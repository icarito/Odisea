extends GdUnitTestSuite

# test_pipe_router.gd — TestSuite para PipeRouter y PipeRun (FD-262).

const PipeRouterScript = preload("res://core_v2/systems/pipe/PipeRouter.gd")
const PipeRunScript = preload("res://core_v2/systems/pipe/PipeRun.gd")

var _broken_emitted: bool = false

func _on_pipe_broken_event() -> void:
	_broken_emitted = true


func test_pipe_router_generate_route() -> void:
	var router = PipeRouterScript.new()
	var from_pos = Vector3(0, 0, 0)
	var to_pos = Vector3(5, 1, 5)
	var options = {
		"clearance": 2.5,
		"snap": 0.5,
		"offset": 0.15
	}

	var curve = router.generate_route(from_pos, to_pos, options)
	assert_object(curve).is_not_null()
	assert_bool(curve.get_point_count() >= 2).is_true()

	var baked = curve.get_baked_points()
	assert_bool(baked.size() >= 2).is_true()

	# Verificar que el camino sube hacia el techo antes de descender al objetivo
	var max_y: float = 0.0
	for p in baked:
		if p.y > max_y:
			max_y = p.y

	assert_bool(max_y >= 2.5).is_true()
	router.free()


func test_pipe_router_determinism() -> void:
	var router = PipeRouterScript.new()
	var from_pos = Vector3(2.0, 0.5, -1.0)
	var to_pos = Vector3(-4.0, 1.2, 8.0)
	var options = {
		"clearance": 3.0,
		"snap": 0.5,
		"offset": 0.2
	}

	var curve1 = router.generate_route(from_pos, to_pos, options)
	var curve2 = router.generate_route(from_pos, to_pos, options)

	var points1 = curve1.get_baked_points()
	var points2 = curve2.get_baked_points()

	assert_int(points1.size()).is_equal(points2.size())

	for i in range(points1.size()):
		assert_float(points1[i].distance_to(points2[i])).is_equal_approx(0.0, 0.0001)

	router.free()


func test_pipe_run_merged_geometry_and_material_sharing() -> void:
	var root = Spatial.new()

	var run1 = PipeRunScript.new()
	var run2 = PipeRunScript.new()

	root.add_child(run1)
	root.add_child(run2)

	var curve1 = Curve3D.new()
	curve1.add_point(Vector3(0, 0, 0))
	curve1.add_point(Vector3(0, 3, 0))
	curve1.add_point(Vector3(5, 3, 0))

	var curve2 = Curve3D.new()
	curve2.add_point(Vector3(0, 0, 0))
	curve2.add_point(Vector3(0, 3, 0))
	curve2.add_point(Vector3(0, 3, 5))

	run1.build_from_curve(curve1)
	run2.build_from_curve(curve2)

	var mesh_node1 = run1.get_node_or_null("PipeMesh") as MeshInstance
	var mesh_node2 = run2.get_node_or_null("PipeMesh") as MeshInstance

	assert_object(mesh_node1).is_not_null()
	assert_object(mesh_node2).is_not_null()

	# Verificar que ambas corridas comparten exactamente el mismo material
	assert_object(mesh_node1.material_override).is_not_null()
	assert_object(mesh_node2.material_override).is_not_null()
	assert_object(mesh_node1.material_override).is_same(mesh_node2.material_override)

	root.free()


func test_pipe_run_damage_and_leak() -> void:
	_broken_emitted = false
	var run = PipeRunScript.new()
	var curve = Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(0, 3, 0))
	curve.add_point(Vector3(4, 3, 0))

	run.build_from_curve(curve)
	run.connect("pipe_broken", self, "_on_pipe_broken_event")

	run.take_damage(10.0)

	assert_bool(run.is_broken).is_true()
	assert_bool(_broken_emitted).is_true()

	var leak = run.get_node_or_null("LeakParticles") as CPUParticles
	assert_object(leak).is_not_null()
	assert_bool(leak.emitting).is_true()

	# La malla fusionada sigue existiendo (el tramo dañado fuga pero no desaparece)
	var mesh_node = run.get_node_or_null("PipeMesh")
	assert_object(mesh_node).is_not_null()

	run.free()


func test_pipe_run_performance_20_runs() -> void:
	var root = Spatial.new()
	var runs: Array = []

	for i in range(20):
		var run = PipeRunScript.new()
		root.add_child(run)

		var curve = Curve3D.new()
		curve.add_point(Vector3(i, 0, 0))
		curve.add_point(Vector3(i, 3, 0))
		curve.add_point(Vector3(i, 3, 4))
		run.build_from_curve(curve)

		runs.append(run)

	# Cada corrida es una sola MeshInstance (1 draw call)
	for run in runs:
		var mesh_inst = run.get_node_or_null("PipeMesh") as MeshInstance
		assert_object(mesh_inst).is_not_null()

	# Todos los 20 runs comparten el mismo material
	var mat0 = (runs[0].get_node("PipeMesh") as MeshInstance).material_override
	for i in range(1, 20):
		var mat_i = (runs[i].get_node("PipeMesh") as MeshInstance).material_override
		assert_object(mat_i).is_same(mat0)

	root.free()
