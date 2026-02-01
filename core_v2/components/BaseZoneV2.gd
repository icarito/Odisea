tool
extends Area
class_name BaseZoneV2

# Exporting debug color for easier configuration in editor
export(Color) var debug_color: Color = Color(0.0, 1.0, 0.0, 0.2) setget set_debug_color
export(bool) var debug_render: bool = true setget set_debug_render
export(Vector3) var zone_extents: Vector3 = Vector3(1, 1, 1) setget set_zone_extents

# Internal reference to the Area node providing collision
var _host_area: Area = null

func _ready():
	_find_and_setup_host()
	if Engine.editor_hint or OS.is_debug_build():
		_update_debug_mesh()

func _find_and_setup_host():
	if self is Area:
		_host_area = self
	elif get_parent() is Area:
		_host_area = get_parent() as Area
	
	if _host_area and _host_area is Object and _host_area is Node:
		# Ensure unique collision shape resource so resizing one doesn't affect others sharing the same resource
		for child in _host_area.get_children():
			if child is CollisionShape and child.shape is BoxShape:
				child.shape = child.shape.duplicate()
				child.shape.extents = zone_extents

		if not Engine.editor_hint:
			if not _host_area.is_connected("body_entered", self, "_on_host_body_entered"):
				_host_area.connect("body_entered", self, "_on_host_body_entered")
			if not _host_area.is_connected("body_exited", self, "_on_host_body_exited"):
				_host_area.connect("body_exited", self, "_on_host_body_exited")
	else:
		if not Engine.editor_hint:
			printerr("[BaseZoneV2] WARNING: ", name, " has no Area host (self or parent).")

func _on_host_body_entered(body: Node):
	if body.is_in_group("player"):
		_on_zone_entered(body)

func _on_host_body_exited(body: Node):
	if body.is_in_group("player"):
		_on_zone_exited(body)

# Virtual methods to be overridden by subclasses
func _on_zone_entered(_body: Node):
	pass

func _on_zone_exited(_body: Node):
	pass

# --- Debug Visualization ---

func set_debug_color(val: Color):
	debug_color = val
	_update_debug_mesh()

func set_debug_render(val: bool):
	debug_render = val
	_update_debug_mesh()

func set_zone_extents(val: Vector3):
	zone_extents = val
	var shape_node = _find_collision_shape()
	if shape_node and shape_node.shape is BoxShape:
		shape_node.shape.extents = zone_extents
	_update_debug_mesh()

func _process(_delta):
	if Engine.editor_hint:
		_check_parent_sync()
		_update_debug_mesh()

func _check_parent_sync():
	var parent = get_parent()
	if parent and parent.has_method("_find_collision_shape"):
		var p_extents = parent.get("zone_extents")
		if p_extents is Vector3:
			if zone_extents != p_extents:
				set_zone_extents(p_extents)
				property_list_changed_notify()

func _find_collision_shape() -> CollisionShape:
	if not _host_area or not (_host_area is Object) or not (_host_area is Node):
		return null
	for child in _host_area.get_children():
		if child is CollisionShape:
			return child
	return null

func _update_debug_mesh():
	if not Engine.editor_hint and not OS.is_debug_build():
		if has_node("_ZoneDebugMesh"):
			get_node("_ZoneDebugMesh").visible = false
		return

	if not debug_render:
		if has_node("_ZoneDebugMesh"):
			get_node("_ZoneDebugMesh").visible = false
		return

	var mesh_inst: MeshInstance
	if has_node("_ZoneDebugMesh"):
		mesh_inst = get_node("_ZoneDebugMesh")
	else:
		mesh_inst = MeshInstance.new()
		mesh_inst.name = "_ZoneDebugMesh"
		mesh_inst.cast_shadow = MeshInstance.SHADOW_CASTING_SETTING_OFF
		add_child(mesh_inst)
		mesh_inst.owner = null

	var shape: CollisionShape = _find_collision_shape()
	
	if shape and shape.shape is BoxShape:
		var box: BoxShape = shape.shape
		if not mesh_inst.mesh is CubeMesh:
			mesh_inst.mesh = CubeMesh.new()
		
		var cube: CubeMesh = mesh_inst.mesh
		cube.size = box.extents * 2.0
		
		# Match global transform exactly
		mesh_inst.global_transform = shape.global_transform
	
	var mat = SpatialMaterial.new()
	mat.flags_transparent = true
	mat.flags_unshaded = true
	mat.albedo_color = debug_color
	mesh_inst.material_override = mat
	mesh_inst.visible = true

func _get_configuration_warning():
	if not (self is Area or get_parent() is Area):
		return "This node must either be an Area or a child of an Area to function as a Zone."
	return ""
