extends SceneTree

# bake_dome_terrace_mesh.gd — Extrae el ArrayMesh embebido de Dome_01.tscn a un .mesh externo,
# quitando las rampas de acceso del mapa de interiores.
#
# Dome_01.tscn pesa ~600 KB porque la geometría del QodotMap (res://maps/DomeTerrace.map)
# quedó horneada como sub_resource ArrayMesh dentro del .tscn. Ese blob se duplica cada vez
# que se copia la escena para un domo nuevo. Extraerlo a un recurso externo permite que los
# interiores que comparten la terraza lo referencien con un solo ext_resource.
#
# Las rampas venían horneadas en la MISMA surface que la cúpula (no son nodos ni surfaces
# separables), así que se filtran por geometría al reconstruir los arrays. Dome_01.tscn
# no se modifica: el filtrado ocurre solo en el .mesh que consume Dome_Intro.
#
# Run: godot3-bin --no-window -s tools/bake_dome_terrace_mesh.gd
# Output: core_v2/levels/interiors/DomeTerrace_baked.mesh

const SRC_SCENE := "res://core_v2/levels/interiors/Dome_01.tscn"
const MESH_NODE := "QodotMap/entity_0_worldspawn/entity_0_mesh_instance"
const OUT_MESH := "res://core_v2/levels/interiors/DomeTerrace_baked.mesh"
const SRC_SHAPE := "res://core_v2/levels/interiors/Dome_01_collision.tres"
const OUT_SHAPE := "res://core_v2/levels/interiors/DomeTerrace_baked.shape"

# Radio del disco de piso útil. Más allá empieza el borde/pared de la cúpula.
const FLOOR_RADIUS := 27.0
# Semiancho del corredor de acceso alineado a cada eje (medido: |across| <= 3.6).
const CORRIDOR_HALF_WIDTH := 3.6
# Las rampas son geometría baja; la bóveda vive muy por encima de esto.
const RAMP_MAX_HEIGHT := 3.2
# Borde del domo (la pared cae en |x| o |z| ≈ 31.25). Más allá es geometría exterior.
const DOME_EDGE := 32.0

# --- Piso como box ---
# El piso original es un anillo perimetral + unos pocos polígonos grandes al centro,
# todo a y=0. Se reemplaza por una placa cuadrada única: el domo entero arranca en
# altura 0, así que una placa plana calza sin huecos contra la base de la cúpula.
const FLOOR_HALF_SIZE := 31.25
# Los UV del mapa original son world-scaled: 0.5 unidades -> 0.0625 UV (1 tile = 8u).
const FLOOR_UV_PER_UNIT := 0.125
# Debajo del piso no se ve nada; el reborde original bajaba a -1.625.
const FLOOR_THICKNESS := 1.625

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load(SRC_SCENE)
	if scene == null:
		push_error("No se pudo cargar %s" % SRC_SCENE)
		quit(1)
		return

	# instance() basta: la malla ya viene horneada en el .tscn, no hay que esperar a Qodot
	# (auto_build solo corre con Engine.is_editor_hint()).
	var root: Node = scene.instance()

	var mesh_instance := root.get_node_or_null(MESH_NODE)
	if mesh_instance == null or not (mesh_instance is MeshInstance):
		push_error("No se encontró el MeshInstance en %s" % MESH_NODE)
		root.free()
		quit(1)
		return

	var src_mesh: Mesh = mesh_instance.mesh
	if src_mesh == null:
		push_error("El MeshInstance no tiene malla")
		root.free()
		quit(1)
		return

	var out_mesh := ArrayMesh.new()
	var total_removed := 0

	var total_floor := 0
	var floor_material: Material = null

	for s in range(src_mesh.get_surface_count()):
		var arrays: Array = src_mesh.surface_get_arrays(s)
		var result := _strip_ramps(arrays)
		total_removed += int(result["removed"])
		total_floor += int(result["floor"])
		# El piso se reconstruye con el material del damero claro. Varias surfaces
		# aportan triángulos de piso (la púrpura de la pared también), así que se
		# elige por textura, no por ser la primera con floor>0.
		if int(result["floor"]) > 0 and _is_light_material(src_mesh.surface_get_material(s)):
			floor_material = src_mesh.surface_get_material(s)
		var out_arrays: Array = result["arrays"]
		var ov: PoolVector3Array = out_arrays[Mesh.ARRAY_VERTEX]
		var oi: PoolIntArray = out_arrays[Mesh.ARRAY_INDEX]
		print("[bake_dome_terrace] surface %d: rampas=%d piso=%d -> verts=%d idx=%d" % [
			s, int(result["removed"]), int(result["floor"]), ov.size(), oi.size()])
		if ov.size() == 0:
			print("[bake_dome_terrace]   (surface vacía tras el filtrado, se omite)")
			continue
		var before := out_mesh.get_surface_count()
		out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
		if out_mesh.get_surface_count() == before:
			push_error("surface %d NO se agregó" % s)
			continue
		out_mesh.surface_set_material(out_mesh.get_surface_count() - 1, src_mesh.surface_get_material(s))

	# Placa de piso: 12 triángulos (caja cerrada) en lugar de los ~134 del anillo original.
	_add_floor_box(out_mesh, _make_floor_material_two_sided(_pick_floor_material(src_mesh, floor_material)))
	print("[bake_dome_terrace] piso original removido=%d tris, reemplazado por box (12 tris)" % total_floor)

	# take_over_path evita que ResourceSaver escriba una referencia a la escena de origen.
	out_mesh.take_over_path(OUT_MESH)
	var err := ResourceSaver.save(OUT_MESH, out_mesh)
	if err != OK:
		push_error("Falló el guardado de la malla: %d" % err)
		root.free()
		quit(1)
		return

	print("[bake_dome_terrace] Guardado %s (surfaces=%d, rampas removidas=%d, aabb=%s)" % [
		OUT_MESH, out_mesh.get_surface_count(), total_removed, out_mesh.get_aabb()])

	# La colisión es un recurso aparte: sin filtrarla quedarían rampas invisibles
	# pero sólidas, con las que el jugador chocaría.
	if not _bake_collision():
		root.free()
		quit(1)
		return

	root.free()
	quit(0)

# El damero del suelo es la textura "light" del set de prototipado.
static func _is_light_material(mat: Material) -> bool:
	if not (mat is SpatialMaterial):
		return false
	var tex := (mat as SpatialMaterial).albedo_texture
	if tex == null:
		return false
	return "/light/" in tex.resource_path

# El piso se dibuja con el material claro; si no se detectó al filtrar, se busca
# directamente entre las surfaces de origen.
func _pick_floor_material(src_mesh: Mesh, detected: Material) -> Material:
	if detected != null:
		return detected
	for s in range(src_mesh.get_surface_count()):
		var mat := src_mesh.surface_get_material(s)
		if _is_light_material(mat):
			return mat
	return null

# El piso es una placa simplificada que se ve tanto desde la cámara baja como a
# través de huecos del scaffold. No debe desaparecer si un import cambia el
# winding de una de sus caras.
func _make_floor_material_two_sided(source: Material) -> Material:
	if not (source is SpatialMaterial):
		return source
	var material: SpatialMaterial = (source as SpatialMaterial).duplicate(true)
	material.params_cull_mode = SpatialMaterial.CULL_DISABLED
	return material

# Placa cuadrada cerrada a y=0. Sustituye el anillo + polígonos sueltos del piso.
func _add_floor_box(mesh: ArrayMesh, material: Material) -> void:
	var h := FLOOR_HALF_SIZE
	var y_top := 0.0
	var y_bot := -FLOOR_THICKNESS

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Cara superior (la única que se pisa y se ve desde adentro).
	_add_quad(st, Vector3(-h, y_top, -h), Vector3(-h, y_top, h), Vector3(h, y_top, h), Vector3(h, y_top, -h), Vector3.UP)
	# Cara inferior, para que la placa sea sólida vista desde abajo.
	_add_quad(st, Vector3(-h, y_bot, h), Vector3(-h, y_bot, -h), Vector3(h, y_bot, -h), Vector3(h, y_bot, h), Vector3.DOWN)
	# Laterales: cierran el canto del piso contra la base de la cúpula.
	_add_quad(st, Vector3(-h, y_bot, -h), Vector3(-h, y_top, -h), Vector3(h, y_top, -h), Vector3(h, y_bot, -h), Vector3.FORWARD)
	_add_quad(st, Vector3(h, y_bot, h), Vector3(h, y_top, h), Vector3(-h, y_top, h), Vector3(-h, y_bot, h), Vector3.BACK)
	_add_quad(st, Vector3(-h, y_bot, h), Vector3(-h, y_top, h), Vector3(-h, y_top, -h), Vector3(-h, y_bot, -h), Vector3.LEFT)
	_add_quad(st, Vector3(h, y_bot, -h), Vector3(h, y_top, -h), Vector3(h, y_top, h), Vector3(h, y_bot, h), Vector3.RIGHT)

	st.generate_tangents()
	st.commit(mesh)
	if material != null:
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)

# Quad con UV world-scaled, para que el damero mantenga el tamaño del mapa original.
func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_normal(normal)
		st.add_uv(_world_uv(v, normal))
		st.add_vertex(v)

func _world_uv(v: Vector3, normal: Vector3) -> Vector2:
	# Proyecta según el eje dominante de la normal para evitar UVs estiradas.
	if abs(normal.y) > 0.5:
		return Vector2(v.x, v.z) * FLOOR_UV_PER_UNIT
	if abs(normal.x) > 0.5:
		return Vector2(v.z, v.y) * FLOOR_UV_PER_UNIT
	return Vector2(v.x, v.y) * FLOOR_UV_PER_UNIT

func _bake_collision() -> bool:
	var src_shape = load(SRC_SHAPE)
	if src_shape == null or not (src_shape is ConcavePolygonShape):
		push_error("No se pudo cargar la colisión %s" % SRC_SHAPE)
		return false

	var faces: PoolVector3Array = src_shape.get_faces()
	var kept := PoolVector3Array()
	var removed := 0
	var floor_removed := 0
	var i := 0
	while i < faces.size():
		var a: Vector3 = faces[i]
		var b: Vector3 = faces[i + 1]
		var c: Vector3 = faces[i + 2]
		i += 3
		if _is_ramp((a + b + c) / 3.0):
			removed += 1
			continue
		if _is_floor(a, b, c):
			floor_removed += 1
			continue
		kept.append(a)
		kept.append(b)
		kept.append(c)

	# La cara superior de la placa es la que sostiene al jugador. Basta esa: el
	# resto del box es visual, y una colisión más simple es más barata de testear.
	var h := FLOOR_HALF_SIZE
	for tri in [
		[Vector3(-h, 0, -h), Vector3(-h, 0, h), Vector3(h, 0, h)],
		[Vector3(-h, 0, -h), Vector3(h, 0, h), Vector3(h, 0, -h)]
	]:
		for v in tri:
			kept.append(v)

	var out_shape := ConcavePolygonShape.new()
	out_shape.set_faces(kept)
	out_shape.take_over_path(OUT_SHAPE)
	var err := ResourceSaver.save(OUT_SHAPE, out_shape)
	if err != OK:
		push_error("Falló el guardado de la colisión: %d" % err)
		return false

	print("[bake_dome_terrace] Guardado %s (rampas=%d, piso=%d -> placa 2 tris, restantes=%d)" % [
		OUT_SHAPE, removed, floor_removed, int(kept.size() / 3.0)])
	return true

# Reconstruye los arrays de una surface omitiendo los triángulos de rampa.
# Reindexa desde cero porque descartar triángulos deja vértices huérfanos.
func _strip_ramps(arrays: Array) -> Dictionary:
	var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PoolIntArray = arrays[Mesh.ARRAY_INDEX]

	var normals: PoolVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PoolVector3Array()
	var uvs: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PoolVector2Array()
	var uv2s: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PoolVector2Array()
	var tangents: PoolRealArray = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PoolRealArray()

	var out_verts := PoolVector3Array()
	var out_normals := PoolVector3Array()
	var out_uvs := PoolVector2Array()
	var out_uv2s := PoolVector2Array()
	var out_tangents := PoolRealArray()
	var out_idx := PoolIntArray()
	var remap := {}
	var removed := 0
	var floor_tris := 0

	var i := 0
	while i < idx.size():
		var ia := idx[i]
		var ib := idx[i + 1]
		var ic := idx[i + 2]
		i += 3
		var centroid: Vector3 = (verts[ia] + verts[ib] + verts[ic]) / 3.0
		if _is_ramp(centroid):
			removed += 1
			continue
		if _is_floor(verts[ia], verts[ib], verts[ic]):
			floor_tris += 1
			continue
		for src_index in [ia, ib, ic]:
			if not remap.has(src_index):
				remap[src_index] = out_verts.size()
				out_verts.append(verts[src_index])
				if normals.size() > 0:
					out_normals.append(normals[src_index])
				if uvs.size() > 0:
					out_uvs.append(uvs[src_index])
				if uv2s.size() > 0:
					out_uv2s.append(uv2s[src_index])
				if tangents.size() > 0:
					for k in range(4):
						out_tangents.append(tangents[src_index * 4 + k])
			out_idx.append(int(remap[src_index]))

	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = out_verts
	if out_normals.size() > 0:
		out_arrays[Mesh.ARRAY_NORMAL] = out_normals
	if out_uvs.size() > 0:
		out_arrays[Mesh.ARRAY_TEX_UV] = out_uvs
	if out_uv2s.size() > 0:
		out_arrays[Mesh.ARRAY_TEX_UV2] = out_uv2s
	if out_tangents.size() > 0:
		out_arrays[Mesh.ARRAY_TANGENT] = out_tangents
	out_arrays[Mesh.ARRAY_INDEX] = out_idx

	return {"arrays": out_arrays, "removed": removed, "floor": floor_tris}

# Geometría de piso: los 3 vértices a y≈0 (cara superior) o en el reborde que baja
# a -1.625. La placa nueva los cubre a todos.
static func _is_floor(a: Vector3, b: Vector3, c: Vector3) -> bool:
	for v in [a, b, c]:
		if v.y > 0.01 or v.y < -FLOOR_THICKNESS - 0.01:
			return false
		if abs(v.x) > FLOOR_HALF_SIZE + 0.01 or abs(v.z) > FLOOR_HALF_SIZE + 0.01:
			return false
	return true

# Una rampa de acceso: geometría baja dentro del corredor alineado a un eje que lleva
# a cada airlock. Cubre tanto la rampa interior (dentro del disco de piso) como el
# corredor que la continúa hacia el borde. La bóveda queda fuera por la altura.
static func _is_ramp(p: Vector3) -> bool:
	if p.y < 0.05 or p.y > RAMP_MAX_HEIGHT:
		return false
	var along: float = abs(p.x) if abs(p.x) > abs(p.z) else abs(p.z)
	var across: float = abs(p.z) if abs(p.x) > abs(p.z) else abs(p.x)
	if across > CORRIDOR_HALF_WIDTH:
		return false
	# Solo dentro del domo. Más allá del borde está la rampa exterior de la fachada,
	# que no pertenece al mapa de interiores y debe conservarse.
	if along > DOME_EDGE:
		return false
	# Descarta el centro del domo: las rampas arrancan cerca del borde del piso.
	return along >= FLOOR_RADIUS - 8.0
