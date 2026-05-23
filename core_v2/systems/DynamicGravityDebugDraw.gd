extends ImmediateGeometry
class_name DynamicGravityDebugDraw

export(NodePath) var target_path := NodePath("")
export(float) var vector_scale := 1.0
export(Color) var gravity_color := Color(0.2, 0.7, 1.0, 1.0)
export(Color) var up_color := Color(1.0, 0.9, 0.2, 1.0)

func _process(_delta: float) -> void:
	clear()
	if not has_node("/root/GravityWorld"):
		return

	var target: Spatial = _resolve_target()
	if target == null:
		return

	var gw = get_node("/root/GravityWorld")
	var origin: Vector3 = target.global_transform.origin
	var gravity: Vector3 = Vector3.ZERO
	if gw.has_method("get_physical_gravity"):
		gravity = gw.get_physical_gravity(origin)
	if gravity.length_squared() <= 0.000001:
		return

	var down: Vector3 = gravity.normalized()
	begin(Mesh.PRIMITIVE_LINES)
	set_color(gravity_color)
	add_vertex(origin)
	add_vertex(origin + down * vector_scale)
	set_color(up_color)
	add_vertex(origin)
	add_vertex(origin - down * vector_scale * 0.5)
	end()

func _resolve_target() -> Spatial:
	if not target_path.is_empty():
		var node: Node = get_node_or_null(target_path)
		if node is Spatial:
			return node as Spatial
	var parent: Node = get_parent()
	if parent is Spatial:
		return parent as Spatial
	return null
