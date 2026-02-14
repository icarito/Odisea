tool
extends BaseZoneV2
class_name OcclusionZoneV2

export(float) var cone_radius: float = 1.5
export(float) var camera_distance_override: float = -1.0 # -1 to ignore
# --- Shader Effect Controls ---
export(float, 0.0, 2.0) var blur_softness: float = 0.8
export(float, 0.1, 3.0) var edge_fade: float = 1.2
export(float, 0.0, 1.0) var transparency_min: float = 0.3
export(float, 0.0, 1.0) var transparency_max: float = 0.95
export(float, 0.5, 5.0) var floor_protect_radius: float = 2.0
# --- Material Enforcement ---
export(bool) var enforce_occlusion_material: bool = false
export(NodePath) var occlusion_target_path = @".."
export(Shader) var custom_occlusion_shader

func _ready():
	add_to_group("OcclusionZoneV2")
	if not Engine.editor_hint:
		push_warning("[DEPRECATED] OcclusionZoneV2 está deprecada. Usa CinematicCameraZoneV2 con use_occlusion=true.")
	if debug_color == Color(0, 1, 0, 0.2): # Only if default
		set_debug_color(Color(1.0, 1.0, 0.0, 0.2)) # Yellow
		
	if not Engine.editor_hint:
		if enforce_occlusion_material:
			_apply_enforcement()

func _on_zone_entered(body: Node):
	WallOcclusionManager.set_occlusion_params(true, cone_radius, {
		"blur_softness": blur_softness,
		"edge_fade": edge_fade,
		"transparency_min": transparency_min,
		"transparency_max": transparency_max,
		"floor_protect_radius": floor_protect_radius
	})
	if body.has_method("set_occlusion_mode"):
		body.set_occlusion_mode(true)
	print("[OcclusionZoneV2] Body entered: ", body.name, " Active count: ", WallOcclusionManager.registered_materials.size())

func _on_zone_exited(body: Node):
	WallOcclusionManager.set_occlusion_params(false, cone_radius, {})
	if body.has_method("set_occlusion_mode"):
		body.set_occlusion_mode(false)

func _apply_enforcement():
	var root = get_node_or_null(occlusion_target_path)
	if not root:
		print("[OcclusionZoneV2] Target path invalid: ", occlusion_target_path)
		return
		
	var shader_to_use = custom_occlusion_shader
	if not shader_to_use:
		shader_to_use = load("res://shaders/dither_hiding.shader")
	print("[OcclusionZoneV2] Applying enforcement starting from target: ", root.name)
	_recursive_apply(root, shader_to_use)

func _is_part_of_player(node: Node) -> bool:
	var curr = node
	while curr != null:
		if curr.is_in_group("player"):
			return true
		curr = curr.get_parent()
	return false

func _recursive_apply(node: Node, shader: Shader):
	# Robust skip for player and its children
	if node == self or node.is_in_group("player") or _is_part_of_player(node):
		return
	
	# Skip nodes in the no_occlusion group
	if node.is_in_group("no_occlusion"):
		return
		
	if node is MeshInstance:
		_process_mesh_instance(node, shader)
	elif node is CSGShape:
		_process_csg(node, shader)
		
	for child in node.get_children():
		_recursive_apply(child, shader)

func _process_mesh_instance(mesh: MeshInstance, shader: Shader):
	# Check surface override
	var mat_override = mesh.material_override
	if mat_override:
		mesh.material_override = _convert_material(mat_override, shader)
		if mesh.material_override is ShaderMaterial:
			WallOcclusionManager.register_material(mesh.material_override)
	
	# Check all surface materials
	var surface_count = mesh.get_surface_material_count()
	for i in range(surface_count):
		var mat_surface = mesh.get_active_material(i)
		if mat_surface:
			var new_mat = _convert_material(mat_surface, shader)
			mesh.set_surface_material(i, new_mat)
			if new_mat is ShaderMaterial:
				WallOcclusionManager.register_material(new_mat)

func _process_csg(csg: CSGShape, shader: Shader):
	var mat = csg.material
	if mat:
		csg.material = _convert_material(mat, shader)
		if csg.material is ShaderMaterial:
			WallOcclusionManager.register_material(csg.material)

func _convert_material(source_mat: Material, shader: Shader) -> Material:
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
		
		# UV Scale/Offset
		new_mat.set_shader_param("uv1_scale", source_mat.uv1_scale)
		new_mat.set_shader_param("uv1_offset", source_mat.uv1_offset)
		
		# Triplanar Logic
		if source_mat.flags_world_triplanar or source_mat.uv1_triplanar:
			new_mat.set_shader_param("uv1_triplanar", true)
			new_mat.set_shader_param("uv1_blend_sharpness", source_mat.uv1_triplanar_sharpness)
		
	return new_mat
