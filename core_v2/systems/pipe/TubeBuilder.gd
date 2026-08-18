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


static func generate_tube_mesh(curve: Curve3D, radius: float = 0.05, sides: int = 8, close_caps: bool = false, u_scale: float = 1.0, corner_rounding_radius: float = 0.15, corner_min_angle_deg: float = 15.0) -> ArrayMesh:
	if not curve or curve.get_point_count() < 2:
		return null

	var raw_points = curve.get_baked_points()
	if raw_points.size() < 2:
		return null

	# Filtrar puntos duplicados o extremadamente cercanos
	var clean_points: Array = []
	for p in raw_points:
		if clean_points.empty() or clean_points.back().distance_squared_to(p) > 0.000001:
			clean_points.append(p)

	if clean_points.size() < 2:
		return null

	# Redondear esquinas pronunciadas insertando puntos de arco Bezier (fillet)
	var points: Array = _refine_corner_points(clean_points, corner_rounding_radius, corner_min_angle_deg)
	if points.size() < 2:
		return null

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	if sides < 3:
		sides = 3

	var ring_v_count = sides + 1
	var accumulated_length = 0.0

	# Marco inicial determinista en P0
	var initial_tangent = (points[1] - points[0]).normalized()
	# Regla determinista para el marco inicial:
	# Se elige el vector auxiliar UP (0,1,0). Si la tangente inicial es casi paralela a UP,
	# se utiliza RIGHT (1,0,0) para garantizar la estabilidad numérica y el determinismo.
	var curr_right = initial_tangent.cross(Vector3.UP).normalized()
	if curr_right.length_squared() < 0.001:
		curr_right = initial_tangent.cross(Vector3.RIGHT).normalized()
	var curr_up = curr_right.cross(initial_tangent).normalized()
	var curr_tangent = initial_tangent

	for i in range(points.size()):
		var p = points[i]
		if i > 0:
			var prev_p = points[i - 1]
			accumulated_length += p.distance_to(prev_p)
			var seg_dir = (p - prev_p).normalized()

			# Transporte paralelo: rotación mínima respecto al marco anterior
			var rot_axis = curr_tangent.cross(seg_dir)
			if rot_axis.length_squared() > 0.000001:
				var axis_norm = rot_axis.normalized()
				var angle = curr_tangent.angle_to(seg_dir)
				curr_right = curr_right.rotated(axis_norm, angle)
				curr_up = curr_up.rotated(axis_norm, angle)
			elif curr_tangent.dot(seg_dir) < -0.999:
				# Giro de 180 grados
				curr_right = -curr_right

			curr_tangent = seg_dir

			# Re-ortogonalizar para evitar acumulación de error numérico flotante
			curr_right = (curr_right - curr_tangent * curr_tangent.dot(curr_right)).normalized()
			curr_up = curr_right.cross(curr_tangent).normalized()

		# Generar anillo de vértices
		for j in range(sides + 1):
			var angle = (j / float(sides)) * TAU
			var local_pos = Vector2(cos(angle), sin(angle)) * radius
			var pos_3d = p + (curr_right * local_pos.x) + (curr_up * local_pos.y)

			var uv_x = (j / float(sides)) * u_scale
			var uv_y = accumulated_length
			st.add_uv(Vector2(uv_x, uv_y))
			st.add_vertex(pos_3d)

	# Índices para el cuerpo del tubo
	for i in range(points.size() - 1):
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
		var total_ring_verts = points.size() * ring_v_count

		# Cap inicial (start_p)
		var start_p = points[0]
		var start_tangent = (points[1] - start_p).normalized()
		var start_normal = -start_tangent
		_append_cap(st, start_p, start_normal, radius, sides, total_ring_verts, true)

		# Cap final (end_p)
		var end_p = points[points.size() - 1]
		var end_tangent = (end_p - points[points.size() - 2]).normalized()
		var end_normal = end_tangent
		var end_start_idx = total_ring_verts + 1 + sides
		_append_cap(st, end_p, end_normal, radius, sides, end_start_idx, false)

	st.generate_normals()
	return st.commit()


static func _refine_corner_points(pts: Array, rounding_radius: float, min_angle_deg: float) -> Array:
	if pts.size() < 3 or rounding_radius <= 0.0001:
		return pts

	var min_angle_rad = deg2rad(min_angle_deg)
	var res: Array = []
	res.append(pts[0])

	for i in range(1, pts.size() - 1):
		var p_prev = pts[i - 1]
		var p_curr = pts[i]
		var p_next = pts[i + 1]

		var d1 = (p_curr - p_prev).normalized()
		var d2 = (p_next - p_curr).normalized()
		var angle = d1.angle_to(d2)

		if angle >= min_angle_rad:
			var l1 = p_prev.distance_to(p_curr)
			var l2 = p_curr.distance_to(p_next)
			var t = rounding_radius * tan(angle / 2.0)
			# Limitar el recorte a un máximo del 45% del tramo adyacente para no solapar esquinas
			t = min(t, min(l1 * 0.45, l2 * 0.45))

			if t > 0.001:
				var p_start = p_curr - d1 * t
				var p_end = p_curr + d2 * t

				res.append(p_start)

				# Puntos intermedios en el arco Bezier cuadrático
				var num_steps = int(clamp(ceil(rad2deg(angle) / 15.0), 2.0, 6.0))
				for k in range(1, num_steps):
					var s = float(k) / float(num_steps)
					var arc_p = (1.0 - s) * (1.0 - s) * p_start + 2.0 * (1.0 - s) * s * p_curr + s * s * p_end
					res.append(arc_p)

				res.append(p_end)
			else:
				res.append(p_curr)
		else:
			res.append(p_curr)

	res.append(pts[pts.size() - 1])
	return res


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
