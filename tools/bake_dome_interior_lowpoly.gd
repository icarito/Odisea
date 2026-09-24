extends SceneTree

# bake_dome_interior_lowpoly.gd — Hornea DomeInteriorLowPoly.glb (hemisferio
# super low-poly hecho en Blender) a .mesh + .shape para RingHub_Level.
#
# Diferencias clave vs bake_dome_terrace_v2.gd:
#  - Fuente: GLB minimalista (16 radiales x 8 anillos = 240 tris, radio 16.5 m,
#    base a z=0, ápex a z=16.5). Nada de bores, piso ni ribs: el facetado lo
#    pinta la textura albedo en Godot.
#  - Un solo material (M_DomeInteriorLowPoly); no hay split piso/carcasa ni
#    lightmap: RingHub usa iluminación en tiempo real (Environment + Sun).
#  - La carcasa se ve desde adentro, así que el material va con cull disabled.
#  - El GLB no trae UVs utiles (todas en cero), asi que el bake genera UV1
#    cilindricas: u = azimut/TAU (0..1, vuelta completa) y v = y/TARGET_RADIUS
#    (0..1, base a apex). RingHub_DomeShell.tres las reescala con uv1_scale.
#  - La colisión sale del mismo GLB (create_trimesh_shape): la cáscara del domo
#    ES un caso estándar de trimesh cóncavo (barato, 240 tris), igual que los
#    domos Dome_Default / Dome_Base ya existentes.
#
# Fuente: Blender, 16x8 -> 240 triángulos. Regenerar:
#   X_CAM=ext blender --background --python <render.py> -- --scene <scene_dome_lp.py>
#   (usa el GLB de la vista "ext": cáscara limpia, sin emisión/luces de preview)
# Run: tools/godot --path . --no-window -s tools/bake_dome_interior_lowpoly.gd
# Output:
#   core_v2/levels/interiors/DomeInteriorLowPoly_baked.mesh (RingHub_Level)
#   core_v2/levels/interiors/DomeInteriorLowPoly_baked.shape (RingHub_Level)

# El hemisferio del GLB sale de Blender con radio 16.5 m; RingHub_Level es una
# torre cuya geometria real llega a r=32.13 (medido sobre vertices), asi que la
# cascara se hornea escalada a TARGET_RADIUS para envolverla en vez de cortarla.
const SRC_RADIUS := 16.5
const TARGET_RADIUS := 35.0

const SRC_GLB := "res://assets/models/dome_interior_lowpoly/DomeInteriorLowPoly.glb"
const OUT_MESH := "res://core_v2/levels/interiors/DomeInteriorLowPoly_baked.mesh"
const OUT_SHAPE := "res://core_v2/levels/interiors/DomeInteriorLowPoly_baked.shape"


# El material del GLB llega como SpatialMaterial. Forzamos cull disabled para
# que la cara interna de la cáscara sea visible desde dentro del domo (la
# geometría es single-sided y el jugador está adentro).
func _material_for(material: Material) -> Material:
	if material is SpatialMaterial:
		var sm := (material as SpatialMaterial).duplicate() as SpatialMaterial
		sm.resource_name = "M_DomeInteriorLowPoly"
		sm.params_cull_mode = SpatialMaterial.CULL_DISABLED
		return sm
	return material


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load(SRC_GLB)
	if scene == null:
		push_error("[bake_dome_lp] No se pudo cargar %s" % SRC_GLB)
		quit(1)
		return
	var root: Spatial = scene.instance()

	# Bucket por material (nombre normalizado): el import del GLB puede dar
	# paths distintos (::3) a instancias duplicadas del mismo material, así que
	# agrupamos por nombre. Aquí hay un solo material -> un solo bucket.
	var buckets := {}
	var nodes := 0
	for mi in _all_meshes(root):
		nodes += 1
		var k := TARGET_RADIUS / SRC_RADIUS
		var xf: Transform = Transform.IDENTITY.scaled(Vector3(k, k, k)) * _relative_transform(mi, root)
		for s in range(mi.mesh.get_surface_count()):
			var material: Material = mi.mesh.surface_get_material(s)
			if material == null:
				material = mi.get_surface_material(s)
			var key := "emb:NULL"
			if material != null:
				var name_norm := material.resource_name
				if name_norm == "":
					name_norm = material.resource_path.get_file()
				while name_norm.length() > 4 \
						and name_norm.substr(name_norm.length() - 4, 1) == "." \
						and name_norm.substr(name_norm.length() - 3).is_valid_integer():
					name_norm = name_norm.substr(0, name_norm.length() - 4)
				key = "emb:" + name_norm
			if not buckets.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				if material != null:
					st.set_material(_material_for(material))
				buckets[key] = st
			_append_surface(buckets[key], mi.mesh, s, xf)

	var out := _commit_buckets(buckets)
	if out.get_surface_count() == 0:
		push_error("[bake_dome_lp] malla vacia")
		quit(1)
		return

	var aabb: AABB = out.get_aabb()
	print("[bake_dome_lp] aabb pos=%s size=%s" % [aabb.position, aabb.size])

	out.take_over_path(OUT_MESH)
	var err := ResourceSaver.save(OUT_MESH, out)
	if err != OK:
		push_error("[bake_dome_lp] fallo guardando mesh: %s" % err)
		quit(1)
		return

	var shape: ConcavePolygonShape = out.create_trimesh_shape()
	shape.take_over_path(OUT_SHAPE)
	err = ResourceSaver.save(OUT_SHAPE, shape)
	if err != OK:
		push_error("[bake_dome_lp] fallo guardando shape: %s" % err)
		quit(1)
		return

	var faces := shape.get_faces().size() / 3
	print("[bake_dome_lp] OK: %d surfaces, %d triangulos, %d nodos fuente" % [
		out.get_surface_count(), faces, nodes])
	quit(0)


func _commit_buckets(buckets: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var keys := buckets.keys()
	keys.sort()
	for key in keys:
		var st: SurfaceTool = buckets[key]
		st.index()
		st.commit(mesh)
	return mesh


func _all_meshes(node: Node) -> Array:
	var out := []
	if node is MeshInstance and node.mesh != null:
		out.append(node)
	for child in node.get_children():
		out += _all_meshes(child)
	return out


func _relative_transform(node: Node, ancestor: Node) -> Transform:
	var xf := Transform.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != ancestor:
		if cursor is Spatial:
			xf = (cursor as Spatial).transform * xf
		cursor = cursor.get_parent()
	return xf


func _append_surface(st: SurfaceTool, mesh: ArrayMesh, surface: int, xf: Transform) -> void:
	var arrays := mesh.surface_get_arrays(surface)
	if arrays.empty():
		return
	var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PoolVector3Array = PoolVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		normals = arrays[Mesh.ARRAY_NORMAL]
	var indices: PoolIntArray = arrays[Mesh.ARRAY_INDEX]
	for i in range(indices.size()):
		var idx := indices[i]
		var wp: Vector3 = xf.xform(verts[idx])
		# UV1 cilindrica: la fuente no trae UVs usables (todas en cero). El azimut
		# se mide sobre -Z para que la costura del wrap caiga detras del jugador.
		var u: float = atan2(wp.x, -wp.z) / TAU + 0.5
		var v: float = wp.y / TARGET_RADIUS
		st.add_uv(Vector2(u, v))
		if idx < normals.size():
			st.add_normal(xf.basis.xform(normals[idx]).normalized())
		st.add_vertex(wp)
