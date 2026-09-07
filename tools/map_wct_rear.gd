extends SceneTree

# Mide la zona trasera del hub (z < -240, |x| <= 90): densidad (y,z) de tris
# para separar el cilindro trasero del hub block.

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

	var rows := {}
	for t in range(ntris):
		var c := (verts[tris[t * 3]] + verts[tris[t * 3 + 1]] + verts[tris[t * 3 + 2]]) / 3.0
		if abs(c.x) > 90.0 or c.z > -140.0 or c.z < -460.0 or c.y > 520.0 or c.y < 100.0:
			continue
		var r := int(floor((c.y - 100.0) / 20.0))
		var cc := int(floor((c.z + 460.0) / 20.0))
		var k := Vector2(r, cc)
		rows[k] = int(rows.get(k, 0)) + 1
	print("== zona trasera |x|<=90, filas y 100..520 paso 20, cols z -460..-140 paso 20 ==")
	for r in range(21):
		var line := ""
		for cc in range(16):
			var n := int(rows.get(Vector2(r, cc), 0))
			line += " " if n == 0 else ("." if n < 4 else ("o" if n < 12 else "O"))
		print("%6.0f |%s" % [100 + r * 20.0, line])
	quit(0)

func _full(n: int) -> PoolIntArray:
	var idx := PoolIntArray()
	idx.resize(n)
	for i in range(n):
		idx[i] = i
	return idx
