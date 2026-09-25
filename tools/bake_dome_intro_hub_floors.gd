extends SceneTree

# bake_dome_intro_hub_floors.gd — Rehornea el CombinedMesh/CombinedCollision de
# TODOS los pisos de ScaffoldHubTower en Dome_Intro.
#
# Antes esto era bake_dome_intro_floor5_railing.gd y solo tocaba Floor_5, porque
# lo unico en discusion eran sus aperturas. Pero los cinco pisos comparten la
# geometria de deck de ScaffoldHubRing, asi que cualquier cambio ahi (por ejemplo
# pasar el deck a un solo quad de doble cara) hay que rehornearlo en todos: la
# escena guarda cada piso ya horneado y el script solo no cambia nada.
#
# Pass 1 closed the elevator-side rail opening (106.048-123.196 deg) and kept the
# original deck/walkway opening (86.022-94.820 deg, from the tower's authored
# inner_opening_angles_deg[5]=90.4). Pass 2 widened that to (86.02,106.05),
# assuming the walkway docked along a wide arc.
#
# Both were wrong. Measured live via global_transform (SpiralWalkways/Item_4's
# _deck_point at all four corners), Item_4 is oriented with its WIDTH axis
# radial and its DEPTH axis tangential: "front" and "back" are radial edges at
# fixed angles (78 deg and 105 deg), "left"/"right" are the tangential-direction
# rails along the ramp. So Item_4 meets the ring at a single angle (~105 deg,
# its "back" edge), not across a wide arc — a corner-to-corner point contact,
# matching what was described as "la union en esquina". Item_4's own
# rail_back_opening (width 2.5, gravity 0.0) is a radial doorway starting right
# at its inner corner (r=13.26) and running out to ~r=15.76, at that same fixed
# angle. The ring only needs a narrow angular gap there — the same width
# (2.5m) projected onto the ring's radius — not a 20 degree arc. The wide arc
# left a real hole (nothing on the other side of most of it) plus a dangling
# rail stub where the old opening boundary didn't line up with anything on
# Item_4's side.
#
# Floor_5 is a ScaffoldHubRing instance whose children are normally pre-baked (see
# ScaffoldHubRing.gd _ready()), so editing its outer_openings_deg text in the .tscn
# has no runtime effect on its own — the mesh has to be rebuilt and re-saved.
# Instead of re-deriving ScaffoldHubTower's build() parameter plumbing, this loads
# the explicit source scene, finds the already-configured Floor_5 node, edits its
# opening arrays, forces a synchronous rebuild, and saves the result as loose
# .mesh/.shape resources (same pattern as DomeTerrace_baked.mesh).
#
# Run: godot3-bin --no-window -s tools/bake_dome_intro_hub_floors.gd
# Output: core_v2/levels/interiors/Dome_Intro_Floor5_baked.mesh / .shape

const DEFAULT_SOURCE_PATH := "res://core_v2/levels/interiors/DomeIntro_HubTowerSource.tscn"
const TOWER_PATH := "ScaffoldHubTower"
const OUT_DIR := "res://core_v2/levels/interiors/"

# Prefijo de los archivos horneados. Sin la variable de entorno se mantiene el
# nombre historico de Dome_Intro; una variante del modulo de criogenia lo cambia y
# hornea a archivos propios sin pisar los de Dome_Intro. Va junto con
# ODISEA_BAKE_SOURCE, que elige la escena fuente.
const DEFAULT_OUT_PREFIX := "Dome_Intro"
var _prefix := DEFAULT_OUT_PREFIX
var _visual_chunks := 1
const LIGHTMAP_TEXEL_SIZE := 0.2
# Todos los pisos del hub, no solo el 5: comparten la geometria de deck de
# ScaffoldHubRing, asi que cualquier cambio ahi hay que re-hornearlo en los cinco.
const FLOORS := ["Floor_1", "Floor_2", "Floor_3", "Floor_4", "Floor_5"]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_prefix = OS.get_environment("ODISEA_BAKE_PREFIX")
	if _prefix.empty():
		_prefix = DEFAULT_OUT_PREFIX
	_visual_chunks = max(1, int(OS.get_environment("ODISEA_BAKE_VISUAL_CHUNKS")))
	var source_path: String = OS.get_environment("ODISEA_BAKE_SOURCE")
	if source_path.empty():
		source_path = DEFAULT_SOURCE_PATH
	var scene: PackedScene = load(source_path)
	if scene == null:
		push_error("Could not load source %s" % source_path)
		quit(1)
		return

	# Mismo motivo que en bake_scaffold_walkways.gd: si PropDitherManager esta activo
	# lo que se hornea son sus ShaderMaterial de runtime, no los materiales autorizados.
	var dither = get_root().get_node_or_null("PropDitherManager")
	if dither != null:
		dither.set_process(false)
		if is_connected("node_added", dither, "_on_node_added"):
			disconnect("node_added", dither, "_on_node_added")
	# Mismo motivo, peor: en tier LOW el gate muta los materiales COMPARTIDOS en
	# memoria (_low_tier_material apaga transparencia/alpha scissor y prende vertex
	# lighting) y al guardarlos quedan las rejillas opacas para todos los perfiles.
	var gate = get_root().get_node_or_null("GLES3VendorGate")
	if gate != null and gate.has_method("suspend_node_mutation"):
		gate.suspend_node_mutation()
		print("[bake_floors] GLES3VendorGate suspendido para hornear")

	var root: Node = scene.instance()
	get_root().add_child(root)

	for floor_name in FLOORS:
		if not _bake_floor(root, floor_name):
			quit(1)
			return
	quit(0)


# firma de contenido -> Material ya guardado en disco (compartido entre pisos)
var _shared_materials := {}

func _share_materials(mesh: ArrayMesh) -> void:
	for i in range(mesh.get_surface_count()):
		var mat: Material = mesh.surface_get_material(i)
		if mat == null:
			continue
		var signature: String = _material_signature(mat)
		if not _shared_materials.has(signature):
			var path: String = OUT_DIR + _prefix + "_HubRing_mat_%02d.material" % _shared_materials.size()
			if ResourceSaver.save(path, mat) != OK:
				push_error("[bake_floors] no pude guardar %s" % path)
				continue
			_shared_materials[signature] = load(path)
		mesh.surface_set_material(i, _shared_materials[signature])

func _material_signature(mat: Material) -> String:
	var parts := PoolStringArray()
	parts.append(mat.get_class())
	for p in mat.get_property_list():
		if not (int(p.usage) & PROPERTY_USAGE_STORAGE):
			continue
		if p.name in ["resource_path", "resource_name", "resource_local_to_scene"]:
			continue
		var value = mat.get(p.name)
		if value is Resource:
			parts.append("%s=%s" % [p.name, (value as Resource).resource_path])
		else:
			parts.append("%s=%s" % [p.name, str(value)])
	return parts.join("|")

func _bake_floor(root: Node, floor_name: String) -> bool:
	var ring: Spatial = root.get_node_or_null(TOWER_PATH + "/" + floor_name)
	if ring == null:
		push_error("[bake_floors] no encuentro %s/%s" % [TOWER_PATH, floor_name])
		return false

	# Los valores de apertura salen de la escena (ver comentario de arriba): este
	# tool solo fuerza la reconstruccion y guarda el resultado.
	ring.rebuild_baked_items = true
	ring.build()

	var visual: MeshInstance = ring.get_node_or_null("CombinedMesh")
	var body: StaticBody = ring.get_node_or_null("StaticBody")
	var collision: CollisionShape = body.get_node_or_null("CombinedCollision") if body else null
	if visual == null or visual.mesh == null or collision == null or collision.shape == null:
		push_error("[bake_floors] %s no produjo CombinedMesh/CombinedCollision" % floor_name)
		return false

	# Los cinco pisos usan los MISMOS materiales de ScaffoldHubRing (deck, marco,
	# baranda) pero cada uno se guardaba con su copia privada embebida, o sea 15
	# materiales distintos para 3 reales: 15 cambios de material por frame y cero
	# batching entre pisos. Se guardan una vez y se referencian desde los cinco.
	_share_materials(visual.mesh)

	var out_mesh: String = OUT_DIR + _prefix + "_%s_baked.mesh" % floor_name
	var out_shape: String = OUT_DIR + _prefix + "_%s_baked.shape" % floor_name
	# Sin UV2 el BakedLightmap ignora la geometria: los pisos del hub no proyectan
	# sombra sobre la terraza ni reciben la luz cocinada. Se genera sobre la malla
	# completa (todas las surfaces), igual que en bake_scaffold_walkways.gd.
	if _visual_chunks == 1:
		if not _save_visual(visual.mesh, out_mesh):
			return false
	else:
		var chunks: Array = _split_mesh_angular(visual.mesh, _visual_chunks)
		for chunk_index in range(chunks.size()):
			var chunk_path: String = OUT_DIR + _prefix + "_%s_third_%d.mesh" % [floor_name, chunk_index]
			if not _save_visual(chunks[chunk_index], chunk_path):
				return false
	if ResourceSaver.save(out_shape, collision.shape) != OK:
		push_error("[bake_floors] no pude guardar %s" % out_shape)
		return false

	var verts := 0
	for i in range(visual.mesh.get_surface_count()):
		verts += visual.mesh.surface_get_array_len(i)
	print("[bake_floors] %s: %d superficies, %d verts, %d chunks, openings=%s docks=%s" % [
		floor_name, visual.mesh.get_surface_count(), verts,
		_visual_chunks, str(ring.outer_openings_deg), str(ring.outer_opening_docks)])
	return true


func _save_visual(mesh: ArrayMesh, path: String) -> bool:
	if not _generate_lightmap_uv2(mesh, path):
		return false
	if ResourceSaver.save(path, mesh) != OK:
		push_error("[bake_floors] no pude guardar %s" % path)
		return false
	return true


# Parte triangulos completos por el angulo de su centroide. No corta geometria:
# cada producto tiene un AABB propio para que el frustum culling de Godot pueda
# descartar dos tercios sin agregar un culler de runtime.
func _split_mesh_angular(mesh: ArrayMesh, chunk_count: int) -> Array:
	var chunks := []
	for _i in range(chunk_count):
		chunks.append(ArrayMesh.new())
	for surface in range(mesh.get_surface_count()):
		var source: Array = mesh.surface_get_arrays(surface)
		var vertices: PoolVector3Array = source[Mesh.ARRAY_VERTEX]
		var indices := PoolIntArray()
		if source[Mesh.ARRAY_INDEX] != null:
			indices = source[Mesh.ARRAY_INDEX]
		var triangle_values := []
		for _i in range(chunk_count):
			var values: Array = source.duplicate()
			for channel in range(Mesh.ARRAY_MAX):
				if channel == Mesh.ARRAY_INDEX or values[channel] == null:
					continue
				values[channel] = _empty_mesh_array(channel)
			values[Mesh.ARRAY_INDEX] = null
			triangle_values.append(values)
		var triangle_index_count: int = indices.size() if not indices.empty() else vertices.size()
		for triangle in range(0, triangle_index_count, 3):
			var a: int = indices[triangle] if not indices.empty() else triangle
			var b: int = indices[triangle + 1] if not indices.empty() else triangle + 1
			var c: int = indices[triangle + 2] if not indices.empty() else triangle + 2
			var center: Vector3 = (vertices[a] + vertices[b] + vertices[c]) / 3.0
			var angle: float = fposmod(atan2(center.z, center.x), TAU)
			var target: int = min(int(angle * float(chunk_count) / TAU), chunk_count - 1)
			for vertex_index in [a, b, c]:
				_copy_vertex(source, triangle_values[target], vertex_index)
		for chunk_index in range(chunk_count):
			var chunk: ArrayMesh = chunks[chunk_index]
			var values: Array = triangle_values[chunk_index]
			if values[Mesh.ARRAY_VERTEX].empty():
				continue
			chunk.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, values)
			chunk.surface_set_material(chunk.get_surface_count() - 1, mesh.surface_get_material(surface))
	return chunks


func _copy_vertex(source: Array, target: Array, vertex_index: int) -> void:
	for channel in range(Mesh.ARRAY_MAX):
		if channel == Mesh.ARRAY_INDEX or source[channel] == null:
			continue
		var stride: int = 4 if channel in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS] else 1
		var values = target[channel]
		for component in range(stride):
			values.append(source[channel][vertex_index * stride + component])
		target[channel] = values


func _empty_mesh_array(channel: int):
	match channel:
		Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL:
			return PoolVector3Array()
		Mesh.ARRAY_TANGENT, Mesh.ARRAY_WEIGHTS:
			return PoolRealArray()
		Mesh.ARRAY_COLOR:
			return PoolColorArray()
		Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2:
			return PoolVector2Array()
		Mesh.ARRAY_BONES:
			return PoolIntArray()
	return null


func _generate_lightmap_uv2(mesh: ArrayMesh, mesh_path: String) -> bool:
	var result: int = mesh.lightmap_unwrap(Transform.IDENTITY, LIGHTMAP_TEXEL_SIZE)
	if result != OK:
		push_error("[bake_floors] no pude generar UV2 para %s (error %d)" % [mesh_path, result])
		return false
	return true
