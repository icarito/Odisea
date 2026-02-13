tool
extends Area
class_name BaseZone

# Exporting debug color for easier configuration in editor
export(Color) var debug_color: Color = Color(0.0, 1.0, 0.0, 0.2) setget set_debug_color
export(bool) var debug_render: bool = true setget set_debug_render
export(Vector3) var zone_extents: Vector3 = Vector3(1, 1, 1) setget set_zone_extents

# Internal reference to the Area node providing collision
var _host_area: Area = null

# Track bodies currently in zone (more reliable than overlaps_body during physics sync)
var _bodies_in_zone: Dictionary = {}

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
				# If we are at default value and child has a different one, adopt it
				if zone_extents == Vector3(1, 1, 1) and child.shape.extents != Vector3(1, 1, 1):
					zone_extents = child.shape.extents
				else:
					child.shape.extents = zone_extents

		if not Engine.editor_hint:
			if not _host_area.is_connected("body_entered", self, "_on_host_body_entered"):
				_host_area.connect("body_entered", self, "_on_host_body_entered")
			if not _host_area.is_connected("body_exited", self, "_on_host_body_exited"):
				_host_area.connect("body_exited", self, "_on_host_body_exited")
	else:
		if not Engine.editor_hint:
			printerr("[BaseZone] WARNING: ", name, " has no Area host (self or parent).")

func _on_host_body_entered(body: Node):
	if body.is_in_group("player"):
		print("DEBUG BASEZONE: Body Entered: ", body.name, " Zone: ", self.name)
		_on_zone_entered(body)
	_bodies_in_zone[body.get_instance_id()] = body

func _on_host_body_exited(body: Node):
	if body.is_in_group("player"):
		print("DEBUG BASEZONE: Body Exited: ", body.name, " Zone: ", self.name)
		_on_zone_exited(body)
	_bodies_in_zone.erase(body.get_instance_id())

# Virtual methods to be overridden by subclasses
func _on_zone_entered(_body: Node):
	pass

func _on_zone_exited(_body: Node):
	pass

func is_body_in_zone(body: Node) -> bool:
	# Use signal-tracked dictionary for reliability (overlaps_body has timing issues)
	return _bodies_in_zone.has(body.get_instance_id())

func get_volume() -> float:
	"""Returns the volume of the zone for priority comparison. Smaller = innermost."""
	return zone_extents.x * zone_extents.y * zone_extents.z * 8.0 # *8 for full box volume

# --- Debug Visualization ---

func set_debug_color(val: Color):
	debug_color = val
	_update_debug_mesh()

func set_debug_render(val: bool):
	debug_render = val
	_update_debug_mesh()

func set_zone_extents(val: Vector3):
	zone_extents = val
	# En el editor, buscar el CollisionShape directamente sin depender de _host_area
	var shape_node = _find_collision_shape_direct()
	if shape_node and shape_node.shape is BoxShape:
		# Solo duplicar una vez si no es local_to_scene
		if not shape_node.shape.resource_local_to_scene:
			var new_shape = BoxShape.new()
			new_shape.extents = zone_extents
			new_shape.resource_local_to_scene = true
			shape_node.shape = new_shape
		else:
			shape_node.shape.extents = zone_extents
	_update_debug_mesh()

# Busca CollisionShape directamente, sin depender de _host_area (para el editor)
func _find_collision_shape_direct() -> CollisionShape:
	# Primero buscar en self (si es Area)
	if self is Area:
		for child in get_children():
			if child is CollisionShape:
				return child
	# Luego buscar en parent (si es Area)
	var parent = get_parent()
	if parent and parent is Area:
		for child in parent.get_children():
			if child is CollisionShape:
				return child
	# Fallback al método original
	return _find_collision_shape()

func _process(_delta):
	if Engine.editor_hint:
		_check_parent_sync()
		_sync_extents_from_shape()
		_update_debug_mesh()

# Sincroniza zone_extents desde el CollisionShape (para cuando el usuario edita el shape directamente)
func _sync_extents_from_shape():
	var shape_node = _find_collision_shape_direct()
	if shape_node and shape_node.shape is BoxShape:
		var shape_extents = shape_node.shape.extents
		if zone_extents != shape_extents:
			zone_extents = shape_extents
			property_list_changed_notify()

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
