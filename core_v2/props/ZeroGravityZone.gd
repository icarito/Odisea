extends Area

class_name ZeroGravityZone

const GravityModes = preload("res://core_v2/systems/GravityModes.gd")

export(int, "STANDARD_1G", "SPIN_WALKABLE", "ZERO_G", "SPIN_DYNAMIC") var gravity_mode := GravityModes.Mode.ZERO_G
export(int) var gravity_priority := 100
export(bool) var allow_coriolis := false
export(bool) var affect_props := false

func _ready() -> void:
	if not is_connected("body_entered", self, "_on_body_entered"):
		connect("body_entered", self, "_on_body_entered")
	if not is_connected("body_exited", self, "_on_body_exited"):
		connect("body_exited", self, "_on_body_exited")
	if has_node("/root/GravityWorld"):
		get_node("/root/GravityWorld").register_zone(self)

func _exit_tree() -> void:
	if has_node("/root/GravityWorld"):
		get_node("/root/GravityWorld").unregister_zone(self)

func get_gravity_mode() -> int:
	return gravity_mode

func get_gravity_priority() -> int:
	return gravity_priority

func contains_global_point(global_position: Vector3) -> bool:
	for child in get_children():
		if not child is CollisionShape:
			continue
		var shape_node: CollisionShape = child as CollisionShape
		if shape_node.disabled or shape_node.shape == null:
			continue
		var local: Vector3 = shape_node.global_transform.affine_inverse().xform(global_position)
		if shape_node.shape is BoxShape:
			var extents: Vector3 = (shape_node.shape as BoxShape).extents
			if abs(local.x) <= extents.x and abs(local.y) <= extents.y and abs(local.z) <= extents.z:
				return true
		elif shape_node.shape is SphereShape:
			if local.length() <= (shape_node.shape as SphereShape).radius:
				return true
	return false

func get_volume() -> float:
	var volume: float = INF
	for child in get_children():
		if child is CollisionShape and (child as CollisionShape).shape is BoxShape:
			var extents: Vector3 = ((child as CollisionShape).shape as BoxShape).extents
			volume = min(volume, extents.x * extents.y * extents.z * 8.0)
	return volume

func allows_coriolis() -> bool:
	return allow_coriolis

func affects_props() -> bool:
	return affect_props

func _on_body_entered(body: Node) -> void:
	print("[ZeroGravityZone] Body entered: ", body.name)
	if not body.is_in_group("player"):
		return
	
	var cm = body.get_node_or_null("ControllerManager")
	if cm and cm.has_method("switch_to"):
		cm.switch_to(cm.Mode.ZERO_GRAVITY)

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
		
	var cm = body.get_node_or_null("ControllerManager")
	if cm and cm.has_method("switch_to"):
		cm.switch_to(cm.Mode.STANDARD_1G)
