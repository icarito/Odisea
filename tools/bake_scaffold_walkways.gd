extends SceneTree

# bake_scaffold_walkways.gd — Merges the SpiralStairs, HubSpokes and SpiralWalkways
# groups in Dome_Intro into one combined MeshInstance plus one StaticBody
# sub-scene (all original CollisionShapes reparented under it) each.
#
# Each group is built from several SteelGratePlatform instances (via RadialScatter
# for SpiralStairs/SpiralWalkways, or placed by hand for HubSpokes). Every leg,
# rail post and joint on a SteelGratePlatform is its own MeshInstance (see
# SteelGratePlatform.gd _add_tube_between/_add_joint_cap) — dozens of separate
# VisualServer draw items per platform, which is the CPU cost this scene's live
# hotzone recorder is catching at the top of the tower (confirmed live: dc/obj
# counters at that spot dropped by more than half after baking). This bakes the
# VISUAL geometry into one combined mesh per group, same pattern ScaffoldHubRing
# already uses for the ring floors.
#
# Collision is NOT derived from that combined visual mesh (a trimesh over every
# rail tube/joint produced a messy concave collider that narrowed the walkable
# path). Instead each platform's own clean CollisionShape nodes (one
# ConvexPolygonShape per deck, a few CylinderShapes per leg) are reparented as-is
# under one new StaticBody, saved as its own small sub-scene.
#
# Run: godot3-bin --no-window -s tools/bake_scaffold_walkways.gd
# Output: core_v2/levels/interiors/DomeIntro_<Group>_sector_00..07.mesh
#         core_v2/levels/interiors/DomeIntro_<Group>_body.tscn

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const GROUPS := ["SpiralStairs", "HubSpokes", "SpiralWalkways"]
const OUT_DIR := "res://core_v2/levels/interiors/"
const SECTOR_COUNT := 8
const FOOTSTEP_SURFACE_SCRIPT := "res://core_v2/systems/footsteps/footstep_surface.gd"
const FOOTSTEP_PROFILE_METAL := "res://core_v2/audio/footsteps/footstep_profile_scaffold_metal.tres"

# Cache de firmas de textura por instancia (ver _texture_key).
var _texture_keys := {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load(SCENE_PATH)
	if scene == null:
		push_error("Could not load %s" % SCENE_PATH)
		quit(1)
		return
	var root: Node = scene.instance()
	get_root().add_child(root)

	# RadialScatter.build() is call_deferred, and each SteelGratePlatform builds
	# itself in _ready via _rebuild() (also queued). Give it several idle frames
	# to fully settle before harvesting geometry.
	for _i in range(20):
		yield(self, "idle_frame")

	for group_name in GROUPS:
		_bake_group(root, group_name)

	quit(0)

func _bake_group(root: Node, group_name: String) -> void:
	var group: Spatial = root.get_node_or_null(group_name)
	if group == null:
		push_error("[bake_walkways] group not found: %s" % group_name)
		return

	# Once a group has been wired into Dome_Intro it is a single CombinedMesh plus
	# an instanced StaticBody, not SteelGratePlatforms any more. Re-harvesting that
	# would bake an already-baked mesh, asi que por defecto se omite.
	#
	# Excepcion con ODISEA_BAKE_REDO_WIRED=1: volver a procesar un grupo ya cableado
	# es justamente lo que hace falta para fusionar sus superficies por material,
	# porque las plataformas originales ya no existen en la escena. Es una operacion
	# sin perdida — misma geometria, mismas UV efectivas, mismas colisiones (se
	# recogen del StaticBody instanciado, que sigue colgando del grupo) — y es
	# idempotente: correrlo dos veces da el mismo resultado.
	if group.get_node_or_null("CombinedMesh") != null:
		if OS.get_environment("ODISEA_BAKE_REDO_WIRED") != "1":
			print("[bake_walkways] %s: ya cableado (CombinedMesh presente), se omite" % group_name)
			return
		print("[bake_walkways] %s: ya cableado, se re-procesa para fusionar superficies" % group_name)

	var mesh_instances := []
	_collect_mesh_instances(group, mesh_instances)
	print("[bake_walkways] %s: %d source MeshInstances" % [group_name, mesh_instances.size()])
	if mesh_instances.empty():
		push_error("[bake_walkways] %s produced no MeshInstances - is it built?" % group_name)
		return

	var group_xform_inv: Transform = group.global_transform.affine_inverse()
	# Se agrupa por FIRMA DE CONTENIDO, no por identidad de objeto: cada
	# SteelGratePlatform genera sus propios SpatialMaterial, asi que agrupar por
	# objeto daba una superficie por plataforma y por material (5x4 = 20 en
	# SpiralWalkways) aunque casi todos fueran identicos.
	var surface_tools := {}      # firma -> SurfaceTool
	var signature_material := {} # firma -> Material representativo (uv1 normalizado)
	var signature_order := []    # preserva el orden de aparicion (salida determinista)

	for mi in mesh_instances:
		if mi.mesh == null:
			continue
		var mi_to_group: Transform = group_xform_inv * mi.global_transform
		for surf_idx in range(mi.mesh.get_surface_count()):
			# SteelGratePlatform assigns whole-node material_override (not
			# per-surface surface_material), so that has to be checked first —
			# get_surface_material() only sees per-surface overrides and would
			# otherwise return null for every tube/joint/deck here.
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_surface_material(surf_idx)
			if mat == null:
				mat = mi.mesh.surface_get_material(surf_idx)

			# El grate escala sus UVs por material (uv1_scale depende del tamaño de
			# la plataforma), asi que dos grates de distinto largo no comparten
			# material. Se hornea esa escala en las UVs del vertice y se comparte un
			# material con uv1 neutro.
			var uv_scale := Vector2(1.0, 1.0)
			var uv_offset := Vector2(0.0, 0.0)
			if mat is SpatialMaterial:
				var sm := mat as SpatialMaterial
				uv_scale = Vector2(sm.uv1_scale.x, sm.uv1_scale.y)
				uv_offset = Vector2(sm.uv1_offset.x, sm.uv1_offset.y)

			var sig := _material_signature(mat)
			if not surface_tools.has(sig):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				surface_tools[sig] = st
				signature_order.append(sig)
				signature_material[sig] = _neutralized_material(mat)
			_append_transformed_surface(surface_tools[sig], mi.mesh, surf_idx, mi_to_group,
				uv_scale, uv_offset)

	var combined := ArrayMesh.new()
	for sig in signature_order:
		var st: SurfaceTool = surface_tools[sig]
		st.generate_normals()
		var mat: Material = signature_material[sig]
		if mat != null:
			st.set_material(mat)
		st.commit(combined)

	# Collision: reuse each platform's own CollisionShape resources (a clean
	# ConvexPolygonShape per deck plus a few CylinderShapes per leg) instead of
	# deriving a trimesh from the full visual mesh. The visual mesh also
	# contains every rail tube and joint sphere; trimeshing that produces a
	# messy concave collider whose thin protrusions narrow the walkable area
	# right at the rail line - that's the "collision too narrow" regression.
	var collision_shapes := []  # Array of [Shape, Transform-in-group-space]
	var shape_nodes := []
	_collect_collision_shapes(group, shape_nodes)
	print("[bake_walkways] %s: %d source CollisionShapes" % [group_name, shape_nodes.size()])
	for cs in shape_nodes:
		if cs.shape == null:
			continue
		var cs_to_group: Transform = group_xform_inv * cs.global_transform
		collision_shapes.append([cs.shape, cs_to_group])

	var out_mesh_path := OUT_DIR + "DomeIntro_%s_baked.mesh" % group_name
	if ResourceSaver.save(out_mesh_path, combined) != OK:
		push_error("[bake_walkways] failed to save %s" % out_mesh_path)
		return
	if not _save_visual_sectors(group_name, combined):
		return

	# Pack the StaticBody + all its CollisionShapes (dozens of small convex/
	# cylinder shapes, one clean subtree) into its own sub-scene so Dome_Intro's
	# node text stays a single instanced child instead of dozens of hand-written
	# CollisionShape blocks.
	var body := StaticBody.new()
	body.name = "StaticBody"
	body.collision_layer = 64
	body.collision_mask = 255
	for i in range(collision_shapes.size()):
		var pair = collision_shapes[i]
		var cs := CollisionShape.new()
		cs.name = "Collision_%d" % i
		cs.shape = pair[0]
		cs.transform = pair[1]
		body.add_child(cs)
		cs.owner = body
	var footstep := Spatial.new()
	footstep.name = "FootstepSurface"
	footstep.set_script(load(FOOTSTEP_SURFACE_SCRIPT))
	footstep.set("footstep_profile", load(FOOTSTEP_PROFILE_METAL))
	body.add_child(footstep)
	footstep.owner = body

	var body_packed := PackedScene.new()
	body_packed.pack(body)
	var out_body_path := OUT_DIR + "DomeIntro_%s_body.tscn" % group_name
	if ResourceSaver.save(out_body_path, body_packed) != OK:
		push_error("[bake_walkways] failed to save %s" % out_body_path)
		return

	var vcount := 0
	for i in range(combined.get_surface_count()):
		vcount += (combined.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PoolVector3Array).size()
	print("[bake_walkways] %s: %d surfaces, %d verts, %d collision shapes -> %s / %s" % [
		group_name, combined.get_surface_count(), vcount, collision_shapes.size(), out_mesh_path, out_body_path])

func _save_visual_sectors(group_name: String, combined: ArrayMesh) -> bool:
	var sector_tools: Array = []
	var sector_vertex_counts: Array = []
	for sector_index in range(SECTOR_COUNT):
		var tools_for_surfaces: Array = []
		var counts_for_surfaces: Array = []
		for _surface_index in range(combined.get_surface_count()):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools_for_surfaces.append(st)
			counts_for_surfaces.append(0)
		sector_tools.append(tools_for_surfaces)
		sector_vertex_counts.append(counts_for_surfaces)

	for surface_index in range(combined.get_surface_count()):
		var arrays: Array = combined.surface_get_arrays(surface_index)
		var vertices: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var indices = arrays[Mesh.ARRAY_INDEX]
		var triangle_count: int = (indices as PoolIntArray).size() / 3 if indices is PoolIntArray and (indices as PoolIntArray).size() > 0 else vertices.size() / 3
		for triangle_index in range(triangle_count):
			var vertex_indices: PoolIntArray = PoolIntArray()
			for corner in range(3):
				var flat_index: int = triangle_index * 3 + corner
				vertex_indices.append((indices as PoolIntArray)[flat_index] if indices is PoolIntArray and (indices as PoolIntArray).size() > 0 else flat_index)
			var face_cross: Vector3 = (vertices[vertex_indices[1]] - vertices[vertex_indices[0]]).cross(vertices[vertex_indices[2]] - vertices[vertex_indices[0]])
			if face_cross.length_squared() <= 0.00000001:
				continue
			var face_normal: Vector3 = face_cross.normalized()
			var centroid: Vector3 = (vertices[vertex_indices[0]] + vertices[vertex_indices[1]] + vertices[vertex_indices[2]]) / 3.0
			var angle: float = fposmod(atan2(centroid.z, centroid.x) + PI * 2.0, PI * 2.0)
			var sector_index: int = min(int(floor(angle / (PI * 2.0) * SECTOR_COUNT)), SECTOR_COUNT - 1)
			var target: SurfaceTool = sector_tools[sector_index][surface_index]
			for vertex_index in vertex_indices:
				if uvs != null:
					target.add_uv(uvs[vertex_index])
				if normals != null:
					var normal: Vector3 = normals[vertex_index]
					target.add_normal(normal.normalized() if normal.length_squared() > 0.00000001 else face_normal)
				target.add_vertex(vertices[vertex_index])
			sector_vertex_counts[sector_index][surface_index] += 3

	for sector_index in range(SECTOR_COUNT):
		var sector_mesh := ArrayMesh.new()
		for surface_index in range(combined.get_surface_count()):
			if sector_vertex_counts[sector_index][surface_index] == 0:
				continue
			var st: SurfaceTool = sector_tools[sector_index][surface_index]
			st.set_material(combined.surface_get_material(surface_index))
			st.commit(sector_mesh)
		if sector_mesh.get_surface_count() == 0:
			continue
		var sector_path: String = OUT_DIR + "DomeIntro_%s_sector_%02d.mesh" % [group_name, sector_index]
		if ResourceSaver.save(sector_path, sector_mesh) != OK:
			push_error("[bake_walkways] failed to save %s" % sector_path)
			return false
	return true

# Firma estable del CONTENIDO de un material. Dos materiales generados por
# separado pero con los mismos valores producen la misma firma y comparten
# superficie. uv1_scale/uv1_offset quedan fuera: se hornean en las UVs.
# Las texturas se identifican por resource_path si lo tienen y, si no, por
# instancia — SteelGratePlatform ahora duplica en superficial, asi que las
# plataformas comparten el mismo objeto Texture y esto empareja.
func _material_signature(mat: Material) -> String:
	if mat == null:
		return "<null>"
	var parts := PoolStringArray()
	parts.append(mat.get_class())
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		parts.append("shader=" + (sm.shader.resource_path if sm.shader else "-"))
		if sm.shader != null:
			for p in VisualServer.shader_get_param_list(sm.shader.get_rid()):
				parts.append("%s=%s" % [p.name, _value_key(sm.get_shader_param(p.name))])
		return parts.join("|")
	for p in mat.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_STORAGE):
			continue
		var pname: String = p.name
		if pname in ["resource_path", "resource_name", "resource_local_to_scene", "uv1_scale", "uv1_offset"]:
			continue
		parts.append("%s=%s" % [pname, _value_key(mat.get(pname))])
	return parts.join("|")


func _value_key(v) -> String:
	if v is Texture:
		return "tex:" + _texture_key(v as Texture)
	if v is Resource:
		var r := v as Resource
		return "res:" + r.resource_path if r.resource_path != "" else "obj:%d" % r.get_instance_id()
	return str(v)


# Las texturas se comparan por CONTENIDO, no por ruta. Una malla ya horneada
# guarda su textura embebida ("....mesh::1", "....mesh::5"), asi que dos copias de
# la misma imagen tienen rutas distintas y por ruta nunca deduplicarian.
func _texture_key(t: Texture) -> String:
	var id: int = t.get_instance_id()
	if _texture_keys.has(id):
		return _texture_keys[id]
	var key := "obj:%d" % id
	if t.resource_path != "" and not ("::" in t.resource_path):
		key = t.resource_path
	else:
		var img: Image = t.get_data()
		if img != null:
			var ctx := HashingContext.new()
			ctx.start(HashingContext.HASH_MD5)
			ctx.update(img.get_data())
			key = "img:%dx%d:%s" % [img.get_width(), img.get_height(), ctx.finish().hex_encode()]
	_texture_keys[id] = key
	return key


# Copia del material con uv1 neutro, porque la escala ya quedo horneada en las UVs.
func _neutralized_material(mat: Material) -> Material:
	if not (mat is SpatialMaterial):
		return mat
	var sm := mat as SpatialMaterial
	if sm.uv1_scale == Vector3(1, 1, 1) and sm.uv1_offset == Vector3.ZERO:
		return mat
	var copy := sm.duplicate() as SpatialMaterial
	copy.uv1_scale = Vector3(1, 1, 1)
	copy.uv1_offset = Vector3.ZERO
	return copy


func _collect_collision_shapes(node: Node, out_list: Array) -> void:
	if node is CollisionShape:
		out_list.append(node)
	for child in node.get_children():
		_collect_collision_shapes(child, out_list)

func _collect_mesh_instances(node: Node, out_list: Array) -> void:
	if node is MeshInstance:
		out_list.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out_list)

func _append_transformed_surface(st: SurfaceTool, mesh: Mesh, surf_idx: int, xform: Transform,
		uv_scale: Vector2 = Vector2(1, 1), uv_offset: Vector2 = Vector2(0, 0)) -> void:
	var arrays: Array = mesh.surface_get_arrays(surf_idx)
	var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var indices = arrays[Mesh.ARRAY_INDEX]
	var normal_basis: Basis = xform.basis.inverse().transposed()

	if indices != null and (indices as PoolIntArray).size() > 0:
		for idx in (indices as PoolIntArray):
			_add_vertex(st, verts[idx], normals[idx] if normals != null else null,
				uvs[idx] if uvs != null else null, xform, normal_basis, uv_scale, uv_offset)
	else:
		for i in range(verts.size()):
			_add_vertex(st, verts[i], normals[i] if normals != null else null,
				uvs[i] if uvs != null else null, xform, normal_basis, uv_scale, uv_offset)

func _add_vertex(st: SurfaceTool, v: Vector3, n, uv, xform: Transform, normal_basis: Basis,
		uv_scale: Vector2 = Vector2(1, 1), uv_offset: Vector2 = Vector2(0, 0)) -> void:
	if uv != null:
		# Hornea uv1_scale/uv1_offset del material en la UV del vertice, para que el
		# material compartido pueda quedarse con uv1 neutro.
		st.add_uv(Vector2(uv.x * uv_scale.x + uv_offset.x, uv.y * uv_scale.y + uv_offset.y))
	if n != null:
		st.add_normal(normal_basis.xform(n).normalized())
	st.add_vertex(xform.xform(v))
