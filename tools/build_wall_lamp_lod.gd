extends SceneTree

const SOURCE := "res://core_v2/props/scifi_lights/IndustrialWallLampLow.mesh"
const TARGET := "res://core_v2/props/scifi_lights/IndustrialWallLampLOD.mesh"
const GRID_RESOLUTION := 72.0

func _init() -> void:
	var source: ArrayMesh = load(SOURCE) as ArrayMesh
	var arrays: Array = source.surface_get_arrays(0)
	var vertices: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PoolVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PoolIntArray = arrays[Mesh.ARRAY_INDEX]
	var bounds: AABB = source.get_aabb()
	var cell_size: float = max(bounds.size.x, max(bounds.size.y, bounds.size.z)) / GRID_RESOLUTION
	var clusters := {}
	var remap := PoolIntArray()
	remap.resize(vertices.size())
	for index in range(vertices.size()):
		var vertex: Vector3 = vertices[index]
		var cell: Vector3 = (vertex - bounds.position) / cell_size
		var key := "%d:%d:%d" % [int(floor(cell.x)), int(floor(cell.y)), int(floor(cell.z))]
		if not clusters.has(key):
			clusters[key] = [clusters.size(), Vector3.ZERO, Vector3.ZERO, Vector2.ZERO, 0]
		var cluster: Array = clusters[key]
		cluster[1] += vertex
		cluster[2] += normals[index]
		cluster[3] += uvs[index]
		cluster[4] += 1
		clusters[key] = cluster
		remap[index] = cluster[0]
	var out_vertices := PoolVector3Array()
	var out_normals := PoolVector3Array()
	var out_uvs := PoolVector2Array()
	out_vertices.resize(clusters.size())
	out_normals.resize(clusters.size())
	out_uvs.resize(clusters.size())
	for cluster in clusters.values():
		var target_index: int = cluster[0]
		var divisor: float = float(cluster[4])
		out_vertices[target_index] = cluster[1] / divisor
		out_normals[target_index] = (cluster[2] / divisor).normalized()
		out_uvs[target_index] = cluster[3] / divisor
	var out_indices := PoolIntArray()
	for index in range(0, indices.size(), 3):
		var a: int = remap[indices[index]]
		var b: int = remap[indices[index + 1]]
		var c: int = remap[indices[index + 2]]
		if a != b and b != c and a != c:
			out_indices.append(a)
			out_indices.append(b)
			out_indices.append(c)
	var output := []
	output.resize(Mesh.ARRAY_MAX)
	output[Mesh.ARRAY_VERTEX] = out_vertices
	output[Mesh.ARRAY_NORMAL] = out_normals
	output[Mesh.ARRAY_TEX_UV] = out_uvs
	output[Mesh.ARRAY_INDEX] = out_indices
	var lod := ArrayMesh.new()
	lod.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, output)
	lod.surface_set_material(0, source.surface_get_material(0))
	lod.resource_name = "IndustrialWallLampLOD"
	var result: int = ResourceSaver.save(TARGET, lod)
	print("LOD vertices %d -> %d, triangles %d -> %d" % [vertices.size(), out_vertices.size(), indices.size() / 3, out_indices.size() / 3])
	quit(result)
