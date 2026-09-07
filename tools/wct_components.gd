extends SceneTree

# Componentes conexas del mesh por adyacencia de vertices: bbox, tris y
# centroide de cada pieza. Identifica las partes reales del modelo.

var _parent := PoolIntArray()

func _uf_find(a: int) -> int:
	while _parent[a] != a:
		_parent[a] = _parent[_parent[a]]
		a = _parent[a]
	return a

func _uf_union(a: int, b: int) -> void:
	var ra := _uf_find(a)
	var rb := _uf_find(b)
	if ra != rb:
		_parent[rb] = ra

func _init() -> void:
	var packed: PackedScene = load("res://core_v2/props/machinery/walking_cargo_transporter.tscn")
	var root: Node = packed.instance()
	var mi: MeshInstance = null
	var stack := [root]
	while not stack.empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance:
			mi = n
			break
		for c in n.get_children():
			stack.push_back(c)
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PoolIntArray = arrays[Mesh.ARRAY_INDEX]
	var tris := indices if not indices.empty() else _full(verts.size())
	var ntris := tris.size() / 3
	var nv := verts.size()

	# union-find sobre vertices
	var parent: PoolIntArray = PoolIntArray()
	parent.resize(nv)
	for i in range(nv):
		parent[i] = i
	_parent = parent

	for t in range(ntris):
		_uf_union(tris[t * 3], tris[t * 3 + 1])
		_uf_union(tris[t * 3 + 1], tris[t * 3 + 2])

	var comps := {}
	for v in range(nv):
		var r := _uf_find(v)
		if not comps.has(r):
			comps[r] = {"n": 0, "lo": verts[v], "hi": verts[v]}
		var c: Dictionary = comps[r]
		c.n += 1
		c.lo = Vector3(min(c.lo.x, verts[v].x), min(c.lo.y, verts[v].y), min(c.lo.z, verts[v].z))
		c.hi = Vector3(max(c.hi.x, verts[v].x), max(c.hi.y, verts[v].y), max(c.hi.z, verts[v].z))

	var list := comps.values()
	list.sort_custom(self, "_by_n")
	print("componentes: %d" % list.size())
	for c in list:
		if c.n < 12:
			continue
		var size: Vector3 = c.hi - c.lo
		var ctr: Vector3 = (c.hi + c.lo) / 2.0
		# candidatas a mal clasificadas: body en zona de piernas
		var leg_zone: bool = ctr.y < 250.0 or (ctr.y < 560.0 and size.y < 120.0 and size.x > 400.0)
		if not leg_zone:
			continue
		print("ZONA-PIERNA n=%5d bbox=(%.0f..%.0f, %.0f..%.0f, %.0f..%.0f) centro=(%.0f, %.0f, %.0f)" % [
			c.n, c.lo.x, c.hi.x, c.lo.y, c.hi.y, c.lo.z, c.hi.z, ctr.x, ctr.y, ctr.z])
	quit(0)

func _by_n(a: Dictionary, b: Dictionary) -> bool:
	return a.n > b.n

func _full(n: int) -> PoolIntArray:
	var idx := PoolIntArray()
	idx.resize(n)
	for i in range(n):
		idx[i] = i
	return idx
