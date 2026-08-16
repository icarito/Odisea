class_name TubeBuilder
extends Reference

# TubeBuilder.gd — Generador reutilizable de mallas de tubos/cables sobre una Curve3D.
# Utilizado por CircuitCable, PipeRun y sistemas de conducción.

static func generate_circle_polygon(radius: float, sides: int = 8) -> PoolVector2Array:
	var arr = PoolVector2Array()
	if sides < 3:
		sides = 3
	for i in range(sides):
		var angle = (i / float(sides)) * TAU
		arr.append(Vector2(cos(angle), sin(angle)) * radius)
	return arr


static func generate_tube_mesh(curve: Curve3D, radius: float = 0.05, sides: int = 8, close_caps: bool = false, u_scale: float = 1.0) -> ArrayMesh:
	if not curve or curve.get_point_count() < 2:
		return null

	var baked_points = curve.get_baked_points()
	if baked_points.size() < 2:
		return null

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	if sides < 3:
		sides = 3

	var ring_v_count = sides + 1
	var up = Vector3.UP
	var accumulated_length = 0.0

	for i in range(baked_points.size()):
		var p = baked_points[i]
		var tangent = Vector3.FORWARD
		if i < baked_points.size() - 1:
			tangent = (baked_points[i + 1] - p).normalized()
		elif i > 0:
			tangent = (p - baked_points[i - 1]).normalized()

		if i > 0:
			accumulated_length += baked_points[i].distance_to(baked_points[i - 1])

		# Construir marco ortonormal (Frenet) estable
		var right = tangent.cross(up).normalized()
		if right.length_squared() < 0.001:
			right = tangent.cross(Vector3.RIGHT).normalized()
		up = right.cross(tangent).normalized()

		# Generar anillo de vértices
		for j in range(sides + 1):
			var angle = (j / float(sides)) * TAU
			var local_pos = Vector2(cos(angle), sin(angle)) * radius
			var pos_3d = p + (right * local_pos.x) + (up * local_pos.y)

			var uv_x = (j / float(sides)) * u_scale
			var uv_y = accumulated_length
			st.add_uv(Vector2(uv_x, uv_y))
			st.add_vertex(pos_3d)

	# Indices para el cuerpo del tubo
	for i in range(baked_points.size() - 1):
		for j in range(sides):
			var curr = i * ring_v_count + j
			var next = curr + 1
			var upper_curr = (i + 1) * ring_v_count + j
			var upper_next = upper_curr + 1

			st.add_index(curr)
			st.add_index(upper_curr)
			st.add_index(next)

			st.add_index(next)
			st.add_index(upper_curr)
			st.add_index(upper_next)

	# Tapas de los extremos si close_caps es verdadero
	if close_caps:
		var total_ring_verts = baked_points.size() * ring_v_count

		# Cap inicial (start_p)
		var start_p = baked_points[0]
		var start_tangent = (baked_points[1] - start_p).normalized()
		var start_normal = -start_tangent
		_append_cap(st, start_p, start_normal, radius, sides, total_ring_verts, true)

		# Cap final (end_p)
		var end_p = baked_points[baked_points.size() - 1]
		var end_tangent = (end_p - baked_points[baked_points.size() - 2]).normalized()
		var end_normal = end_tangent
		var end_start_idx = total_ring_verts + 1 + sides
		_append_cap(st, end_p, end_normal, radius, sides, end_start_idx, false)

	st.generate_normals()
	return st.commit()


static func _append_cap(st: SurfaceTool, center: Vector3, normal: Vector3, radius: float, sides: int, start_vertex_idx: int, invert_indices: bool) -> void:
	var up = Vector3.UP
	var right = normal.cross(up).normalized()
	if right.length_squared() < 0.001:
		right = normal.cross(Vector3.RIGHT).normalized()
	up = right.cross(normal).normalized()

	var center_idx = start_vertex_idx
	st.add_uv(Vector2(0.5, 0.5))
	st.add_vertex(center)

	var ring_first_idx = start_vertex_idx + 1
	for i in range(sides):
		var angle = (i / float(sides)) * TAU
		var pos = center + (right * cos(angle) * radius) + (up * sin(angle) * radius)
		var uv = Vector2(0.5 + cos(angle) * 0.5, 0.5 + sin(angle) * 0.5)
		st.add_uv(uv)
		st.add_vertex(pos)

	for i in range(sides):
		var curr = ring_first_idx + i
		var next = ring_first_idx + ((i + 1) % sides)
		if invert_indices:
			st.add_index(center_idx)
			st.add_index(next)
			st.add_index(curr)
		else:
			st.add_index(center_idx)
			st.add_index(curr)
			st.add_index(next)
