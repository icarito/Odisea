extends SceneTree

# bake_ring_collider_primitives.gd — Reemplaza un ConcavePolygonShape (trimesh) de un
# anillo/plataforma octogonal (piso + baranda interior/exterior + patas de soporte,
# el patron "CombinedMesh/CombinedCollision" que arma ScaffoldHubRing) por un puñado
# de shapes primitivos (ConvexPolygonShape por segmento + BoxShape por pata).
#
# Origen: FD perf Anbernic 2026-09-20. El collider del piso de RingHub_Level (3786
# triangulos, "Hub/RingFloor/StaticBody/CombinedCollision") medido contra 32 piezas
# primitivas dio el MISMO costo de fisica por frame en el dispositivo (Box3D ya
# resuelve el BVH del trimesh razonablemente bien) — la ganancia real es tamaño de
# escena/carga (.tscn ~20% mas chico), no ms_physics por frame. Se documenta y se
# generaliza igual porque Dome_Intro (ScaffoldHubRing, ver bake_dome_intro_hub_floors.gd)
# usa la MISMA geometria de anillo en 5 pisos.
#
# Algoritmo (ver detalle abajo):
#   1. Cargar la escena fuente, ubicar el CollisionShape con el ConcavePolygonShape.
#   2. Clasificar sus vertices en bandas de Y (piso / baranda / patas) por umbrales
#      explicitos — un gap de Y no alcanza para distinguirlas solo (la baranda tiene
#      DOS barras con un hueco del mismo tamaño que el hueco piso->baranda), asi que
#      los umbrales son parametros, no auto-deteccion.
#   3. Agrupar por angulo en N sectores (regular, 360/N grados) y quedarse con el
#      vertice de radio maximo/minimo por sector -> esquinas exteriores/interiores.
#   4. Piso: N prismas trapezoidales (ConvexPolygonShape, 8 puntos c/u) entre esquina
#      interior y exterior consecutivas.
#   5. Baranda: 2*N paredes delgadas (ConvexPolygonShape) seccion by seccion, interior
#      y exterior, con un espesor radial fijo (las paredes de origen son laminas).
#   6. Patas: se detectan como los mismos N vertices de esquina exterior pero tomados
#      de la banda MAS BAJA (fuera del rango piso/baranda); se generan como BoxShape
#      cuadrado centrado en cada esquina, del Y de esa banda hasta el Y de arranque
#      del piso.
#   7. Splice de TEXTO en el .tscn destino (nunca PackedScene.pack() sobre la escena
#      completa: eso ya corrompio nodos en este repo, ver AGENTS.md / memoria del
#      proyecto). Reemplaza el bloque `[sub_resource ... id=OLD_ID]` del shape viejo y
#      el `[node ... CollisionShape]` que lo usa por los N*2+N nuevos, y borra
#      cualquier `__meta__` que apuntara al shape viejo (cache de ShapeBounds).
#
# Uso:
#   ODISEA_BAKE_SCENE=res://core_v2/levels/RingHub_Level.tscn \
#   ODISEA_BAKE_BODY=Hub/RingFloor/StaticBody \
#   ODISEA_BAKE_OLD_NODE=CombinedCollision \
#   ODISEA_BAKE_SEGMENTS=8 \
#   ODISEA_BAKE_FLOOR_Y=0.05,0.35 \
#   ODISEA_BAKE_RAIL_Y=0.5,1.5 \
#   ODISEA_BAKE_RAIL_THICKNESS=0.06 \
#   ODISEA_BAKE_LEG_Y_BELOW=0.05 \
#   ODISEA_BAKE_LEG_HALF=0.10 \
#   ODISEA_BAKE_DRY_RUN=1 \
#   tools/godot --no-window -s tools/bake_ring_collider_primitives.gd
#
# ODISEA_BAKE_DRY_RUN=1 imprime el resultado (conteo de piezas, bounding box) sin
# escribir el archivo — usarlo primero para revisar antes de aplicar de verdad.
# Sin DRY_RUN escribe directo sobre ODISEA_BAKE_SCENE; revisar con git diff/screenshot
# antes de commitear (ver docs/handoff/anbernic-lowend/plan.md, seccion RingHub_Level).


func _init() -> void:
	var scene_path := _env("ODISEA_BAKE_SCENE", "")
	var body_path := _env("ODISEA_BAKE_BODY", "")
	var old_node_name := _env("ODISEA_BAKE_OLD_NODE", "CombinedCollision")
	if scene_path == "" or body_path == "":
		printerr("[bake_ring] faltan ODISEA_BAKE_SCENE / ODISEA_BAKE_BODY")
		quit(1)
		return

	var segments := int(_env("ODISEA_BAKE_SEGMENTS", "8"))
	var floor_y := _parse_range(_env("ODISEA_BAKE_FLOOR_Y", "0.05,0.35"))
	var rail_y := _parse_range(_env("ODISEA_BAKE_RAIL_Y", "0.5,1.5"))
	var rail_thickness := float(_env("ODISEA_BAKE_RAIL_THICKNESS", "0.06"))
	var leg_y_below := float(_env("ODISEA_BAKE_LEG_Y_BELOW", "0.05"))
	var leg_half := float(_env("ODISEA_BAKE_LEG_HALF", "0.10"))
	var dry_run := _env("ODISEA_BAKE_DRY_RUN", "") != ""

	var scene: Node = load(scene_path).instance()
	var body: Node = scene.get_node_or_null(body_path)
	if body == null:
		printerr("[bake_ring] no encuentro el nodo ", body_path)
		quit(1)
		return
	var old_cs: CollisionShape = body.get_node_or_null(old_node_name)
	if old_cs == null or not (old_cs.shape is ConcavePolygonShape):
		printerr("[bake_ring] ", old_node_name, " no tiene un ConcavePolygonShape")
		quit(1)
		return

	var faces: PoolVector3Array = (old_cs.shape as ConcavePolygonShape).get_faces()
	var verts := _unique_verts(faces)
	print("[bake_ring] vertices unicos: ", verts.size())

	var floor_verts := _band(verts, floor_y.x, floor_y.y)
	var rail_verts := _band(verts, rail_y.x, rail_y.y)
	var leg_verts := []
	for v in verts:
		if v.y < leg_y_below:
			leg_verts.append(v)

	var outer := _corners(floor_verts, segments, true)
	var inner := _corners(floor_verts, segments, false)
	var leg_outer := _corners(leg_verts, segments, true)

	# Extents Y reales observados dentro de cada banda, no el umbral de clasificacion
	# tal cual (mas ancho a proposito, para no perderse vertices por poco) — asi la
	# pieza generada abraza la geometria real en vez de la ventana de busqueda.
	var floor_y_tight := _y_extent(floor_verts, floor_y)
	var rail_y_tight := _y_extent(rail_verts, rail_y)

	if outer.size() < segments or inner.size() < segments:
		printerr("[bake_ring] no se pudieron derivar las ", segments, " esquinas del piso (outer=",
			outer.size(), " inner=", inner.size(), "). Revisar ODISEA_BAKE_FLOOR_Y.")
		quit(1)
		return

	var pieces := _build_pieces(segments, outer, inner, floor_y_tight, rail_y_tight, rail_thickness,
		leg_outer, leg_verts, leg_half, floor_y.x)

	print("[bake_ring] piezas generadas: ", pieces.size(), " (", segments, " piso + ",
		segments * 2, " baranda + ", leg_outer.size(), " patas)")

	if dry_run:
		var mn := Vector3(INF, INF, INF)
		var mx := Vector3(-INF, -INF, -INF)
		for p in pieces:
			var corners = p.points if p.kind == "convex" else [p.points[0] - p.points[1], p.points[0] + p.points[1]]
			for pt in corners:
				mn.x = min(mn.x, pt.x); mn.y = min(mn.y, pt.y); mn.z = min(mn.z, pt.z)
				mx.x = max(mx.x, pt.x); mx.y = max(mx.y, pt.y); mx.z = max(mx.z, pt.z)
		print("[bake_ring] DRY RUN — bounding box: min=", mn, " max=", mx)
		print("[bake_ring] (comparar contra el AABB del mesh original antes de aplicar)")
		quit(0)
		return

	var ok := _splice_into_file(scene_path, old_cs, pieces, body_path)
	quit(0 if ok else 1)


# --- utilidades ---

func _env(key: String, default_value: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else default_value

func _parse_range(s: String) -> Vector2:
	var parts := s.split(",")
	return Vector2(float(parts[0]), float(parts[1]))

func _unique_verts(faces: PoolVector3Array) -> Array:
	var seen := {}
	for v in faces:
		var key := "%.4f,%.4f,%.4f" % [v.x, v.y, v.z]
		seen[key] = v
	return seen.values()

func _band(verts: Array, y0: float, y1: float) -> Array:
	var out := []
	for v in verts:
		if v.y > y0 and v.y < y1:
			out.append(v)
	return out

func _angle_bin(v: Vector3, segments: int) -> int:
	var a := rad2deg(atan2(v.z, v.x))
	if a < 0:
		a += 360.0
	var step := 360.0 / segments
	return int(round(a / step)) % segments

# Por cada sector angular, el vertice de radio maximo (want_max=true, esquina
# exterior) o minimo (want_max=false, esquina interior). Devuelve un Diccionario
# sector -> Vector2(x,z); si algun sector no tiene vertices, queda ausente (el
# llamador debe validar el tamaño resultante).
func _corners(verts: Array, segments: int, want_max: bool) -> Dictionary:
	var bins := {}
	for v in verts:
		var k := _angle_bin(v, segments)
		var r := Vector2(v.x, v.z).length()
		if not bins.has(k):
			bins[k] = []
		bins[k].append([r, v.x, v.z])
	var out := {}
	for k in bins:
		var lst: Array = bins[k]
		lst.sort_custom(self, "_sort_by_radius")
		if want_max:
			out[k] = Vector2(lst[lst.size() - 1][1], lst[lst.size() - 1][2])
		else:
			out[k] = Vector2(lst[0][1], lst[0][2])
	return out

func _sort_by_radius(a: Array, b: Array) -> bool:
	return a[0] < b[0]


class Piece:
	var name := ""
	var kind := "" # "convex" | "box"
	var points := [] # convex: PoolVector3Array; box: [center, half_extents]


func _y_extent(verts: Array, fallback: Vector2) -> Vector2:
	if verts.empty():
		return fallback
	var y0 := INF
	var y1 := -INF
	for v in verts:
		y0 = min(y0, v.y)
		y1 = max(y1, v.y)
	return Vector2(y0, y1)

func _build_pieces(segments: int, outer: Dictionary, inner: Dictionary, floor_y: Vector2,
		rail_y: Vector2, rail_thickness: float, leg_outer: Dictionary, leg_verts: Array,
		leg_half: float, leg_top_y: float) -> Array:
	var pieces := []

	for k in range(segments):
		var k2 := (k + 1) % segments
		if not (outer.has(k) and outer.has(k2) and inner.has(k) and inner.has(k2)):
			continue
		var pts := PoolVector3Array()
		for corner in [outer[k], outer[k2], inner[k], inner[k2]]:
			pts.append(Vector3(corner.x, floor_y.x, corner.y))
			pts.append(Vector3(corner.x, floor_y.y, corner.y))
		var p := Piece.new()
		p.name = "RingFloorSeg_%d" % k
		p.kind = "convex"
		p.points = pts
		pieces.append(p)

	for ring_name in ["Outer", "Inner"]:
		var ring: Dictionary = outer if ring_name == "Outer" else inner
		for k in range(segments):
			var k2 := (k + 1) % segments
			if not (ring.has(k) and ring.has(k2)):
				continue
			var p0: Vector2 = ring[k]
			var p1: Vector2 = ring[k2]
			var mid := (p0 + p1) * 0.5
			var n := mid.normalized()
			var pts := PoolVector3Array()
			for corner in [p0, p1]:
				for sgn in [-1.0, 1.0]:
					var o: Vector2 = corner + n * rail_thickness * sgn
					pts.append(Vector3(o.x, rail_y.x, o.y))
					pts.append(Vector3(o.x, rail_y.y, o.y))
			var p := Piece.new()
			p.name = "RingRail%s_%d" % [ring_name, k]
			p.kind = "convex"
			p.points = pts
			pieces.append(p)

	for k in leg_outer:
		var corner: Vector2 = leg_outer[k]
		# Y real de la pata: min/max de los vertices de esa columna (angulo+radio
		# cercanos a la esquina), no solo la banda "por debajo" — asi conecta bien
		# con el piso aunque el tapon de abajo sea la unica banda aislada.
		var y_min := INF
		var y_max := -INF
		for v in leg_verts:
			if Vector2(v.x, v.z).distance_to(corner) < leg_half * 3.0:
				y_min = min(y_min, v.y)
				y_max = max(y_max, v.y)
		if y_min == INF:
			continue
		y_max = max(y_max, leg_top_y)
		var cy := (y_min + y_max) * 0.5
		var hy := (y_max - y_min) * 0.5
		var p := Piece.new()
		p.name = "RingLeg_%d" % k
		p.kind = "box"
		p.points = [Vector3(corner.x, cy, corner.y), Vector3(leg_half, hy, leg_half)]
		pieces.append(p)

	return pieces


func _splice_into_file(scene_path: String, old_cs: CollisionShape, pieces: Array, body_path: String) -> bool:
	var fs_path := ProjectSettings.globalize_path(scene_path)
	var f := File.new()
	if f.open(fs_path, File.READ) != OK:
		printerr("[bake_ring] no pude abrir ", fs_path)
		return false
	var txt := f.get_as_text()
	f.close()

	var old_shape: ConcavePolygonShape = old_cs.shape
	var old_res_path: String = old_shape.resource_path
	# El shape del .tscn en memoria no trae el id textual; lo recuperamos buscando
	# el bloque `[sub_resource type="ConcavePolygonShape" id=N]` que contiene el
	# primer valor de su PoolVector3Array (huella suficientemente unica).
	var faces := old_shape.get_faces()
	if faces.size() == 0:
		printerr("[bake_ring] el shape original no tiene faces, no puedo ubicarlo en el texto")
		return false
	var needle := "%.4f" % faces[0].x
	var marker_start := txt.find('[sub_resource type="ConcavePolygonShape"')
	var found_block_start := -1
	var found_block_end := -1
	while marker_start != -1:
		var block_end := txt.find("\n\n", marker_start)
		if block_end == -1:
			block_end = txt.length()
		var block: String = txt.substr(marker_start, block_end - marker_start)
		if block.find(needle) != -1:
			found_block_start = marker_start
			found_block_end = block_end + 2
			break
		marker_start = txt.find('[sub_resource type="ConcavePolygonShape"', block_end)
	if found_block_start == -1:
		printerr("[bake_ring] no encontre el sub_resource del shape original en el texto")
		return false
	var old_id_line: String = txt.substr(found_block_start, txt.find("]", found_block_start) - found_block_start + 1)

	var node_name: String = old_cs.name
	var old_node_marker := '[node name="%s" type="CollisionShape" parent="%s"]' % [node_name, body_path]
	var node_start := txt.find(old_node_marker)
	if node_start == -1:
		printerr("[bake_ring] no encontre el nodo ", old_node_marker)
		return false
	var node_block_end := txt.find("\n\n", node_start)
	if node_block_end == -1:
		node_block_end = txt.length()

	# ids nuevos: el mayor id existente en el archivo + 100 de margen.
	var max_id := 0
	var re := RegEx.new()
	re.compile("id=(\\d+)")
	for m in re.search_all(txt):
		max_id = max(max_id, int(m.get_string(1)))
	var next_id := max_id + 100

	var subres_lines := PoolStringArray()
	var node_lines := PoolStringArray()
	for p in pieces:
		var sid := next_id
		next_id += 1
		if p.kind == "convex":
			var flat := PoolStringArray()
			for pt in p.points:
				flat.append("%.5f" % pt.x)
				flat.append("%.5f" % pt.y)
				flat.append("%.5f" % pt.z)
			subres_lines.append('[sub_resource type="ConvexPolygonShape" id=%d]\npoints = PoolVector3Array( %s )\n' % [sid, flat.join(", ")])
			node_lines.append('[node name="%s" type="CollisionShape" parent="%s"]\nshape = SubResource( %d )\n' % [p.name, body_path, sid])
		else:
			var center: Vector3 = p.points[0]
			var half: Vector3 = p.points[1]
			subres_lines.append('[sub_resource type="BoxShape" id=%d]\nextents = Vector3( %.5f, %.5f, %.5f )\n' % [sid, half.x, half.y, half.z])
			node_lines.append('[node name="%s" type="CollisionShape" parent="%s"]\ntransform = Transform( 1, 0, 0, 0, 1, 0, 0, 0, 1, %.5f, %.5f, %.5f )\nshape = SubResource( %d )\n' % [p.name, body_path, center.x, center.y, center.z, sid])

	var new_txt := txt.substr(0, found_block_start)
	new_txt += subres_lines.join("\n") + "\n\n"
	new_txt += txt.substr(found_block_end, node_start - found_block_end)
	new_txt += node_lines.join("\n")
	new_txt += txt.substr(node_block_end)

	# limpiar cualquier __meta__ que quedara apuntando al SubResource viejo (cache
	# de ShapeBounds.trimesh_shape_of, ver core_v2/systems/collision/ShapeBounds.gd)
	var old_id_num := old_id_line.get_slice("id=", 1).replace("]", "")
	var meta_marker := '__meta__ = {\n"odisea_trimesh_shape": SubResource( %s )\n}\n' % old_id_num
	if new_txt.find(meta_marker) != -1:
		new_txt = new_txt.replace(meta_marker, "")
		print("[bake_ring] limpiado __meta__ odisea_trimesh_shape huerfano")

	var out := File.new()
	if out.open(fs_path, File.WRITE) != OK:
		printerr("[bake_ring] no pude escribir ", fs_path)
		return false
	out.store_string(new_txt)
	out.close()
	print("[bake_ring] escrito ", fs_path, " (", new_txt.length(), " bytes, antes ", txt.length(), ")")
	return true
