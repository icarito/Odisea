extends Path
class_name MagRail

# MagRail.gd — Riel de mantenimiento de alta velocidad (MVP)
# Extiende Path/Curve3D para definir el trazado; genera geometria greybox con
# materiales existentes y expone consultas deterministicas para PlayerMovementV2.

const DEFAULT_RAIL_MATERIAL_PATH := "res://assets/models/GRIS.tres"
const DEFAULT_ACCENT_MATERIAL_PATH := "res://assets/models/LED.tres"

export(float, 1.0, 4.0) var speed_multiplier := 1.85
export(float, 1.0, 30.0) var min_rail_speed := 11.0
export(float, 1.0, 40.0) var max_rail_speed := 18.0
export(float, 0.2, 3.0) var engage_radius := 1.15
export(float, 1.0, 30.0) var rail_inertia := 8.0
export(float, 0.0, 1.0) var drift_factor := 0.35
export(float, 0.0, 1.5) var player_offset_y := 0.15
export(bool) var bidirectional := true
export(bool) var build_greybox_mesh := true
export(float, 0.05, 0.5) var rail_width := 0.18
export(float, 0.05, 0.5) var rail_height := 0.12
export(NodePath) var attached_body_path := NodePath("")

var _prev_global_transform: Transform = Transform.IDENTITY
var _last_step_prev_transform: Transform = Transform.IDENTITY
var _last_step_curr_transform: Transform = Transform.IDENTITY
var _has_prev_transform := false
var _attached_body: Node = null
var _platform_velocity_cache := Vector3.ZERO
var _greybox_mesh_node: MeshInstance = null
var _added_exception_players := {}


func _ready() -> void:
	add_to_group("magrail")
	_prev_global_transform = global_transform
	_last_step_prev_transform = global_transform
	_last_step_curr_transform = global_transform
	_has_prev_transform = true
	_resolve_attached_body()
	if build_greybox_mesh and not Engine.editor_hint:
		_rebuild_greybox_mesh()
	elif build_greybox_mesh and Engine.editor_hint:
		_rebuild_greybox_mesh()


func _physics_process(dt: float) -> void:
	if Engine.editor_hint:
		return
	if dt > 0.0 and _has_prev_transform:
		_last_step_prev_transform = _prev_global_transform
		_last_step_curr_transform = global_transform
		var delta_origin: Vector3 = global_transform.origin - _prev_global_transform.origin
		_platform_velocity_cache = delta_origin / dt
	_prev_global_transform = global_transform
	_has_prev_transform = true


func _resolve_attached_body() -> void:
	if attached_body_path != NodePath(""):
		_attached_body = get_node_or_null(attached_body_path)
		return
	var p := get_parent()
	if p is RigidBody or p is KinematicBody:
		_attached_body = p


func _exit_tree() -> void:
	for pid in _added_exception_players.keys():
		var entry: Dictionary = _added_exception_players[pid]
		var body: Node = entry.get("body", null)
		var player: Node = entry.get("player", null)
		if is_instance_valid(body) and is_instance_valid(player) and body is RigidBody:
			(body as RigidBody).remove_collision_exception_with(player)
	_added_exception_players.clear()


func register_player_exception(player: Node) -> void:
	if _attached_body == null or not is_instance_valid(_attached_body):
		_resolve_attached_body()
	# Contrato machine-launch.md: excepcion unilateral desde la pieza rigida al jugador.
	if _attached_body is RigidBody and is_instance_valid(player) and player is PhysicsBody:
		var rb := _attached_body as RigidBody
		if player in rb.get_collision_exceptions():
			return
		rb.add_collision_exception_with(player)
		_added_exception_players[player.get_instance_id()] = {
			"body": rb,
			"player": player
		}


func unregister_player_exception(player: Node) -> void:
	if not is_instance_valid(player):
		return
	var pid: int = player.get_instance_id()
	if not _added_exception_players.has(pid):
		return
	var entry: Dictionary = _added_exception_players[pid]
	_added_exception_players.erase(pid)
	var body: Node = entry.get("body", null)
	if is_instance_valid(body) and body is RigidBody:
		(body as RigidBody).remove_collision_exception_with(player)


func get_platform_velocity_at(world_pos: Vector3, dt: float) -> Vector3:
	if _attached_body != null and is_instance_valid(_attached_body) and _attached_body is RigidBody:
		var rb := _attached_body as RigidBody
		var arm: Vector3 = world_pos - rb.global_transform.origin
		return rb.linear_velocity + rb.angular_velocity.cross(arm)
	if dt > 0.0 and _has_prev_transform:
		var curr_tx: Transform = global_transform
		var prev_tx: Transform = _prev_global_transform
		if curr_tx.is_equal_approx(prev_tx):
			curr_tx = _last_step_curr_transform
			prev_tx = _last_step_prev_transform
		var local_pt: Vector3 = curr_tx.affine_inverse().xform(world_pos)
		var prev_world_pt: Vector3 = prev_tx.xform(local_pt)
		return (world_pos - prev_world_pt) / dt
	return _platform_velocity_cache


func get_curve_length() -> float:
	if curve == null:
		return 0.0
	return curve.get_baked_length()


func is_curve_closed() -> bool:
	if curve == null or curve.get_point_count() < 2:
		return false
	var first_pt: Vector3 = curve.get_point_position(0)
	var last_pt: Vector3 = curve.get_point_position(curve.get_point_count() - 1)
	return first_pt.distance_squared_to(last_pt) < 0.01


func get_closest_point_info(world_pos: Vector3) -> Dictionary:
	if curve == null or curve.get_point_count() < 2:
		return {}
	var length: float = curve.get_baked_length()
	if length <= 0.001:
		return {}
	var local_pos: Vector3 = to_local(world_pos)
	var offset: float = clamp(curve.get_closest_offset(local_pos), 0.0, length)
	var sample: Dictionary = sample_at_offset(offset, 1.0)
	if sample.empty():
		return {}
	var closest_world: Vector3 = sample["world_pos"]
	sample["distance"] = world_pos.distance_to(closest_world)
	sample["offset"] = offset
	sample["curve_length"] = length
	return sample


func sample_at_offset(offset: float, direction_sign: float) -> Dictionary:
	if curve == null or curve.get_point_count() < 2:
		return {}
	var length: float = curve.get_baked_length()
	if length <= 0.001:
		return {}
	var clamped_offset: float = clamp(offset, 0.0, length)
	var local_pos: Vector3 = curve.interpolate_baked(clamped_offset)
	var eps: float = min(0.2, length * 0.1)
	var dir_s: float = 1.0 if direction_sign >= 0.0 else -1.0
	var off_a: float = clamp(clamped_offset - eps * dir_s, 0.0, length)
	var off_b: float = clamp(clamped_offset + eps * dir_s, 0.0, length)
	var pos_a: Vector3 = curve.interpolate_baked(off_a)
	var pos_b: Vector3 = curve.interpolate_baked(off_b)
	var local_tan: Vector3 = pos_b - pos_a
	if local_tan.length_squared() < 0.000001:
		local_tan = Vector3.FORWARD * dir_s
	else:
		local_tan = local_tan.normalized()

	# Curvatura horizontal aproximada (cambio de direccion por metro) para derrape controlado.
	var step_ahead: float = clamp(clamped_offset + 0.6 * dir_s, 0.0, length)
	var step_ahead_b: float = clamp(step_ahead + eps * dir_s, 0.0, length)
	var tan_ahead: Vector3 = curve.interpolate_baked(step_ahead_b) - curve.interpolate_baked(step_ahead)
	var curvature := 0.0
	if tan_ahead.length_squared() > 0.000001:
		tan_ahead = tan_ahead.normalized()
		var cross_y: float = local_tan.cross(tan_ahead).y
		curvature = clamp(cross_y * 2.5, -1.0, 1.0)

	var world_pos: Vector3 = global_transform.xform(local_pos)
	var world_tan: Vector3 = global_transform.basis.xform(local_tan).normalized()
	var world_up: Vector3 = global_transform.basis.y.normalized()
	return {
		"world_pos": world_pos,
		"tangent": world_tan,
		"up": world_up,
		"curvature": curvature,
		"offset": clamped_offset,
		"curve_length": length
	}


func _rebuild_greybox_mesh() -> void:
	if curve == null or curve.get_point_count() < 2:
		return
	var points: PoolVector3Array = curve.get_baked_points()
	if points.size() < 2:
		return

	if _greybox_mesh_node != null and is_instance_valid(_greybox_mesh_node):
		_greybox_mesh_node.queue_free()
	_greybox_mesh_node = MeshInstance.new()
	_greybox_mesh_node.name = "GreyboxRailMesh"
	add_child(_greybox_mesh_node)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hw: float = rail_width * 0.5
	var hh: float = rail_height * 0.5
	var n_pts: int = points.size()
	for i in range(n_pts - 1):
		var p0: Vector3 = points[i]
		var p1: Vector3 = points[i + 1]
		var seg: Vector3 = p1 - p0
		if seg.length_squared() < 0.00001:
			continue
		var fwd: Vector3 = seg.normalized()
		var side: Vector3 = fwd.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		else:
			side = side.normalized()
		var up: Vector3 = side.cross(fwd).normalized()

		var a0: Vector3 = p0 - side * hw + up * hh
		var b0: Vector3 = p0 + side * hw + up * hh
		var c0: Vector3 = p0 + side * hw - up * hh
		var d0: Vector3 = p0 - side * hw - up * hh

		var a1: Vector3 = p1 - side * hw + up * hh
		var b1: Vector3 = p1 + side * hw + up * hh
		var c1: Vector3 = p1 + side * hw - up * hh
		var d1: Vector3 = p1 - side * hw - up * hh

		# Top
		_add_quad(st, a0, b0, b1, a1, up)
		# Bottom
		_add_quad(st, d1, c1, c0, d0, -up)
		# Left
		_add_quad(st, d0, a0, a1, d1, -side)
		# Right
		_add_quad(st, b0, c0, c1, b1, side)

	var mat: Material = null
	if ResourceLoader.exists(DEFAULT_RAIL_MATERIAL_PATH):
		mat = load(DEFAULT_RAIL_MATERIAL_PATH)
	if mat == null:
		var fallback := SpatialMaterial.new()
		fallback.albedo_color = Color(0.28, 0.34, 0.42, 1.0)
		fallback.metallic = 0.6
		fallback.roughness = 0.35
		mat = fallback
	st.set_material(mat)
	_greybox_mesh_node.mesh = st.commit()


func _add_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3) -> void:
	st.add_normal(normal)
	st.add_vertex(v0)
	st.add_normal(normal)
	st.add_vertex(v1)
	st.add_normal(normal)
	st.add_vertex(v2)

	st.add_normal(normal)
	st.add_vertex(v0)
	st.add_normal(normal)
	st.add_vertex(v2)
	st.add_normal(normal)
	st.add_vertex(v3)
