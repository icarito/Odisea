tool
extends BaseZoneV2
class_name CinematicCameraZoneV2

# CinematicCameraZone.gd - Trigger zone to activate a cinematic rig
# Permite referenciar directamente el CinematicRig desde el Inspector.

# Referencia directa al rig (arrastra el nodo desde el árbol)
export(NodePath) var cinematic_rig_path: NodePath
export(CinematicManager.ControlMode) var control_mode = CinematicManager.ControlMode.LOCKED_VIEW
export(bool) var use_occlusion := false
export(float) var occlusion_cone_radius: float = 1.5
export(float, 0.0, 2.0) var occlusion_blur_softness: float = 0.8
export(float, 0.1, 3.0) var occlusion_edge_fade: float = 1.2
export(float, 0.0, 1.0) var occlusion_transparency_min: float = 0.3
export(float, 0.0, 1.0) var occlusion_transparency_max: float = 0.95
export(float, 0.5, 5.0) var occlusion_floor_protect_radius: float = 2.0
export(bool) var enforce_occlusion_material: bool = false
export(NodePath) var occlusion_root = @".."
export(Shader) var custom_occlusion_shader

# --- Direction Latch Control ---
export(bool) var latch_on_enter := true # Si true, activa el latch de dirección al entrar a la zona
export(bool) var latch_on_exit := true # Si true, activa el latch de dirección al salir de la zona
export(Vector3) var track_axis := Vector3.RIGHT # Eje principal de movimiento 2.5D

# Cached reference (may be any Node; CinematicRigV2 is a Spatial)
var _rig_node: Node = null

# Runtime control: allows external systems (like HoloTerminal) to enable/disable this zone
var is_zone_active: bool = true

func _ready():
	# Llamar primero a la lógica base de BaseZoneV2
	._ready()
	add_to_group("CinematicCameraZoneV2")
	
	# Color naranja para zonas cinemáticas
	if debug_color == Color(0, 1, 0, 0.2):
		set_debug_color(Color(1.0, 0.5, 0.0, 0.3))
	
	# Auto-setup: crear CollisionShape si no existe (también en editor para visualización)
	_ensure_collision_shape()
	# Cache rig deterministically at ready
	_cache_rig()
	if not Engine.editor_hint and use_occlusion and enforce_occlusion_material:
		_apply_occlusion_enforcement()

func _ensure_collision_shape():
	"""Crea un CollisionShape automáticamente si la zona no tiene uno."""
	var has_shape := false
	for child in get_children():
		if child is CollisionShape:
			has_shape = true
			break
	
	if not has_shape:
		var shape_node = CollisionShape.new()
		shape_node.name = "CollisionShape"
		var box = BoxShape.new()
		box.extents = zone_extents
		shape_node.shape = box
		add_child(shape_node)

func _find_rig_in_children(node: Node) -> Node:
	"""Busca recursivamente un CinematicRigV2 entre los hijos."""
	if node is CinematicRigV2:
		return node
	for child in node.get_children():
		var found = _find_rig_in_children(child)
		if found:
			return found
	return null

func _cache_rig():
	"""Cachea la referencia al rig para evitar búsquedas repetidas.
	Si no hay `cinematic_rig_path`, intenta buscar un CinematicRigV2 entre sus hijos."""
	_rig_node = null
	# Primero intentar por path explícito
	if cinematic_rig_path and not cinematic_rig_path.is_empty():
		_rig_node = get_node_or_null(cinematic_rig_path)
		if _rig_node:
			return
		else:
			printerr("[CinematicCameraZone] Rig no encontrado en path: ", cinematic_rig_path)

	# Buscar en hijos/descendientes
	var found = _find_rig_in_children(self)
	if found:
		_rig_node = found
		cinematic_rig_path = _rig_node.get_path()
		print("[CinematicCameraZone] Auto-linked cinematic rig: ", _rig_node.name)
		return
	
	# Como último recurso, buscar rig en escena por grupo (legacy)
	var rigs = get_tree().get_nodes_in_group("cinematic_rigs")
	if rigs.size() == 1:
		_rig_node = rigs[0]
		cinematic_rig_path = _rig_node.get_path()
		print("[CinematicCameraZone] Linked single cinematic rig in scene: ", _rig_node.name)

func _on_zone_entered(_body: Node):
	# Rig activation now handled by PlayerController for determinism
	pass

func _on_zone_exited(_body: Node):
	# Rig deactivation now handled by PlayerController for determinism
	pass

func set_zone_occlusion_for_body(body: Node, active: bool) -> void:
	if not use_occlusion:
		return
	WallOcclusionManager.set_occlusion_params(active, occlusion_cone_radius, {
		"blur_softness": occlusion_blur_softness,
		"edge_fade": occlusion_edge_fade,
		"transparency_min": occlusion_transparency_min,
		"transparency_max": occlusion_transparency_max,
		"floor_protect_radius": occlusion_floor_protect_radius
	} if active else {})
	if is_instance_valid(body) and body.has_method("set_occlusion_mode"):
		body.set_occlusion_mode(active)

func _apply_occlusion_enforcement() -> void:
	var root = get_node_or_null(occlusion_root)
	if not root:
		print("[CinematicCameraZone] Occlusion root inválido: ", occlusion_root)
		return
	var shader_to_use = custom_occlusion_shader
	if not shader_to_use:
		shader_to_use = load("res://shaders/dither_hiding.shader")
	_recursive_apply_occlusion(root, shader_to_use)

func _is_part_of_player(node: Node) -> bool:
	var curr = node
	while curr != null:
		if curr.is_in_group("player"):
			return true
		curr = curr.get_parent()
	return false

func _recursive_apply_occlusion(node: Node, shader: Shader) -> void:
	if node == self or node.is_in_group("player") or _is_part_of_player(node):
		return
	if node.is_in_group("no_occlusion"):
		return
	if node is MeshInstance:
		_process_mesh_instance_occlusion(node, shader)
	elif node is CSGShape:
		_process_csg_occlusion(node, shader)
	for child in node.get_children():
		_recursive_apply_occlusion(child, shader)

func _process_mesh_instance_occlusion(mesh: MeshInstance, shader: Shader) -> void:
	var mat_override = mesh.material_override
	if mat_override:
		mesh.material_override = _convert_material_occlusion(mat_override, shader)
		if mesh.material_override is ShaderMaterial:
			WallOcclusionManager.register_material(mesh.material_override)

	var surface_count = mesh.get_surface_material_count()
	for i in range(surface_count):
		var mat_surface = mesh.get_active_material(i)
		if mat_surface:
			var new_mat = _convert_material_occlusion(mat_surface, shader)
			mesh.set_surface_material(i, new_mat)
			if new_mat is ShaderMaterial:
				WallOcclusionManager.register_material(new_mat)

func _process_csg_occlusion(csg: CSGShape, shader: Shader) -> void:
	var mat = csg.material
	if mat:
		csg.material = _convert_material_occlusion(mat, shader)
		if csg.material is ShaderMaterial:
			WallOcclusionManager.register_material(csg.material)

func _convert_material_occlusion(source_mat: Material, shader: Shader) -> Material:
	if source_mat is ShaderMaterial:
		if source_mat.shader == shader:
			return source_mat

	var new_mat = ShaderMaterial.new()
	new_mat.shader = shader

	if source_mat is SpatialMaterial:
		new_mat.set_shader_param("albedo", source_mat.albedo_color)
		if source_mat.albedo_texture:
			new_mat.set_shader_param("texture_albedo", source_mat.albedo_texture)

		new_mat.set_shader_param("roughness", source_mat.roughness)
		new_mat.set_shader_param("metallic", source_mat.metallic)
		new_mat.set_shader_param("specular", source_mat.metallic_specular)
		new_mat.set_shader_param("uv1_scale", source_mat.uv1_scale)
		new_mat.set_shader_param("uv1_offset", source_mat.uv1_offset)

		if source_mat.flags_world_triplanar or source_mat.uv1_triplanar:
			new_mat.set_shader_param("uv1_triplanar", true)
			new_mat.set_shader_param("uv1_blend_sharpness", source_mat.uv1_triplanar_sharpness)

	return new_mat
