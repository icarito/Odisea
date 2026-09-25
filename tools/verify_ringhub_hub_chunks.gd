extends SceneTree

# verify_ringhub_hub_chunks.gd — verifica el producto de `make bake-ringhub-hub`
# tal como lo consume RingHub_Level.tscn.
#
# El objetivo del split en tercios es que el frustum pueda descartar AABBs por
# separado: el hub conserva MeshInstance (BakedLightmap no cubre MultiMesh) pero
# cada piso son tres mallas con AABB propio en vez de una sola que abarca los 360
# grados. Este verificador falla si el nivel vuelve a una malla por piso, si un
# tercio pierde use_in_baked_light/UV2, si los tercios dejan de repartir la
# geometria, o si la colision por piso deja de ser una sola.
#
# No agrega la escena al arbol: no dispara _ready ni depende de autoloads.
#
# Uso: tools/godot --path . --no-window -s tools/verify_ringhub_hub_chunks.gd
# Exit code != 0 si algo falla.

const LEVEL := "res://core_v2/levels/RingHub_Level.tscn"
# Nombre del nodo por tercio. El tercio 0 conserva el nombre historico
# "CombinedMesh" para no invalidar a los consumidores que ya lo buscan.
const CHUNK_NODES := ["CombinedMesh", "CombinedMesh_Third_1", "CombinedMesh_Third_2"]
# RingFloor es el piso 1; los otros cuatro son Floor_2..5.
const FLOORS := ["RingFloor", "Floor_2", "Floor_3", "Floor_4", "Floor_5"]
# Cada tercio deberia tener cerca de un tercio de los vertices. Los huecos y los
# sectores salteados de cada piso lo desbalancean, pero no deberia alejarse de
# esto sin que el split haya dejado de partir por angulo.
const CHUNK_VERTEX_TOLERANCE := 0.25

var _failures := []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		push_error("[verify_hub_chunks] no pude cargar %s" % LEVEL)
		quit(1)
		return
	var root: Node = packed.instance()

	for floor_name in FLOORS:
		_check_floor(root, floor_name)

	if _failures.empty():
		print("[verify_hub_chunks] PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("[verify_hub_chunks] %s" % failure)
	quit(1)


func _check_floor(root: Node, floor_name: String) -> void:
	var floor_node: Node = root.get_node_or_null("Hub/" + floor_name)
	if floor_node == null:
		_fail("falta Hub/%s" % floor_name)
		return

	var chunk_aabbs := []
	var chunk_verts := []
	var union_aabb := AABB()
	var have_union := false
	var total_verts := 0
	for chunk_name in CHUNK_NODES:
		var node: MeshInstance = floor_node.get_node_or_null(chunk_name)
		if node == null:
			_fail("%s/%s no existe" % [floor_name, chunk_name])
			return
		if node.mesh == null:
			_fail("%s/%s sin mesh" % [floor_name, chunk_name])
			return
		if node.mesh.resource_path.empty() or not ResourceLoader.exists(node.mesh.resource_path):
			_fail("%s/%s apunta a un .mesh inexistente: %s" % [
				floor_name, chunk_name, node.mesh.resource_path])
		if not node.use_in_baked_light:
			_fail("%s/%s sin use_in_baked_light" % [floor_name, chunk_name])
		# Sin UV2 el BakedLightmap ignora la superficie.
		var missing_uv2 := 0
		for surface_index in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(surface_index)
			if arrays.size() <= Mesh.ARRAY_TEX_UV2 or arrays[Mesh.ARRAY_TEX_UV2] == null \
					or arrays[Mesh.ARRAY_TEX_UV2].size() == 0:
				missing_uv2 += 1
		if missing_uv2 > 0:
			_fail("%s/%s tiene %d/%d surfaces sin UV2" % [
				floor_name, chunk_name, missing_uv2, node.mesh.get_surface_count()])

		var aabb: AABB = node.mesh.get_aabb()
		if aabb.size.x <= 0.0 or aabb.size.y <= 0.0 or aabb.size.z <= 0.0:
			_fail("%s/%s tiene AABB degenerado %s" % [floor_name, chunk_name, str(aabb.size)])
		chunk_aabbs.append(aabb)
		chunk_verts.append(_vertex_count(node.mesh))
		total_verts += chunk_verts[chunk_verts.size() - 1]
		if have_union:
			union_aabb = union_aabb.merge(aabb)
		else:
			union_aabb = aabb
			have_union = true

	# Cada tercio tiene su AABB: si los tres comparten el AABB del anillo entero,
	# el frustum no puede descartar ninguno y el split no aporta nada.
	var descartables := 0
	for aabb in chunk_aabbs:
		if aabb.size.x < union_aabb.size.x * 0.999 or aabb.size.z < union_aabb.size.z * 0.999:
			descartables += 1
	if descartables < CHUNK_NODES.size():
		_fail("%s: solo %d/%d tercios tienen AABB propio" % [
			floor_name, descartables, CHUNK_NODES.size()])

	if total_verts > 0:
		for i in range(chunk_verts.size()):
			var ratio: float = float(chunk_verts[i]) / float(total_verts)
			var expected: float = 1.0 / float(CHUNK_NODES.size())
			if abs(ratio - expected) > CHUNK_VERTEX_TOLERANCE:
				_fail("%s/%s tiene %d/%d verts (%.2f, esperado ~%.2f)" % [
					floor_name, CHUNK_NODES[i], chunk_verts[i], total_verts, ratio, expected])
	else:
		_fail("%s: 0 vertices en los tercios" % floor_name)

	# Una sola colision por piso y su AABB coincide con la union visual.
	var body: StaticBody = floor_node.get_node_or_null("StaticBody") as StaticBody
	if body == null:
		_fail("%s sin StaticBody" % floor_name)
		return
	var shapes := []
	for child in body.get_children():
		if child is CollisionShape:
			shapes.append(child)
	if shapes.size() != 1:
		_fail("%s tiene %d CollisionShape (esperado 1)" % [floor_name, shapes.size()])
		return
	var shape: Shape = (shapes[0] as CollisionShape).shape
	if shape == null:
		_fail("%s/StaticBody/CombinedCollision sin shape" % floor_name)
		return
	if shape is ConcavePolygonShape:
		var faces: PoolVector3Array = (shape as ConcavePolygonShape).get_faces()
		if faces.empty():
			_fail("%s: colision vacia" % floor_name)
	else:
		_fail("%s: la colision no es ConcavePolygonShape" % floor_name)
	var shape_aabb: AABB = shape.get_debug_mesh().get_aabb()
	# La colision incluye el parapeto (mas alto que la baranda visual) y excluye
	# la franja hazard, asi que no es identica: se compara XZ contra el visual.
	var slack := 0.35
	if abs(shape_aabb.size.x - union_aabb.size.x) > slack \
			or abs(shape_aabb.size.z - union_aabb.size.z) > slack:
		_fail("%s: colision XZ %s no coincide con visual XZ %s" % [
			floor_name, str(shape_aabb.size), str(union_aabb.size)])
	if abs(shape_aabb.position.x - union_aabb.position.x) > slack \
			or abs(shape_aabb.position.z - union_aabb.position.z) > slack:
		_fail("%s: colision XZ no esta alineada con el visual" % floor_name)

	print("[verify_hub_chunks] %-9s verts=%s AABB=%s colision_faces=%d" % [
		floor_name, str(chunk_verts), str(union_aabb.size),
		(shape as ConcavePolygonShape).get_faces().size() / 3])


func _vertex_count(mesh: ArrayMesh) -> int:
	var total := 0
	for surface_index in range(mesh.get_surface_count()):
		total += mesh.surface_get_array_len(surface_index)
	return total


func _fail(message: String) -> void:
	_failures.append(message)
