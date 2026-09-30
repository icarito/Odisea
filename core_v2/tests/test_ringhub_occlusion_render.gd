extends GdUnitTestSuite

# test_ringhub_occlusion_render.gd - FD-316 (tarea HH): verificacion de la oclusion
# REAL (no mock) de RingHub con el renderer del fork.
#
# Contexto: el A/B ODISEA_OCCLUDERS=0/1 del playback del render-esclavo daba draw
# calls, vertices y objetos IDENTICOS (56 / 160k / 37 en el Anbernic), asi que se
# creyo que los occluders no cullaban. Estas pruebas miden con el renderer real
# (VisualServer.force_draw + INFO_OBJECTS_IN_FRAME) y separan las dos causas:
#
#  1. El mecanismo standalone (Occluder + OccluderShapePolygon, sin Rooms&Portals)
#     SI culla en el fork (test_occluder_culls_*).
#  2. El andamio del hub viaja como MultiMeshInstance con un AABB por SECTOR (9-13 m
#     medidos en el nivel). El culler de oclusion solo descarta una instancia cuando
#     TODO su AABB cae dentro de la silueta del occluder; un AABB del tamano del
#     sector nunca entra, asi que el andamio batcheado no se puede cullar jamon con
#     un occluder perfecto (test_multimesh_sector_aabb_is_not_rejectable).
#  3. Los occluders del hub son correctos: el anillo de piso culla lo que esta
#     debajo del anillo y respeta el atrio (test_ringhub_occluders_respect_atrium_hole).
#
# El binario headless de CI usa el rasterizer dummy: get_render_info devuelve 0 para
# todo y las pruebas de render se saltean. Correr con el renderer real:
#   ./runtest.sh --show -a ./core_v2/tests/test_ringhub_occlusion_render.gd

const OccluderScript = preload("res://core_v2/levels/RingHubOccluders.gd")

# Cuenta objetos en frame tras forzar un dibujo. Con el rasterizer dummy devuelve 0.
func _objects_in_frame() -> int:
	VisualServer.force_draw()
	return int(VisualServer.get_render_info(VisualServer.INFO_OBJECTS_IN_FRAME))


# Mundo minimo con camara propia en el origen. Los nodos usan auto_free para no
# filtrarse entre casos (el render_info es global y veria lo del caso anterior).
func _make_camera_at(pos: Vector3, pitch_deg: float) -> Camera:
	var cam := Camera.new()
	cam.fov = 75.0
	add_child(cam)
	cam.global_transform = Transform(Basis(Vector3.RIGHT, deg2rad(pitch_deg)), pos)
	cam.make_current()
	return auto_free(cam)


# Occluder con un quad centrado en `pos`.
func _make_poly_occluder(pos: Vector3, half: float) -> Occluder:
	var occ := Occluder.new()
	var shape := OccluderShapePolygon.new()
	shape.two_way = true
	shape.polygon_points = PoolVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half)])
	occ.shape = shape
	add_child(occ)
	occ.global_transform = Transform(Basis(), pos)
	return auto_free(occ)


func _make_box(pos: Vector3, size: float) -> MeshInstance:
	var mi := MeshInstance.new()
	var box := CubeMesh.new()
	box.size = Vector3(size, size, size)
	mi.mesh = box
	add_child(mi)
	mi.global_transform = Transform(Basis(), pos)
	return auto_free(mi)


func _make_multimesh(positions: Array, size: float) -> MultiMeshInstance:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := CubeMesh.new()
	box.size = Vector3(size, size, size)
	mm.mesh = box
	mm.instance_count = positions.size()
	for i in range(positions.size()):
		mm.set_instance_transform(i, Transform(Basis(), positions[i]))
	var mmi := MultiMeshInstance.new()
	mmi.multimesh = mm
	add_child(mmi)
	return auto_free(mmi)


# 1. El mecanismo base: un MeshInstance detras de un poligono deja de contarse.
func test_occluder_culls_mesh_instance_behind():
	_make_camera_at(Vector3.ZERO, 0.0)
	_make_box(Vector3(0, 0, -10), 1.0)
	var occ := _make_poly_occluder(Vector3(0, 0, -5), 2.0)
	for _i in range(2):
		yield(get_tree(), "idle_frame")

	var con := _objects_in_frame()
	occ.visible = false
	for _i in range(2):
		yield(get_tree(), "idle_frame")
	var without_occ := _objects_in_frame()

	if without_occ <= 0:
		return # rasterizer dummy (CI headless)
	assert_int(con).is_less(without_occ)


# 2. Un MultiMeshInstance SI se culla cuando su AABB completo entra en la silueta.
func test_occluder_culls_multimesh_when_aabb_fits():
	_make_camera_at(Vector3.ZERO, 0.0)
	_make_multimesh([Vector3(-1.5, 0, -10), Vector3(0, 0, -10), Vector3(1.5, 0, -10)], 1.0)
	var occ := _make_poly_occluder(Vector3(0, 0, -5), 4.0)
	for _i in range(2):
		yield(get_tree(), "idle_frame")

	var con := _objects_in_frame()
	occ.visible = false
	for _i in range(2):
		yield(get_tree(), "idle_frame")
	var without_occ := _objects_in_frame()

	if without_occ <= 0:
		return
	assert_int(con).is_less(without_occ)


# 3. Causa real del A/B plano: el andamio va batcheado en MultiMeshInstances con un
#    AABB por SECTOR (todo el ancho de la instancia, 9-13 m en RingHub). El culler
#    descarta una instancia solo si TODO su AABB cae dentro de la silueta, asi que un
#    sector de ese ancho nunca se puede rechazar. Control positivo: un cubo chico en
#    el mismo plano SI se culla, aunque los dos esten detras del mismo poligono.
func test_multimesh_sector_aabb_is_not_rejectable():
	_make_camera_at(Vector3.ZERO, 0.0)
	# Sector ancho (AABB ~30 m): no entra en la silueta de un occluder razonable.
	_make_multimesh([Vector3(-15, 0, -10), Vector3(0, 0, -10), Vector3(15, 0, -10)], 1.0)
	# Cubo chico en el centro de la vista, mismo plano que el sector.
	_make_box(Vector3(0, 0, -10), 1.0)
	var occ := _make_poly_occluder(Vector3(0, 0, -5), 3.0)
	for _i in range(2):
		yield(get_tree(), "idle_frame")

	var con := _objects_in_frame()
	occ.visible = false
	for _i in range(2):
		yield(get_tree(), "idle_frame")
	var without_occ := _objects_in_frame()

	if without_occ <= 0:
		return
	# Solo el cubo chico se culla; el sector ancho sobrevive al occluder.
	assert_int(without_occ - con).is_equal(1)


# 4. Los occluders del hub son geometricamente correctos: el anillo de piso de un
#    piso culla un objetivo que esta debajo del ANILLO (r entre inner y outer) y no
#    culla uno que esta debajo del ATRIO (r < inner_radius). Fija el radio del
#    agujero y la altura de los pisos que el playback del Anbernic ejercita.
func test_ringhub_occluders_respect_atrium_hole():
	var prev := OS.get_environment(OccluderScript.OCCLUDERS_ENV)
	OS.set_environment(OccluderScript.OCCLUDERS_ENV, "1")
	var occluders = auto_free(OccluderScript.new())
	add_child(occluders)
	assert_int(occluders.occluder_count()).is_equal(9)

	# Camara arriba, mirando hacia abajo por el atrio.
	_make_camera_at(Vector3(0, 14, 6), -90.0)
	# Debajo del anillo (r=9 -> entre 6 y 13) y debajo del atrio (r=3 -> < 6).
	_make_box(Vector3(0, 0, 9), 1.0)
	_make_box(Vector3(0, 0, 3), 1.0)
	for _i in range(2):
		yield(get_tree(), "idle_frame")

	var con := _objects_in_frame()
	occluders.visible = false
	for _i in range(2):
		yield(get_tree(), "idle_frame")
	var without_occ := _objects_in_frame()

	if without_occ <= 0:
		return
	# Solo el objetivo debajo del anillo desaparece; el del atrio queda visible.
	assert_int(without_occ - con).is_equal(1)
	OS.set_environment(OccluderScript.OCCLUDERS_ENV, prev)