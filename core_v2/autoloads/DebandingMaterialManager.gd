extends Node

const DEBANDING_SHADER_PATH := "res://debandingmaterial.shader"
const DITHER_ENV := "ODISEA_DEBANDING_DITHER"

var _shader: Shader = null
var _converted_cache := {}

func _ready() -> void:
	_shader = load(DEBANDING_SHADER_PATH) as Shader
	if _shader == null:
		push_warning("[DebandingMaterialManager] Missing shader at %s" % DEBANDING_SHADER_PATH)
		return
	call_deferred("_apply_to_current_scene")

func _apply_to_current_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_apply_to_subtree(scene)

func _apply_to_subtree(root: Node) -> void:
	if root == null:
		return
	for node in _walk_nodes(root):
		if node is MeshInstance and _should_apply_to_mesh(node):
			_apply_debanding_to_mesh_instance(node)
		elif node is CSGShape and _should_apply_to_csg(node):
			_apply_debanding_to_csg(node)

func _walk_nodes(root: Node) -> Array:
	var out := []
	var stack := [root]
	while not stack.empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for c in node.get_children():
			stack.append(c)
	return out

func _should_apply_to_mesh(node: MeshInstance) -> bool:
	if node.is_in_group("deband_target"):
		return true
	var p: Node = node
	while p != null:
		if p.name == "QodotMap":
			return true
		p = p.get_parent()
	return false

func _should_apply_to_csg(node: CSGShape) -> bool:
	return node.is_in_group("deband_target")

func _apply_debanding_to_mesh_instance(mesh_instance: MeshInstance) -> void:
	if mesh_instance.material_override is SpatialMaterial:
		var override_mat: SpatialMaterial = mesh_instance.material_override
		if not override_mat.flags_transparent:
			mesh_instance.material_override = _to_deband_material(override_mat)

	var mesh := mesh_instance.mesh
	if mesh == null:
		return
	for i in range(mesh.get_surface_count()):
		var mat := mesh.surface_get_material(i)
		if mat is SpatialMaterial:
			var src: SpatialMaterial = mat
			if not src.flags_transparent:
				mesh.surface_set_material(i, _to_deband_material(src))

func _apply_debanding_to_csg(csg: CSGShape) -> void:
	if csg.material is SpatialMaterial:
		var src: SpatialMaterial = csg.material
		if not src.flags_transparent:
			csg.material = _to_deband_material(src)

func _to_deband_material(src: SpatialMaterial) -> ShaderMaterial:
	var key := src.get_instance_id()
	if _converted_cache.has(key):
		return _converted_cache[key]

	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.resource_local_to_scene = true

	mat.set_shader_param("albedo", src.albedo_color)
	mat.set_shader_param("specular", float(src.metallic_specular))
	mat.set_shader_param("metallic", float(src.metallic))
	mat.set_shader_param("roughness", float(src.roughness))
	mat.set_shader_param("roughness_texture_channel", _roughness_channel_mask(src))
	mat.set_shader_param("debanding_dither", _get_dither_value())

	if src.albedo_texture:
		mat.set_shader_param("texture_albedo", src.albedo_texture)
	if src.roughness_texture:
		mat.set_shader_param("texture_roughness", src.roughness_texture)
	if src.emission_texture:
		mat.set_shader_param("texture_emission", src.emission_texture)

	var emission_energy := src.emission_energy if src.emission_enabled else 0.0
	mat.set_shader_param("emission_energy", emission_energy)
	if src.emission_enabled:
		mat.set_shader_param("emission", src.emission)

	_converted_cache[key] = mat
	return mat

func _get_dither_value() -> float:
	var env_value := OS.get_environment(DITHER_ENV)
	if env_value == "":
		return 0.0018
	var parsed := float(env_value)
	return clamp(parsed, 0.0, 0.02)

func _roughness_channel_mask(src: SpatialMaterial) -> Color:
	var channel := int(src.get("roughness_texture_channel"))
	match channel:
		1:
			return Color(0.0, 1.0, 0.0, 0.0)
		2:
			return Color(0.0, 0.0, 1.0, 0.0)
		3:
			return Color(0.0, 0.0, 0.0, 1.0)
		_:
			return Color(1.0, 0.0, 0.0, 0.0)
