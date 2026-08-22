extends SceneTree

# Separa DomeTerrace_baked.mesh sin regenerar geometría ni materiales desde Dome_01.
# El recurso fuente es el asset artístico versionado: sus surfaces 0-1 son el domo
# con dome_wall_cylindrical.shader y la 2 es el piso PBR de Hangar Concrete Floor.

const SOURCE_MESH := "res://core_v2/levels/interiors/DomeTerrace_baked.mesh"
const OUT_SHELL_MESH := "res://core_v2/levels/interiors/DomeShell_baked.mesh"
const OUT_FLOOR_MESH := "res://core_v2/levels/interiors/DomeTerraceFloor_baked.mesh"
# El UV2 del piso heredado del mesh combinado sólo ocupaba ~1/10 del atlas
# resultante. Reempaquetarlo por separado deja suficientes texels para que las
# sombras del andamio no desaparezcan en el filtrado del lightmap.
const FLOOR_LIGHTMAP_TEXEL_SIZE := 0.1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var source: ArrayMesh = load(SOURCE_MESH)
	if source == null:
		push_error("[split_dome_terrace] no pude cargar " + SOURCE_MESH)
		quit(1)
		return
	var shell := ArrayMesh.new()
	var floor_mesh := ArrayMesh.new()
	for surface_index in range(source.get_surface_count()):
		var destination: ArrayMesh = floor_mesh if _is_floor_surface(source, surface_index) else shell
		_append_surface(source, surface_index, destination)
	if shell.get_surface_count() == 0 or floor_mesh.get_surface_count() == 0:
		push_error("[split_dome_terrace] no encontré domo y piso por separado")
		quit(1)
		return
	if not _has_uv2_on_all_surfaces(shell):
		push_error("[split_dome_terrace] el domo fuente no tiene UV2 en todas sus surfaces")
		quit(1)
		return
	# No se regeneran ni los materiales ni la geometría: sólo se recalcula el
	# segundo canal UV del piso ya separado, para que use su propio atlas.
	var unwrap_result: int = floor_mesh.lightmap_unwrap(Transform.IDENTITY, FLOOR_LIGHTMAP_TEXEL_SIZE)
	if unwrap_result != OK or not _has_uv2_on_all_surfaces(floor_mesh):
		push_error("[split_dome_terrace] no pude reempaquetar UV2 del piso: %d" % unwrap_result)
		quit(1)
		return
	# Godot 3 vincula el BakedLightmapData a la instancia de mesh en runtime.
	# Un ArrayMesh externo compartido puede hornearse bien (el PNG contiene luz),
	# pero perder ese vínculo al ejecutar. El piso es un receptor único de
	# Dome_Intro, así que debe duplicarse localmente al instanciar la escena.
	floor_mesh.resource_local_to_scene = true
	if not _save(OUT_SHELL_MESH, shell) or not _save(OUT_FLOOR_MESH, floor_mesh):
		quit(1)
		return
	print("[split_dome_terrace] PASS: shell=%d surfaces, floor=%d surfaces; materiales copiados sin cambios, UV2 del piso a %.2fm/texel" % [
		shell.get_surface_count(), floor_mesh.get_surface_count(), FLOOR_LIGHTMAP_TEXEL_SIZE])
	quit()

func _is_floor_surface(mesh: ArrayMesh, surface_index: int) -> bool:
	var arrays: Array = mesh.surface_get_arrays(surface_index)
	var vertices: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PoolIntArray = arrays[Mesh.ARRAY_INDEX]
	if indices.empty():
		return false
	for index_offset in range(0, indices.size(), 3):
		for vertex_index in [indices[index_offset], indices[index_offset + 1], indices[index_offset + 2]]:
			var vertex: Vector3 = vertices[vertex_index]
			if vertex.y > 0.01 or vertex.y < -1.635 or abs(vertex.x) > 31.26 or abs(vertex.z) > 31.26:
				return false
	return true

func _append_surface(source: ArrayMesh, surface_index: int, destination: ArrayMesh) -> void:
	destination.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(surface_index))
	destination.surface_set_material(destination.get_surface_count() - 1, source.surface_get_material(surface_index))

func _has_uv2_on_all_surfaces(mesh: ArrayMesh) -> bool:
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var uv2: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		if uv2.empty():
			return false
	return true

func _save(path: String, mesh: ArrayMesh) -> bool:
	mesh.take_over_path(path)
	var result: int = ResourceSaver.save(path, mesh)
	if result != OK:
		push_error("[split_dome_terrace] no pude guardar %s: %d" % [path, result])
		return false
	return true
