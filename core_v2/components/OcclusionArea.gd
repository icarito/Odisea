tool
extends Area

export(float) var cone_radius: float = 1.5
export(float) var camera_distance_override: float = -1.0 # -1 to ignore
export(bool) var debug_render: bool = true setget set_debug_render
# --- Material Enforcement ---
export(bool) var enforce_occlusion_material: bool = false
export(NodePath) var occlusion_target_path = @".."
export(Shader) var custom_occlusion_shader


func set_debug_render(val):
	debug_render = val
	if has_node("DebugMesh"):
		get_node("DebugMesh").visible = val

func _ready():
	if not Engine.editor_hint:
		connect("body_entered", self, "_on_body_entered")
		connect("body_exited", self, "_on_body_exited")
		
		if enforce_occlusion_material:
			_apply_enforcement()

func _on_body_entered(body):
	if body.is_in_group("player"):
		WallOcclusionManager.set_occlusion_params(true, cone_radius)
		if body.has_method("set_occlusion_mode"):
			body.set_occlusion_mode(true)
		print("[OcclusionArea] Body entered: ", body.name, " Active count: ", WallOcclusionManager.registered_materials.size())


func _on_body_exited(body):
	if body.is_in_group("player"):
		WallOcclusionManager.set_occlusion_params(false, cone_radius)
		if body.has_method("set_occlusion_mode"):
			body.set_occlusion_mode(false)

func _apply_enforcement():
	var root = get_node_or_null(occlusion_target_path)
	if not root:
		print("[OcclusionArea] Target path invalid: ", occlusion_target_path)
		return
		
	var shader_to_use = custom_occlusion_shader
	if not shader_to_use:
		shader_to_use = load("res://shaders/dither_hiding.shader")
	print("[OcclusionArea] Applying enforcement starting from target: ", root.name)
	_recursive_apply(root, shader_to_use)


func _recursive_apply(node: Node, shader: Shader):
	# SKIP PLAYER and the Area itself
	if node.is_in_group("player") or node == self:
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
		
		print("[OcclusionArea] Converted SpatialMaterial to ShaderMaterial for mesh/shape.")
		
	return new_mat

# --- Debug Visualization ---
func _process(_delta):
	if Engine.editor_hint or OS.is_debug_build():
		if debug_render:
			if not has_node("DebugMesh"):
				_create_debug_mesh()
			else:
				_update_debug_mesh()
		elif has_node("DebugMesh"):
			get_node("DebugMesh").queue_free()

func _update_debug_mesh():
	var mesh_inst = get_node("DebugMesh")
	var shape = null
	for child in get_children():
		if child is CollisionShape:
			shape = child.shape
			break
			
	if shape and shape is BoxShape:
		if not mesh_inst.mesh is CubeMesh:
			mesh_inst.mesh = CubeMesh.new()
		
		var target_size = shape.extents * 2
		if mesh_inst.mesh.size != target_size:
			mesh_inst.mesh.size = target_size

func _enter_tree():
	if Engine.editor_hint or OS.is_debug_build():
		_create_debug_mesh()

func _create_debug_mesh():
	if not debug_render: return
	if has_node("DebugMesh"): return
	
	var mesh_inst = MeshInstance.new()
	mesh_inst.name = "DebugMesh"
	
	var mat = SpatialMaterial.new()
	mat.albedo_color = Color(1, 1, 0, 0.2) # Yellow, transparent
	mat.flags_transparent = true
	mat.flags_unshaded = true
	mesh_inst.material_override = mat
	
	add_child(mesh_inst)
	_update_debug_mesh()
