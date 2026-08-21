extends Node

# Applies `make bake` visual authoring without changing runtime pipe graph
# positions or NodePaths.
export(Resource) var visual_bake: Resource


func _ready() -> void:
	call_deferred("_apply_visual_authoring")


func _apply_visual_authoring() -> void:
	if visual_bake == null:
		return
	var dome: Node = get_parent()
	if dome == null:
		return
	_apply_recursive(dome)


func _apply_recursive(node: Node) -> void:
	if node.name == "FissureVisual" and bool(visual_bake.get("orient_leaks_inward")):
		_apply_leak_direction(node)
	elif node.name.begins_with("Valve") and node is Spatial and bool(visual_bake.get("orient_valves_inward")):
		_apply_valve_facing(node as Spatial)
	for child in node.get_children():
		_apply_recursive(child)


func _apply_leak_direction(node: Node) -> void:
	if not node.has_method("set_spray_direction") or not (node is Spatial):
		return
	var fissure: Spatial = node as Spatial
	var inward_world := _inward_direction(fissure.global_transform.origin)
	var local_direction: Vector3 = fissure.global_transform.basis.xform_inv(inward_world).normalized()
	node.set_spray_direction(local_direction)


func _apply_valve_facing(valve: Spatial) -> void:
	var inward_world := _inward_direction(valve.global_transform.origin)
	var local_x: Vector3 = Vector3.UP.cross(inward_world).normalized()
	if local_x.length_squared() <= 0.000001:
		return
	var visual_transform := valve.global_transform
	visual_transform.basis = Basis(local_x, Vector3.UP, inward_world)
	valve.global_transform = visual_transform


func _inward_direction(world_position: Vector3) -> Vector3:
	var inward := Vector3(-world_position.x, 0.12, -world_position.z)
	if inward.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return inward.normalized()
