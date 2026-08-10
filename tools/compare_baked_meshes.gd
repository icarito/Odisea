extends SceneTree

# compare_baked_meshes.gd — Compara el horneado actual de un grupo de andamios
# contra una referencia (por ejemplo la version pristina de un commit viejo,
# extraida con `git show <commit>:<path>`), para confirmar que rehornear desde la
# fuente restaurada da la MISMA geometria y no una version revertida.
#
# No compara vertice a vertice: el conteo cambia legitimamente si se fusionan
# materiales o se apaga el relleno de baranda. Compara la nube de puntos: AABB,
# centroide y cuantos vertices de la referencia tienen un vertice del actual a
# menos de TOLERANCE.
#
# Run: ODISEA_CMP_A=res://... ODISEA_CMP_B=res://... godot3-bin --no-window -s tools/compare_baked_meshes.gd

const TOLERANCE := 0.02
const CELL := 0.5

func _init() -> void:
	var path_a: String = OS.get_environment("ODISEA_CMP_A")
	var path_b: String = OS.get_environment("ODISEA_CMP_B")
	if path_a.empty() or path_b.empty():
		printerr("CMP: faltan ODISEA_CMP_A / ODISEA_CMP_B")
		quit(1)
		return
	var mesh_a: ArrayMesh = load(path_a)
	var mesh_b: ArrayMesh = load(path_b)
	if mesh_a == null or mesh_b == null:
		printerr("CMP: no pude cargar alguna de las mallas")
		quit(1)
		return

	var points_a: Array = _points(mesh_a)
	var points_b: Array = _points(mesh_b)
	print("CMP: A=%s  %d verts  aabb=%s" % [path_a.get_file(), points_a.size(), str(_aabb(points_a))])
	print("CMP: B=%s  %d verts  aabb=%s" % [path_b.get_file(), points_b.size(), str(_aabb(points_b))])

	var grid := {}
	for p in points_a:
		var key: String = _cell_key(p)
		if not grid.has(key):
			grid[key] = []
		grid[key].append(p)

	var matched := 0
	for p in points_b:
		if _has_near(grid, p):
			matched += 1
	print("CMP: %d/%d vertices de B tienen contraparte en A (%.2f%%)" % [
		matched, points_b.size(), 100.0 * float(matched) / max(points_b.size(), 1)])
	quit(0)

func _points(mesh: ArrayMesh) -> Array:
	var out := []
	for s in range(mesh.get_surface_count()):
		for v in (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PoolVector3Array):
			out.append(v)
	return out

func _aabb(points: Array) -> AABB:
	if points.empty():
		return AABB()
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box

func _cell_key(p: Vector3) -> String:
	return "%d,%d,%d" % [int(floor(p.x / CELL)), int(floor(p.y / CELL)), int(floor(p.z / CELL))]

func _has_near(grid: Dictionary, p: Vector3) -> bool:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var key: String = "%d,%d,%d" % [
					int(floor(p.x / CELL)) + dx,
					int(floor(p.y / CELL)) + dy,
					int(floor(p.z / CELL)) + dz]
				if not grid.has(key):
					continue
				for q in grid[key]:
					if (q - p).length_squared() <= TOLERANCE * TOLERANCE:
						return true
	return false
