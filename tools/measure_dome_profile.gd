extends SceneTree

# measure_dome_profile.gd — Silueta interior de la cúpula, para el `dome_profile` de IceLevel.
#
# La superficie de hielo (IceLevel/IceSurface) es un plano que el shader recorta contra un
# radio. Ese radio tiene que ser el de la PARED a la altura del hielo: la cúpula no es un
# cilindro, se cierra desde y≈6.7 hacia el óculo, así que un radio fijo o deja un anillo de
# piso descubierto abajo, o asoma fuera del domo arriba.
#
# Método: rayos horizontales desde el eje del domo hacia afuera. El primer impacto es la
# cara INTERNA de la pared; el mayor de todos los ángulos es el radio que el disco necesita
# para tapar el piso en todas las direcciones (la pared es un polígono, sus esquinas quedan
# más lejos que sus caras). Los rayos que no impactan son los cuatro vanos de los airlocks.
#
# Run:    godot3-bin --no-window -s tools/measure_dome_profile.gd
# Output: por consola, la tabla lista para pegar en IceLevel.dome_profile.
#
# Contra el valor crudo se suma MARGIN para enterrar el borde del disco en el espesor de la
# pared (~0.7 m). No subirlo mucho más: pasado el espesor, el hielo asoma por fuera.

const WALL_MESH := "res://core_v2/levels/interiors/DomeTerrace_baked.mesh"
# Surface 0 = la cúpula (shader dome_wall_cylindrical). Las otras son piso y explanada.
const WALL_SURFACE := 0
const RAYS := 128
const HEIGHT_STEP := 1.0
const MAX_HEIGHT := 31.0
const MARGIN := 0.1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var mesh: Mesh = load(WALL_MESH)
	if mesh == null or mesh.get_surface_count() <= WALL_SURFACE:
		push_error("No se pudo cargar la pared en %s" % WALL_MESH)
		quit(1)
		return

	var triangles := _surface_triangles(mesh, WALL_SURFACE)
	print("[dome_profile] triángulos de pared=%d" % (triangles.size() / 3))

	var samples := []
	var height := 0.0
	while height <= MAX_HEIGHT:
		var measured := _inner_radius_at(triangles, height)
		if measured["hits"] > 0:
			samples.append(Vector2(height, measured["max"]))
			print("[dome_profile] y=%5.1f cara_interna=%.2f..%.2f vanos=%d" % [
				height, measured["min"], measured["max"], RAYS - int(measured["hits"])])
		height += HEIGHT_STEP

	_print_table(samples)
	quit(0)

# Radio de la cara interna a una altura: mínimo y máximo sobre todos los ángulos.
func _inner_radius_at(triangles: PoolVector3Array, height: float) -> Dictionary:
	var origin := Vector3(0.0, height, 0.0)
	var smallest := 1e9
	var largest := -1e9
	var hits := 0
	for i in range(RAYS):
		var angle: float = TAU * float(i) / float(RAYS)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var nearest := 1e9
		var t := 0
		while t < triangles.size():
			var hit = Geometry.ray_intersects_triangle(origin, direction, triangles[t], triangles[t + 1], triangles[t + 2])
			t += 3
			if hit == null:
				continue
			nearest = min(nearest, Vector2(hit.x, hit.z).length())
		if nearest > 1e8:
			continue
		hits += 1
		smallest = min(smallest, nearest)
		largest = max(largest, nearest)
	return {"min": smallest, "max": largest, "hits": hits}

# La cúpula es recta a tramos: se queda solo con los quiebres reales, así la tabla es
# corta y la interpolación lineal sigue siendo exacta.
func _print_table(samples: Array) -> void:
	var kept := _simplify(samples, 0.02)
	var table := ""
	for point in kept:
		table += "\tVector2(%s, %s),\n" % [stepify(point.x, 0.05), stepify(point.y + MARGIN, 0.01)]
	print("[dome_profile] puntos=%d (de %d muestras), margen=+%.2f" % [kept.size(), samples.size(), MARGIN])
	print("[dome_profile] tabla para IceLevel.dome_profile:\n" + table)

# Douglas-Peucker sobre la curva (altura, radio).
func _simplify(points: Array, tolerance: float) -> Array:
	if points.size() < 3:
		return points
	var first: Vector2 = points[0]
	var last: Vector2 = points[points.size() - 1]
	var worst := 0.0
	var worst_index := 0
	for i in range(1, points.size() - 1):
		var distance := _distance_to_segment(points[i], first, last)
		if distance > worst:
			worst = distance
			worst_index = i
	if worst <= tolerance:
		return [first, last]
	var head: Array = _simplify(points.slice(0, worst_index), tolerance)
	var tail: Array = _simplify(points.slice(worst_index, points.size() - 1), tolerance)
	head.remove(head.size() - 1)
	return head + tail

func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var span: Vector2 = to - from
	if span.length_squared() <= 0.0:
		return point.distance_to(from)
	var t: float = clamp((point - from).dot(span) / span.length_squared(), 0.0, 1.0)
	return point.distance_to(from + span * t)

func _surface_triangles(mesh: Mesh, surface: int) -> PoolVector3Array:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PoolIntArray = arrays[Mesh.ARRAY_INDEX]
	var out := PoolVector3Array()
	var i := 0
	while i < indices.size():
		out.append(verts[indices[i]])
		out.append(verts[indices[i + 1]])
		out.append(verts[indices[i + 2]])
		i += 3
	return out
