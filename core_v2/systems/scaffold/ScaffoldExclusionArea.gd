tool
extends Area
class_name ScaffoldExclusionArea
# Component: drop into any scene to carve out a box-shaped hole in the
# InfiniteScaffoldField.
#
# Usage:
#   1. Instance ScaffoldExclusionArea.tscn (or add an Area with this script).
#   2. Add a CollisionShape child with a BoxShape.
#   3. Resize the BoxShape using the editor gizmo.
#   4. Position / rotate the node in the editor.

## Extra margin around the box where pipes get *capped* instead of removed.
export var soft_margin: float = 0.0

func _ready():
	if not Engine.editor_hint:
		add_to_group("scaffold_exclusion")
	# Don't collide with anything, just for area definition
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false

func _get_extents() -> Vector3:
	for child in get_children():
		if child is CollisionShape and child.shape is BoxShape:
			return child.shape.extents
	return Vector3(5, 5, 5)

func is_point_excluded(world_pos: Vector3) -> bool:
	var local = global_transform.affine_inverse().xform(world_pos)
	var ext = _get_extents()
	return abs(local.x) <= ext.x and abs(local.y) <= ext.y and abs(local.z) <= ext.z

func is_point_in_margin(world_pos: Vector3) -> bool:
	if soft_margin <= 0.0:
		return false
	var local = global_transform.affine_inverse().xform(world_pos)
	var ext = _get_extents()
	var outer = ext + Vector3(soft_margin, soft_margin, soft_margin)
	var inside_outer = abs(local.x) <= outer.x and abs(local.y) <= outer.y and abs(local.z) <= outer.z
	return inside_outer and not is_point_excluded(world_pos)

func get_aabb_world() -> AABB:
	var ext = _get_extents()
	var corners = []
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				corners.append(global_transform.xform(Vector3(ext.x * sx, ext.y * sy, ext.z * sz)))
	var mn = corners[0]
	var mx = corners[0]
	for c in corners:
		mn.x = min(mn.x, c.x)
		mn.y = min(mn.y, c.y)
		mn.z = min(mn.z, c.z)
		mx.x = max(mx.x, c.x)
		mx.y = max(mx.y, c.y)
		mx.z = max(mx.z, c.z)
	return AABB(mn, mx - mn)

func _get_configuration_warning() -> String:
	var has_box = false
	for child in get_children():
		if child is CollisionShape and child.shape is BoxShape:
			has_box = true
			break
	if not has_box:
		return "This node requires a CollisionShape child with a BoxShape to define the exclusion volume."
	return ""
