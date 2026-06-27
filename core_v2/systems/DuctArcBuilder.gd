extends Reference
class_name DuctArcBuilder

# FD-052: DuctArcBuilder
# Generates procedural toroidal segments for radial duct mazes.

static func get_or_build_arc(major_radius: float, minor_radius: float, arc_degrees: float, segments: int = 12) -> ArrayMesh:
	var cache_key = "%f_%f_%f_%d" % [major_radius, minor_radius, arc_degrees, segments]
	# Note: In a real global script we might use a static variable if supported,
	# but for simplicity and since this is a global class_name, we'll rely on the
	# Spawner to hold the reference or just rebuild if not cached elsewhere.
	# However, the prompt says "Cachea por key". I'll use a static dictionary.
	if not _cache.has(cache_key):
		_cache[cache_key] = _build_arc(major_radius, minor_radius, arc_degrees, segments)
	return _cache[cache_key]

const _cache = {}

static func _build_arc(R: float, r: float, arc_deg: float, arc_segs: int) -> ArrayMesh:
	var section_segs = 16
	var vertices = PoolVector3Array()
	var normals = PoolVector3Array()
	var uvs = PoolVector2Array()
	var indices = PoolIntArray()

	var arc_rad = deg2rad(arc_deg)

	for i in range(arc_segs + 1):
		var u = (float(i) / arc_segs - 0.5) * arc_rad
		var cos_u = cos(u)
		var sin_u = sin(u)

		for j in range(section_segs + 1):
			var v = (float(j) / section_segs) * TAU
			var cos_v = cos(v)
			var sin_v = sin(v)

			# Torus vertex centered at (0,0,0) with Z as tangent axis (arc)
			# Following ODI-001: Z is forward navigable
			var x = r * cos_v
			var z = (R + x) * sin_u
			x = (R + x) * cos_u - R
			var y = r * sin_v

			vertices.push_back(Vector3(x, y, z))

			# Normal
			# The center of the section at angle u is (R*cos_u - R, 0, R*sin_u)
			var center = Vector3(R * cos_u - R, 0, R * sin_u)
			normals.push_back((Vector3(x, y, z) - center).normalized())

			uvs.push_back(Vector2(float(i) / arc_segs, float(j) / section_segs))

	for i in range(arc_segs):
		for j in range(section_segs):
			var i0 = i * (section_segs + 1) + j
			var i1 = i0 + 1
			var i2 = (i + 1) * (section_segs + 1) + j
			var i3 = i2 + 1

			# Winding order: CCW
			indices.push_back(i0)
			indices.push_back(i1)
			indices.push_back(i2)

			indices.push_back(i1)
			indices.push_back(i3)
			indices.push_back(i2)

	var arr = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vertices
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
