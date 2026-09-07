extends SceneTree

# Mide la zona de la cintura (y 380..620): densidad (y,z) en franjas X para
# ubicar el cilindro oscuro (eje de cadera) y las cajas de la pelvis.

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

	var bands := [
		{"name": "|x| 0..90", "lo": 0.0, "hi": 90.0},
		{"name": "|x| 90..160", "lo": 90.0, "hi": 160.0},
		{"name": "|x| 160..280", "lo": 160.0, "hi": 280.0},
		{"name": "|x| 280..460", "lo": 280.0, "hi": 460.0},
	]
	for b in bands:
		var rows := {}
		for t in range(ntris):
			var c := (verts[tris[t * 3]] + verts[tris[t * 3 + 1]] + verts[tris[t * 3 + 2]]) / 3.0
			var ax: float = abs(c.x)
			if ax <= b.lo or ax > b.hi:
				continue
			if c.y > 620.0 or c.y < 340.0:
				continue
			var r := int(floor((c.y - 340.0) / 20.0))
			var cc := int(floor((c.z + 340.0) / 20.0))
			var k := Vector2(r, cc)
			rows[k] = int(rows.get(k, 0)) + 1
		print("== %s (y 340..620, z -340..120) ==" % b.name)
		for r in range(14):
			var line := ""
			for cc in range(23):
				var n := int(rows.get(Vector2(r, cc), 0))
				line += " " if n == 0 else ("." if n < 4 else ("o" if n < 12 else "O"))
			print("%6.0f |%s" % [340 + r * 20.0, line])
	quit(0)

func _full(n: int) -> PoolIntArray:
	var idx := PoolIntArray()
	idx.resize(n)
	for i in range(n):
		idx[i] = i
	return idx
