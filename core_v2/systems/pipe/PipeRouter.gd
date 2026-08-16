tool
extends Spatial
class_name PipeRouter

# PipeRouter.gd — Generador procedural determinista de rutas de tubería.
#
# Calcula un camino que abraza paredes y techo entre dos fixtures (tanque, criopod,
# válvula, tee) manteniendo un offset configurable de la geometría y evitando el suelo.

func _ready() -> void:
	add_to_group("replay_sync")


# API principal: calcula la Curve3D entre from_anchor y to_anchor.
# from_anchor / to_anchor pueden ser NodePath, Spatial, Vector3 o Transform.
func generate_route(from_anchor, to_anchor, options: Dictionary = {}) -> Curve3D:
	var pos_a: Vector3 = _resolve_position(from_anchor)
	var pos_b: Vector3 = _resolve_position(to_anchor)

	var offset: float = float(options.get("offset", 0.15))
	var snap: float = float(options.get("snap", 0.5))
	var clearance: float = float(options.get("clearance", 2.0))
	var prefer_ceiling: bool = bool(options.get("prefer_ceiling", true))
	var corner_radius: float = float(options.get("corner_radius", 0.25))
	var space_state: PhysicsDirectSpaceState = options.get("space_state", null) as PhysicsDirectSpaceState

	if space_state == null and is_inside_tree() and get_world():
		space_state = get_world().direct_space_state

	# Determinar altura de techo objetivo
	var ceiling_y: float = max(pos_a.y, pos_b.y) + clearance

	if space_state:
		var ray_a = space_state.intersect_ray(pos_a, pos_a + Vector3.UP * 10.0, [self])
		var ray_b = space_state.intersect_ray(pos_b, pos_b + Vector3.UP * 10.0, [self])

		if ray_a and ray_a.has("position"):
			ceiling_y = min(ceiling_y, ray_a["position"].y - offset)
		if ray_b and ray_b.has("position"):
			ceiling_y = min(ceiling_y, ray_b["position"].y - offset)

	# Asegurar que la altura del techo sea superior a ambos puntos
	ceiling_y = max(ceiling_y, max(pos_a.y, pos_b.y) + offset)

	if snap > 0.0:
		ceiling_y = stepify(ceiling_y, snap)

	# Construir la lista de waypoints en orden
	var waypoints: Array = []

	waypoints.append(pos_a)

	if prefer_ceiling:
		# Puntos intermedios hacia el techo y a lo largo de las paredes
		var p1 = Vector3(pos_a.x, ceiling_y, pos_a.z)
		var p2 = Vector3(pos_b.x, ceiling_y, pos_a.z)
		var p3 = Vector3(pos_b.x, ceiling_y, pos_b.z)

		if snap > 0.0:
			p1.x = stepify(p1.x, snap)
			p1.z = stepify(p1.z, snap)
			p2.x = stepify(p2.x, snap)
			p2.z = stepify(p2.z, snap)
			p3.x = stepify(p3.x, snap)
			p3.z = stepify(p3.z, snap)

		_append_unique_waypoint(waypoints, p1)
		_append_unique_waypoint(waypoints, p2)
		_append_unique_waypoint(waypoints, p3)
	else:
		# Trazado alternativo (ej: abraza paredes primero)
		var wall_y = pos_a.y + (pos_b.y - pos_a.y) * 0.5
		if snap > 0.0:
			wall_y = stepify(wall_y, snap)

		var p1 = Vector3(pos_a.x, wall_y, pos_a.z)
		var p2 = Vector3(pos_b.x, wall_y, pos_b.z)

		_append_unique_waypoint(waypoints, p1)
		_append_unique_waypoint(waypoints, p2)

	_append_unique_waypoint(waypoints, pos_b)

	# Limpiar waypoints colineales redundantes
	waypoints = _clean_collinear_waypoints(waypoints)

	# Construir Curve3D con codos/suavizado de esquinas
	var curve = Curve3D.new()

	if waypoints.size() < 2:
		return curve

	for i in range(waypoints.size()):
		var curr: Vector3 = waypoints[i]

		if i == 0 or i == waypoints.size() - 1 or corner_radius <= 0.0:
			curve.add_point(curr)
		else:
			var prev: Vector3 = waypoints[i - 1]
			var next: Vector3 = waypoints[i + 1]

			var dir_in: Vector3 = (curr - prev).normalized()
			var dir_out: Vector3 = (next - curr).normalized()

			var seg_in_len: float = curr.distance_to(prev)
			var seg_out_len: float = curr.distance_to(next)
			var r: float = min(corner_radius, min(seg_in_len * 0.4, seg_out_len * 0.4))

			var handle_in = -dir_in * r
			var handle_out = dir_out * r

			curve.add_point(curr, handle_in, handle_out)

	return curve


func _resolve_position(anchor) -> Vector3:
	if anchor is Vector3:
		return anchor
	elif anchor is Transform:
		return anchor.origin
	elif anchor is Spatial:
		return anchor.global_transform.origin
	elif anchor is NodePath:
		if not anchor.is_empty():
			var node = get_node_or_null(anchor)
			if node and node is Spatial:
				return node.global_transform.origin
	return Vector3.ZERO


func _append_unique_waypoint(waypoints: Array, p: Vector3) -> void:
	if waypoints.size() > 0:
		var last: Vector3 = waypoints[waypoints.size() - 1]
		if last.distance_to(p) < 0.001:
			return
	waypoints.append(p)


func _clean_collinear_waypoints(waypoints: Array) -> Array:
	if waypoints.size() <= 2:
		return waypoints

	var cleaned: Array = []
	cleaned.append(waypoints[0])

	for i in range(1, waypoints.size() - 1):
		var prev: Vector3 = cleaned[cleaned.size() - 1]
		var curr: Vector3 = waypoints[i]
		var next: Vector3 = waypoints[i + 1]

		var d1 = (curr - prev).normalized()
		var d2 = (next - curr).normalized()

		if d1.dot(d2) < 0.9999:
			cleaned.append(curr)

	cleaned.append(waypoints[waypoints.size() - 1])
	return cleaned


# --- CONTRATO DE REPLAY DETERMINISTA ---

func get_snapshot() -> Dictionary:
	return {
		"name": name,
		"transform": global_transform
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("transform"):
		global_transform = data["transform"]
