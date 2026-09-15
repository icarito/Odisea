extends SceneTree

# bake_dome_terrace_v2.gd — Hornea DomeTerraceV2.glb (domo paramétrico hecho en
# Blender, dome_v2/scene_dome.py) a DomeTerraceV2_baked.mesh + .shape.
#
# Diferencias clave vs el bake Qodot original (bake_dome_terrace_mesh.gd):
#  - Fuente: GLB paramétrico con agujero de hangar centrado en la
#    ScaffoldHubTower (0,0) y 4 bores cilíndricos concéntricos con la carcasa
#    de los airlocks (sin gap).
#  - Superficies: una por material (acero claro, acero oscuro, amarillo, cian),
#    agrupadas con SurfaceTool por bucket y commit() append al ArrayMesh.
#  - La colisión sale del mismo GLB (create_trimesh_shape).
#
# Run: godot3-bin --path . --no-window -s tools/bake_dome_terrace_v2.gd
# Output:
#   core_v2/levels/interiors/DomeTerraceV2_baked.mesh
#   core_v2/levels/interiors/DomeTerraceV2_baked.shape

const SRC_GLB := "res://assets/models/dome_terrace_v2/DomeTerraceV2.glb"
const OUT_MESH := "res://core_v2/levels/interiors/DomeTerraceV2_baked.mesh"
const OUT_SHAPE := "res://core_v2/levels/interiors/DomeTerraceV2_baked.shape"
const WALL_SHADER_PATH := "res://core_v2/levels/interiors/shaders/dome_wall_cylindrical.shader"


# La carcasa (M_BrushedSteelLight) recibe el shader cilíndrico que viajaba
# embebido en la superficie 0 del mesh Qodot original: reconstruye UVs desde la
# posición angular mundial (XZ) para texturizar la pared sin costuras por
# segmento. Los params quedan en default del shader (= el mesh viejo, que tenía
# todos los params sin setear). Los bores van en bucket oscuro aparte para no
# smearingar el tiling a lo largo del túnel.
func _material_for(material: Material) -> Material:
	if material != null and material.resource_name == "M_BrushedSteelLight":
		var shader: Shader = load(WALL_SHADER_PATH)
		if shader != null:
			var sm := ShaderMaterial.new()
			sm.shader = shader
			sm.resource_name = "DomeWallCylindrical"
			return sm
	return material


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load(SRC_GLB)
	if scene == null:
		push_error("[bake_v2] No se pudo cargar %s" % SRC_GLB)
		quit(1)
		return
	var root: Spatial = scene.instance()

	# Bucket por material (ruta si es externo, nombre si va embebido).
	var buckets := {}
	var order := []
	var nodes := 0
	for mi in _all_meshes(root):
		nodes += 1
		var xf: Transform = _relative_transform(mi, root)
		for s in range(mi.mesh.get_surface_count()):
			var material: Material = mi.mesh.surface_get_material(s)
			if material == null:
				material = mi.get_surface_material(s)
			# Clave por nombre normalizado (no por path): el import del GLB da
			# paths distintos (::3, ::5) a instancias duplicadas del mismo
			# material, y Blender añade sufijos .001/.002. Mismo nombre = mismo
			# material plano aqui, asi que se fusionan en un solo bucket.
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
				order.append(key)
			_append_surface(buckets[key], mi.mesh, s, xf)
	var out := ArrayMesh.new()
	order.sort()
	for key in order:
		var st: SurfaceTool = buckets[key]
		st.index()
		st.commit(out)

	if out.get_surface_count() == 0:
		push_error("[bake_v2] malla vacia")
		quit(1)
		return
	var aabb: AABB = out.get_aabb()
	print("[bake_v2] aabb pos=%s size=%s" % [aabb.position, aabb.size])

	out.take_over_path(OUT_MESH)
	var err := ResourceSaver.save(OUT_MESH, out)
	if err != OK:
		push_error("[bake_v2] fallo guardando mesh: %s" % err)
		quit(1)
		return

	var shape: ConcavePolygonShape = out.create_trimesh_shape()
	shape.take_over_path(OUT_SHAPE)
	err = ResourceSaver.save(OUT_SHAPE, shape)
	if err != OK:
		push_error("[bake_v2] fallo guardando shape: %s" % err)
		quit(1)
		return

	var faces := shape.get_faces().size() / 3
	print("[bake_v2] OK: %d surfaces, %d triangulos, %d nodos fuente" % [
		out.get_surface_count(), faces, nodes])
	quit(0)


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
	var normals: PoolVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PoolIntArray = arrays[Mesh.ARRAY_INDEX]
	for i in range(indices.size()):
		var idx := indices[i]
		st.add_uv(uvs[idx] if idx < uvs.size() else Vector2.ZERO)
		if idx < normals.size():
			st.add_normal(xf.basis.xform(normals[idx]).normalized())
		st.add_vertex(xf.xform(verts[idx]))
