extends SceneTree

# Hornea los .glb de las palancas a .mesh en espacio del prop.
#
#   godot3-bin --path . --no-window -s tools/bake_prop_models.gd
#
# industrial_electricitys_lever: base y brazo vienen fusionados en UNA malla (mas un
# Lamp y una Camera de Sketchfab que no sirven), asi que instanciar el .glb no permite
# animar nada. Son dos componentes conexas, asi que el corte es exacto y no hace falta
# partir triangulos.
#
# palanca_pedestal: son 10 MeshInstance con un unico material; se funden en una sola
# malla estatica (10 draw calls -> 2) dejando aparte el nodo de la palanca.

const LEVER_SRC := "res://assets/models/industrial_lever/industrial_electricitys_lever.glb"
const LEVER_OUT := "res://assets/models/industrial_lever/"
const PEDESTAL_SRC := "res://assets/models/palanca_pedestal/palanca_pedestal.glb"
const PEDESTAL_OUT := "res://assets/models/palanca_pedestal/"
const PEDESTAL_HANDLE := "Circle001"

func _init():
	_bake_lever()
	_bake_pedestal()
	quit()

func _bake_pedestal() -> void:
	var root = load(PEDESTAL_SRC).instance()
	var st_static := SurfaceTool.new()
	st_static.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_handle := SurfaceTool.new()
	st_handle.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material: Material = null
	var handle_found := false

	for mi in _all_meshes(root):
		var xf: Transform = _relative_transform(mi, root)
		if material == null:
			material = mi.get_surface_material(0)
			if material == null:
				material = mi.mesh.surface_get_material(0)
		var is_handle: bool = mi.name.begins_with(PEDESTAL_HANDLE) or (mi.get_parent() != null and mi.get_parent().name == PEDESTAL_HANDLE)
		if is_handle:
			handle_found = true
		_append(st_handle if is_handle else st_static, mi.mesh, xf)

	if not handle_found:
		printerr("[bake] handle node ", PEDESTAL_HANDLE, " not found")

	for pair in [["PalancaPedestalBody", st_static], ["PalancaPedestalHandle", st_handle]]:
		var st: SurfaceTool = pair[1]
		st.index()
		st.generate_tangents()
		var mesh: ArrayMesh = st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			printerr("[bake] empty mesh for ", pair[0])
			continue
		if material != null:
			mesh.surface_set_material(0, material)
		var path: String = PEDESTAL_OUT + pair[0] + ".mesh"
		var err = ResourceSaver.save(path, mesh)
		var aabb: AABB = mesh.get_aabb()
		print("[t] %s tris=%d min=%s max=%s err=%d" % [path, mesh.surface_get_array_len(0) / 3, str(aabb.position), str(aabb.end), err])

func _all_meshes(node: Node) -> Array:
	var out := []
	if node is MeshInstance:
		out.append(node)
	for c in node.get_children():
		out += _all_meshes(c)
	return out

func _append(st: SurfaceTool, mesh: Mesh, xf: Transform) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var v: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PoolVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PoolIntArray = arrays[Mesh.ARRAY_INDEX]
	for i in idx:
		if uv != null and uv.size() > i:
			st.add_uv(uv[i])
		if n != null and n.size() > i:
			st.add_normal(xf.basis.xform(n[i]).normalized())
		st.add_vertex(xf.xform(v[i]))

func _bake_lever() -> void:
	var root = load(LEVER_SRC).instance()
	var mi: MeshInstance = _find_mesh(root) as MeshInstance
	if mi == null:
		printerr("[bake] no MeshInstance in ", LEVER_SRC)
		return

	# Transform de la malla relativa a la raiz del modelo (incluye el root_scale del import).
	var xf: Transform = _relative_transform(mi, root)
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PoolIntArray = arrays[Mesh.ARRAY_INDEX]
	print("[t] source verts=", verts.size(), " indices=", indices.size())

	var groups: Array = _components(verts, indices)
	print("[t] components=", groups.size())

	var material: Material = mi.get_surface_material(0)
	if material == null:
		material = mi.mesh.surface_get_material(0)

	# La pieza mas alta (la que llega mas arriba en Y) es el brazo; la otra es la base.
	var best_top := -1e20
	var arm_idx := 0
	for i in range(groups.size()):
		var top: float = _bounds(verts, groups[i], xf)[1].y
		if top > best_top:
			best_top = top
			arm_idx = i

	for i in range(groups.size()):
		var b = _bounds(verts, groups[i], xf)
		var name = "IndustrialLeverArm" if i == arm_idx else "IndustrialLeverBase"
		var mesh: ArrayMesh = _build(arrays, groups[i], xf, material)
		var path = LEVER_OUT + name + ".mesh"
		var err = ResourceSaver.save(path, mesh)
		print("[t] %s tris=%d min=%s max=%s err=%d" % [path, groups[i].size() / 3, str(b[0]), str(b[1]), err])

func _find_mesh(node: Node) -> Node:
	if node is MeshInstance:
		return node
	for c in node.get_children():
		var r = _find_mesh(c)
		if r != null:
			return r
	return null

func _relative_transform(node: Spatial, root: Spatial) -> Transform:
	var t: Transform = Transform()
	var cur: Spatial = node
	while cur != null:
		t = cur.transform * t
		if cur == root:
			break
		cur = cur.get_parent() as Spatial
	return t

# Agrupa los triangulos por componente conexa, soldando vertices por posicion
# (el importador duplica vertices en las costuras de UV/normal).
func _components(verts: PoolVector3Array, indices: PoolIntArray) -> Array:
	var n: int = verts.size()
	# Array (no PoolIntArray): los Pool* son tipos por valor y las uniones se perderian.
	var parent := []
	parent.resize(n)
	for i in range(n):
		parent[i] = i

	var weld := {}
	for i in range(n):
		var key: String = "%.4f_%.4f_%.4f" % [verts[i].x, verts[i].y, verts[i].z]
		if weld.has(key):
			_union(parent, i, weld[key])
		else:
			weld[key] = i

	var tri_count: int = indices.size() / 3
	for t in range(tri_count):
		var a: int = indices[t * 3]
		var b: int = indices[t * 3 + 1]
		var c: int = indices[t * 3 + 2]
		_union(parent, a, b)
		_union(parent, b, c)

	var buckets := {}
	for t in range(tri_count):
		var r: int = _find(parent, indices[t * 3])
		if not buckets.has(r):
			buckets[r] = PoolIntArray()
		var tri: PoolIntArray = buckets[r]
		tri.append(indices[t * 3])
		tri.append(indices[t * 3 + 1])
		tri.append(indices[t * 3 + 2])
		buckets[r] = tri
	return buckets.values()

func _find(parent: Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x

func _union(parent: Array, a: int, b: int) -> void:
	var ra: int = _find(parent, a)
	var rb: int = _find(parent, b)
	if ra != rb:
		parent[ra] = rb

func _bounds(verts: PoolVector3Array, tri: PoolIntArray, xf: Transform) -> Array:
	var mn: Vector3 = xf.xform(verts[tri[0]])
	var mx := mn
	for i in tri:
		var v: Vector3 = xf.xform(verts[i])
		mn = Vector3(min(mn.x, v.x), min(mn.y, v.y), min(mn.z, v.z))
		mx = Vector3(max(mx.x, v.x), max(mx.y, v.y), max(mx.z, v.z))
	return [mn, mx]

func _build(arrays: Array, tri: PoolIntArray, xf: Transform, material: Material) -> ArrayMesh:
	var src_v: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_n: PoolVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var src_uv: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in tri:
		if src_uv != null and src_uv.size() > i:
			st.add_uv(src_uv[i])
		if src_n != null and src_n.size() > i:
			st.add_normal(xf.basis.xform(src_n[i]).normalized())
		st.add_vertex(xf.xform(src_v[i]))
	st.index()
	st.generate_tangents()
	var mesh: ArrayMesh = st.commit()
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh
