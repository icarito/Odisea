tool
extends Area

class_name ZeroGravityZone

signal gravity_zone_changed(body, mode)

const GravityModes = preload("res://core_v2/systems/GravityModes.gd")

export(int, "STANDARD_1G", "SPIN_WALKABLE", "ZERO_G", "SPIN_DYNAMIC") var gravity_mode := GravityModes.Mode.ZERO_G
export(int) var gravity_priority := 100
export(bool) var allow_coriolis := false
export(bool) var affect_props := false
export(Color) var debug_color: Color = Color(0.2, 0.65, 1.0, 0.3) setget set_debug_color
export(bool) var debug_render: bool = true setget set_debug_render

func _ready() -> void:
	if Engine.editor_hint:
		set_process(true)
		_update_debug_mesh()
		return
	set_process(false)
	add_to_group("zero_gravity_zones")
	if not is_connected("body_entered", self, "_on_body_entered"):
		connect("body_entered", self, "_on_body_entered")
	if not is_connected("body_exited", self, "_on_body_exited"):
		connect("body_exited", self, "_on_body_exited")
	if has_node("/root/GravityWorld"):
		get_node("/root/GravityWorld").register_zone(self)
	if OS.is_debug_build():
		_update_debug_mesh()

func _exit_tree() -> void:
	if has_node("/root/GravityWorld"):
		get_node("/root/GravityWorld").unregister_zone(self)

func _process(_delta: float) -> void:
	if Engine.editor_hint:
		_update_debug_mesh()

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
		elif shape_node.shape is CylinderShape:
			var cylinder: CylinderShape = shape_node.shape as CylinderShape
			var half_height: float = cylinder.height * 0.5
			if abs(local.y) <= half_height and Vector2(local.x, local.z).length() <= cylinder.radius:
				return true
	return false

func get_volume() -> float:
	var volume: float = INF
	for child in get_children():
		if child is CollisionShape and (child as CollisionShape).shape is BoxShape:
			var extents: Vector3 = ((child as CollisionShape).shape as BoxShape).extents
			volume = min(volume, extents.x * extents.y * extents.z * 8.0)
		elif child is CollisionShape and (child as CollisionShape).shape is SphereShape:
			var radius: float = ((child as CollisionShape).shape as SphereShape).radius
			volume = min(volume, (4.0 / 3.0) * PI * radius * radius * radius)
		elif child is CollisionShape and (child as CollisionShape).shape is CylinderShape:
			var cylinder: CylinderShape = (child as CollisionShape).shape as CylinderShape
			volume = min(volume, PI * cylinder.radius * cylinder.radius * cylinder.height)
	return volume

func allows_coriolis() -> bool:
	return allow_coriolis

func affects_props() -> bool:
	return affect_props

func set_debug_color(val: Color) -> void:
	debug_color = val
	_update_debug_mesh()

func set_debug_render(val: bool) -> void:
	debug_render = val
	_update_debug_mesh()

func _find_collision_shape() -> CollisionShape:
	for child in get_children():
		if child is CollisionShape:
			return child
	return null

func _update_debug_mesh() -> void:
	if not Engine.editor_hint and not OS.is_debug_build():
		if has_node("_ZoneDebugMesh"):
			get_node("_ZoneDebugMesh").visible = false
		return

	if not debug_render:
		if has_node("_ZoneDebugMesh"):
			get_node("_ZoneDebugMesh").visible = false
		return

	var shape_node := _find_collision_shape()
	if shape_node == null or shape_node.shape == null:
		if has_node("_ZoneDebugMesh"):
			get_node("_ZoneDebugMesh").visible = false
		return

	var mesh_inst: MeshInstance = null
	if has_node("_ZoneDebugMesh"):
		mesh_inst = get_node("_ZoneDebugMesh")
	else:
		mesh_inst = MeshInstance.new()
		mesh_inst.name = "_ZoneDebugMesh"
		mesh_inst.cast_shadow = MeshInstance.SHADOW_CASTING_SETTING_OFF
		add_child(mesh_inst)
		mesh_inst.owner = null

	var shape := shape_node.shape
	if shape is BoxShape:
		if not mesh_inst.mesh is CubeMesh:
			mesh_inst.mesh = CubeMesh.new()
		(mesh_inst.mesh as CubeMesh).size = (shape as BoxShape).extents * 2.0
	elif shape is SphereShape:
		if not mesh_inst.mesh is SphereMesh:
			mesh_inst.mesh = SphereMesh.new()
		var sphere_mesh: SphereMesh = mesh_inst.mesh as SphereMesh
		sphere_mesh.radius = (shape as SphereShape).radius
		sphere_mesh.height = (shape as SphereShape).radius * 2.0
	elif shape is CylinderShape:
		if not mesh_inst.mesh is CylinderMesh:
			mesh_inst.mesh = CylinderMesh.new()
		var cylinder_shape: CylinderShape = shape as CylinderShape
		var cylinder_mesh: CylinderMesh = mesh_inst.mesh as CylinderMesh
		cylinder_mesh.top_radius = cylinder_shape.radius
		cylinder_mesh.bottom_radius = cylinder_shape.radius
		cylinder_mesh.height = cylinder_shape.height
	else:
		mesh_inst.visible = false
		return

	var mat := SpatialMaterial.new()
	mat.flags_transparent = true
	mat.flags_unshaded = true
	mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
	mat.albedo_color = debug_color
	mesh_inst.material_override = mat
	mesh_inst.global_transform = shape_node.global_transform
	mesh_inst.visible = true

func _on_body_entered(body: Node) -> void:
	print("[ZeroGravityZone] Body entered: ", body.name)
	if not body.is_in_group("player"):
		return
	emit_signal("gravity_zone_changed", body, GravityModes.Mode.ZERO_G)
	_notify_controller_gravity_mode(body, GravityModes.Mode.ZERO_G)

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	emit_signal("gravity_zone_changed", body, GravityModes.Mode.STANDARD_1G)
	_notify_controller_gravity_mode(body, GravityModes.Mode.STANDARD_1G)

func _notify_controller_gravity_mode(body: Node, mode: int) -> void:
	var cm = body.get_node_or_null("ControllerManager")
	if cm == null:
		return
	
	if not is_connected("gravity_zone_changed", cm, "_on_gravity_zone_changed"):
		connect("gravity_zone_changed", cm, "_on_gravity_zone_changed")
		
	if cm.has_method("set_gravity_mode"):
		cm.set_gravity_mode(mode)
	elif cm.has_method("switch_to"):
		cm.switch_to(cm.get_controller_mode_for_gravity_mode(mode))
