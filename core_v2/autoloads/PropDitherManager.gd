# PropDitherManager.gd
# Autoload singleton that automatically applies the dither occlusion shader
# to all layer 7 (Props) MeshInstance nodes. Updates player_pos/camera_pos
# uniforms each frame so the shader can compute cone-based dithering.
#
# Props are detected by scanning for StaticBody nodes with collision_layer & 64.
# Their child MeshInstance SpatialMaterials are converted to ShaderMaterial.
# Nodes in group "no_occlusion" are skipped.

extends Node

const PROP_LAYER_BIT: int = 64  # Layer 7

var _dither_shader: Shader = preload("res://shaders/prop_dither_occlusion.gdshader")
var _parallax_shader: Shader = preload("res://core_v2/props/parallax_assets/card_parallax.shader")
var _registered_materials: Array = []
var _processed_meshes: Dictionary = {}  # MeshInstance -> true (avoid double-processing)

var _player_node: Spatial = null
var _camera_node: Camera = null

# Shader effect parameters (can be tuned via set_occlusion_params)
var _hole_radius: float = 0.5
var _shader_params: Dictionary = {
	"blur_softness": 0.5,
	"edge_fade": 1.0,
	"transparency_min": 0.3,
	"transparency_max": 0.95,
	"floor_protect_radius": 1.0
}

func _ready() -> void:
	# Defer scan to let the scene tree finish loading
	call_deferred("_scan_scene_tree")
	# Watch for new nodes added later (streaming, instancing, etc.)
	get_tree().connect("node_added", self, "_on_node_added")


func _process(_delta: float) -> void:
	if _registered_materials.empty():
		return

	if not is_instance_valid(_player_node):
		if is_instance_valid(SessionManager.player):
			_player_node = SessionManager.player

	_camera_node = get_viewport().get_camera()

	if not is_instance_valid(_player_node) or not is_instance_valid(_camera_node):
		return

	var p_pos: Vector3 = _player_node.global_transform.origin + Vector3(0, 1.2, 0)
	var c_pos: Vector3 = _camera_node.global_transform.origin

	var living: Array = []
	for mat in _registered_materials:
		if is_instance_valid(mat):
			mat.set_shader_param("player_pos", p_pos)
			mat.set_shader_param("camera_pos", c_pos)
			mat.set_shader_param("is_active", 1.0)
			mat.set_shader_param("hole_radius", _hole_radius)
			for key in _shader_params:
				mat.set_shader_param(key, _shader_params[key])
			living.append(mat)
	_registered_materials = living


func set_occlusion_params(radius: float, params: Dictionary = {}) -> void:
	_hole_radius = radius
	for key in params:
		_shader_params[key] = params[key]


func register_material(mat: ShaderMaterial) -> void:
	if mat and not _registered_materials.has(mat):
		_registered_materials.append(mat)


# --- Scene scanning --------------------------------------------------------

func _scan_scene_tree() -> void:
	_scan_node(get_tree().root)


func _on_node_added(node: Node) -> void:
	# Process CollisionObject nodes on the prop layer (StaticBody or KinematicBody)
	if node is CollisionObject:
		var co := node as CollisionObject
		if co.collision_layer & PROP_LAYER_BIT:
			# Skip the player
			if co.is_in_group("player"):
				return
			# Defer to let all children be added to the tree
			call_deferred("_process_collision_object", co)


func _scan_node(node: Node) -> void:
	if node is CollisionObject:
		var co := node as CollisionObject
		if co.collision_layer & PROP_LAYER_BIT and not co.is_in_group("player"):
			_process_collision_object(co)

	for child in node.get_children():
		_scan_node(child)


func _process_collision_object(co: CollisionObject) -> void:
	if not is_instance_valid(co):
		return
	# Keep default lighting/shadow behavior for Qodot world geometry.
	if _is_under_qodot_map(co):
		return
	var prop_root: Node = _get_occlusion_root_for_collision_object(co)
	_convert_meshes_recursive(prop_root)


func _is_under_qodot_map(node: Node) -> bool:
	var current: Node = node
	while current != null:
		if current.get_class() == "QodotMap":
			return true
		current = current.get_parent()
	return false


func _get_occlusion_root_for_collision_object(co: CollisionObject) -> Node:
	if _has_mesh_descendant(co):
		return co

	var parent := co.get_parent()
	if parent == null:
		return co

	# Qodot func_group StaticBodies can live directly under the map root. Using
	# their parent would convert the whole level mesh and visibly dither floors.
	if parent.get_class() == "QodotSpatial":
		return co

	return parent


func _has_mesh_descendant(node: Node) -> bool:
	for child in node.get_children():
		if child is MeshInstance:
			return true
		if _has_mesh_descendant(child):
			return true
	return false


func _convert_meshes_recursive(node: Node) -> void:
	if not is_instance_valid(node):
		return
	# Skip player and their children
	if node.is_in_group("player"):
		return
	# Skip nodes tagged no_occlusion
	if node.is_in_group("no_occlusion"):
		return
	# Skip KinematicBody branches that are NOT on the prop layer (other actors)
	if node is KinematicBody:
		var kb := node as KinematicBody
		if not (kb.collision_layer & PROP_LAYER_BIT):
			return

	if node is MeshInstance:
		_convert_mesh_instance(node as MeshInstance)

	for child in node.get_children():
		_convert_meshes_recursive(child)


func _convert_mesh_instance(mesh: MeshInstance) -> void:
	if _processed_meshes.has(mesh):
		return
	_processed_meshes[mesh] = true

	# Convert material_override if it's a SpatialMaterial
	var mat_override = mesh.material_override
	if mat_override is SpatialMaterial and _can_apply_occlusion_dither(mat_override as SpatialMaterial):
		mesh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		var new_mat = _convert_spatial_to_dither(mat_override as SpatialMaterial)
		mesh.material_override = new_mat
		register_material(new_mat)
		return  # Override takes priority, no need to process surfaces
	elif mat_override is ShaderMaterial and (mat_override as ShaderMaterial).shader == _parallax_shader:
		register_material(mat_override as ShaderMaterial)
		return

	# Convert per-surface materials
	var surface_count: int = mesh.get_surface_material_count()
	for i in range(surface_count):
		var active_mat = mesh.get_active_material(i)
		if active_mat is SpatialMaterial and _can_apply_occlusion_dither(active_mat as SpatialMaterial):
			mesh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
			var new_mat = _convert_spatial_to_dither(active_mat as SpatialMaterial)
			mesh.set_surface_material(i, new_mat)
			register_material(new_mat)
		elif active_mat is ShaderMaterial and (active_mat as ShaderMaterial).shader == _parallax_shader:
			register_material(active_mat as ShaderMaterial)


func _can_apply_occlusion_dither(mat: SpatialMaterial) -> bool:
	if mat.flags_transparent:
		return false
	if mat.params_use_alpha_scissor:
		return false
	return true


func _convert_spatial_to_dither(source: SpatialMaterial) -> ShaderMaterial:
	var new_mat := ShaderMaterial.new()
	new_mat.shader = _dither_shader

	# Albedo
	new_mat.set_shader_param("albedo", source.albedo_color)
	if source.albedo_texture:
		new_mat.set_shader_param("texture_albedo", source.albedo_texture)

	# PBR
	new_mat.set_shader_param("metallic", source.metallic)
	new_mat.set_shader_param("roughness", source.roughness)
	new_mat.set_shader_param("specular", source.metallic_specular)

	# MRAO texture (metallic_texture is typically the MRAO map)
	if source.metallic_texture:
		new_mat.set_shader_param("texture_metallic_roughness_ao", source.metallic_texture)
		new_mat.set_shader_param("has_mrao_map", true)
	else:
		new_mat.set_shader_param("has_mrao_map", false)

	# Normal map
	if source.normal_enabled and source.normal_texture:
		new_mat.set_shader_param("texture_normal", source.normal_texture)
		new_mat.set_shader_param("normal_scale", source.normal_scale)
		new_mat.set_shader_param("has_normal_map", true)
	else:
		new_mat.set_shader_param("has_normal_map", false)

	# UV scale/offset
	new_mat.set_shader_param("uv1_scale", source.uv1_scale)
	new_mat.set_shader_param("uv1_offset", source.uv1_offset)

	# Emission
	if source.emission_enabled:
		new_mat.set_shader_param("emission_enabled", true)
		new_mat.set_shader_param("emission_color", source.emission)
		new_mat.set_shader_param("emission_energy", source.emission_energy)
		new_mat.set_shader_param("emission_op", source.emission_operator)

	# Initial occlusion params
	new_mat.set_shader_param("hole_radius", _hole_radius)
	new_mat.set_shader_param("is_active", 1.0)
	for key in _shader_params:
		new_mat.set_shader_param(key, _shader_params[key])

	return new_mat
