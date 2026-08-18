extends GdUnitTestSuite

# test_tube_builder.gd — TestSuite para la primitiva TubeBuilder (FD-267).

const TubeBuilderScript = preload("res://core_v2/systems/pipe/TubeBuilder.gd")


func test_straight_tube_mesh_generation() -> void:
	var curve = Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(0, 5, 0))

	var radius = 0.1
	var sides = 8
	var mesh = TubeBuilderScript.generate_tube_mesh(curve, radius, sides, false)

	assert_object(mesh).is_not_null()
	assert_int(mesh.get_surface_count()).is_equal(1)

	var mdt = MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)

	assert_bool(mdt.get_vertex_count() > 0).is_true()
	assert_bool(mdt.get_face_count() > 0).is_true()

	for i in range(mdt.get_vertex_count()):
		var norm = mdt.get_vertex_normal(i)
		assert_float(norm.length()).is_equal_approx(1.0, 0.01)


func test_90_degree_corner_tube_geometry_and_bounded_surface_area() -> void:
	var curve = Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(0, 3, 0))
	curve.add_point(Vector3(3, 3, 0))

	var radius = 0.05
	var sides = 8
	var mesh = TubeBuilderScript.generate_tube_mesh(curve, radius, sides, false)

	assert_object(mesh).is_not_null()

	var mdt = MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)

	var total_area = 0.0
	for f in range(mdt.get_face_count()):
		var v0 = mdt.get_vertex(mdt.get_face_vertex(f, 0))
		var v1 = mdt.get_vertex(mdt.get_face_vertex(f, 1))
		var v2 = mdt.get_vertex(mdt.get_face_vertex(f, 2))

		var face_normal = (v1 - v0).cross(v2 - v0)
		var tri_area = face_normal.length() * 0.5
		assert_bool(tri_area > 0.000001).is_true() # Sin triángulos colapsados ni degenerados
		total_area += tri_area

	# Área teórica de un cilindro de largo 6m y radio 0.05m: 2 * PI * r * h ≈ 1.885 m²
	var theoretical_area = 2.0 * PI * radius * 6.0
	# El área calculada debe estar cerca del valor teórico y no abrirse en abanico
	assert_bool(total_area < theoretical_area * 1.5).is_true()
	assert_bool(total_area > theoretical_area * 0.7).is_true()


func test_tube_builder_determinism() -> void:
	var curve = Curve3D.new()
	curve.add_point(Vector3(1.5, 0.0, -2.0))
	curve.add_point(Vector3(1.5, 4.0, -2.0))
	curve.add_point(Vector3(-3.0, 4.0, 5.0))

	var mesh1 = TubeBuilderScript.generate_tube_mesh(curve, 0.08, 8, true)
	var mesh2 = TubeBuilderScript.generate_tube_mesh(curve, 0.08, 8, true)

	assert_object(mesh1).is_not_null()
	assert_object(mesh2).is_not_null()

	var mdt1 = MeshDataTool.new()
	mdt1.create_from_surface(mesh1, 0)

	var mdt2 = MeshDataTool.new()
	mdt2.create_from_surface(mesh2, 0)

	assert_int(mdt1.get_vertex_count()).is_equal(mdt2.get_vertex_count())
	assert_int(mdt1.get_face_count()).is_equal(mdt2.get_face_count())

	# Comprobar reproducción bit a bit
	for i in range(mdt1.get_vertex_count()):
		assert_vector3(mdt1.get_vertex(i)).is_equal(mdt2.get_vertex(i))
		assert_vector3(mdt1.get_vertex_normal(i)).is_equal(mdt2.get_vertex_normal(i))
		assert_vector2(mdt1.get_vertex_uv(i)).is_equal(mdt2.get_vertex_uv(i))
