extends SceneTree

# bake_dome_exterior_lowpoly.gd — Hornea DomeExteriorLowPoly.glb (hemisferio
# super low-poly hecho en Blender) a .mesh + .shape.
#
# Es el gemelo EXTERIOR de bake_dome_interior_lowpoly.gd:
#  - Misma geometría (16 radiales x 8 anillos = 240 tris, radio 16.5 m, base a
#    z=0, ápex a z=16.5).
#  - Diferencia clave: es una cáscara EXTERIOR. El material va con cull BACK
#    (no disabled) porque la cara que importa es la de afuera; el interior se
#    descarta. El domo interior, en cambio, se ve desde adentro (cull disabled).
#  - Un solo material (M_DomeExteriorLowPoly); sin split piso/carcasa ni lightmap.
#  - NO está cableado a ninguna escena todavía: es asset listo para usar.
#
# Fuente: Blender, 16x8 -> 240 triángulos. Regenerar:
#   X_CAM=ext blender --background --python <render.py> -- --scene <scene_dome_ext.py>
#   (usa el GLB de la vista "ext": cáscara limpia, sin luces de preview)
# Run: tools/godot --path . --no-window -s tools/bake_dome_exterior_lowpoly.gd
# Output:
#   core_v2/levels/exteriors/DomeExteriorLowPoly_baked.mesh
#   core_v2/levels/exteriors/DomeExteriorLowPoly_baked.shape

# Mismo escalado que el gemelo interior: la cascara se hornea a TARGET_RADIUS
# para que ambos domos sigan siendo el mismo objeto visto de los dos lados.
const SRC_RADIUS := 16.5
const TARGET_RADIUS := 35.0

const SRC_GLB := "res://assets/models/dome_exterior_lowpoly/DomeExteriorLowPoly.glb"
const OUT_MESH := "res://core_v2/levels/exteriors/DomeExteriorLowPoly_baked.mesh"
const OUT_SHAPE := "res://core_v2/levels/exteriors/DomeExteriorLowPoly_baked.shape"


# El material del GLB llega como SpatialMaterial. Forzamos cull BACK (exterior
# visible, interior descartado) para que la cáscara sea una superficie exterior
# normal y barata en la Mali.
func _material_for(material: Material) -> Material:
	if material is SpatialMaterial:
		var sm := (material as SpatialMaterial).duplicate() as SpatialMaterial
		sm.resource_name = "M_DomeExteriorLowPoly"
		sm.params_cull_mode = SpatialMaterial.CULL_BACK
		return sm
	return material


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load(SRC_GLB)
	if scene == null:
		push_error("[bake_dome_ext] No se pudo cargar %s" % SRC_GLB)
		quit(1)
		return
	var root: Spatial = scene.instance()

	# Bucket por material (nombre normalizado): aquí hay un solo material.
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
		push_error("[bake_dome_ext] malla vacia")
		quit(1)
		return

	var aabb: AABB = out.get_aabb()
	print("[bake_dome_ext] aabb pos=%s size=%s" % [aabb.position, aabb.size])

	out.take_over_path(OUT_MESH)
	var err := ResourceSaver.save(OUT_MESH, out)
	if err != OK:
		push_error("[bake_dome_ext] fallo guardando mesh: %s" % err)
		quit(1)
		return

	var shape: ConcavePolygonShape = out.create_trimesh_shape()
	shape.take_over_path(OUT_SHAPE)
	err = ResourceSaver.save(OUT_SHAPE, shape)
	if err != OK:
		push_error("[bake_dome_ext] fallo guardando shape: %s" % err)
		quit(1)
		return

	var faces := shape.get_faces().size() / 3
	print("[bake_dome_ext] OK: %d surfaces, %d triangulos, %d nodos fuente" % [
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
	var uvs: PoolVector2Array = PoolVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		uvs = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PoolIntArray = arrays[Mesh.ARRAY_INDEX]
	for i in range(indices.size()):
		var idx := indices[i]
		st.add_uv(uvs[idx] if idx < uvs.size() else Vector2.ZERO)
		if idx < normals.size():
			st.add_normal(xf.basis.xform(normals[idx]).normalized())
		st.add_vertex(xf.xform(verts[idx]))
