# PropDitherManager.gd
# Autoload singleton that automatically applies the dither occlusion shader
# to all layer 7 (Props) MeshInstance nodes. Updates player_pos/camera_pos
# uniforms each frame so the shader can compute cone-based dithering.
#
# Props are detected by scanning for StaticBody nodes with collision_layer & 64.
# Their child MeshInstance, MultiMeshInstance and CSG SpatialMaterials are
# converted to ShaderMaterial.
# Nodes in group "no_occlusion" are skipped.

extends Node

const PROP_LAYER_BIT: int = 64  # Layer 7

var _dither_shader: Shader = preload("res://shaders/prop_dither_occlusion.gdshader")
var _dither_shader_double_sided: Shader = preload("res://shaders/prop_dither_occlusion_double_sided.gdshader")
var _parallax_shader: Shader = preload("res://core_v2/props/parallax_assets/card_parallax.shader")
# The duct maze hull keeps its own stylized panel shader but now carries the same
# cone-occlusion uniforms (player_pos/camera_pos/is_active/...). Register its materials
# so they fade between camera and player like the generic dither props, without losing
# the panel/seam/rivet look.
var _duct_hull_shader: Shader = preload("res://core_v2/props/duct/shaders/duct_hull.shader")
var _registered_materials: Array = []
var _registered_lookup: Dictionary = {}  # ShaderMaterial -> true (O(1) dedupe on register)
# Every per-frame uniform this manager writes (player_pos/camera_pos/is_active/hole_radius)
# is global, and the conversion below is a pure function of the source SpatialMaterial.
# So meshes sharing a source material can share one converted ShaderMaterial instead of
# getting a private copy each: Dome_Intro alone was registering 3825 materials (225
# criopods x 3 meshes x surfaces), and _process rewrote every one of them every frame.
var _dither_cache: Dictionary = {}  # source SpatialMaterial -> converted ShaderMaterial
var _processed_meshes: Dictionary = {}  # MeshInstance -> true (avoid double-processing)

var _player_node: Spatial = null
var _camera_node: Camera = null

# Historicamente la conversion a dither apagaba cast_shadow en todo lo que tocaba
# (perf / evitar shadow del ALPHA_SCISSOR cambiando de frame a frame). Eso le
# quita la sombra tambien a props que casi nunca entran al cono de oclusion,
# como el shell de los criopods. Parametro para probar dejarlo prendido.
export var strip_shadow_on_convert: bool = false

# Shader effect parameters (can be tuned via set_occlusion_params)
var _hole_radius: float = 0.5
var _shader_params: Dictionary = {
	"edge_fade": 1.0,
	"transparency_min": 0.3,
	"transparency_max": 0.95,
	"floor_protect_radius": 1.0
}

func _ready() -> void:
	call_deferred("_scan_scene_tree")
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
	var dropped := false
	for mat in _registered_materials:
		if is_instance_valid(mat):
			mat.set_shader_param("player_pos", p_pos)
			mat.set_shader_param("camera_pos", c_pos)
			mat.set_shader_param("is_active", 1.0)
			mat.set_shader_param("hole_radius", _hole_radius)
			for key in _shader_params:
				mat.set_shader_param(key, _shader_params[key])
			living.append(mat)
		else:
			dropped = true
	if dropped:
		# Keep the dedupe lookup in sync with the pruned array.
		_registered_lookup.clear()
		for mat in living:
			_registered_lookup[mat] = true
	_registered_materials = living


func set_occlusion_params(radius: float, params: Dictionary = {}) -> void:
	_hole_radius = radius
	for key in params:
		_shader_params[key] = params[key]


func register_material(mat: ShaderMaterial) -> void:
	# Dictionary lookup instead of Array.has(): the linear scan made scene load
	# O(n^2) over thousands of materials.
	if mat and not _registered_lookup.has(mat):
		_registered_lookup[mat] = true
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


func refresh_occlusion_for_node(root: Node) -> void:
	if not is_instance_valid(root):
		return
	if root is CollisionObject:
		var co := root as CollisionObject
		if co.collision_layer & PROP_LAYER_BIT and not co.is_in_group("player"):
			_process_collision_object(co)
			return
	_convert_meshes_recursive(root)


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
		if child is MeshInstance or child is MultiMeshInstance:
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

	if node is CSGShape:
		_convert_csg_shape(node as CSGShape)
	elif node is MeshInstance:
		_convert_mesh_instance(node as MeshInstance)
	elif node is MultiMeshInstance:
		_convert_multimesh_instance(node as MultiMeshInstance)

	for child in node.get_children():
		_convert_meshes_recursive(child)


# CSG geometry is not a MeshInstance, so the scan walked straight past it: a
# prop built from CSG stayed solid between camera and player while every mesh
# around it faded. The elevator's door headers are exactly that. Its material can
# sit on the shape itself (CSGPrimitive.material) or as an override; the override
# is what the renderer honours last, so that is where the converted shader goes.
func _convert_csg_shape(shape: CSGShape) -> void:
	if _processed_meshes.has(shape):
		return
	_processed_meshes[shape] = true

	var source = shape.material_override
	if source == null:
		source = shape.get("material")
	if source is ShaderMaterial:
		if _is_occlusion_shader((source as ShaderMaterial).shader):
			register_material(source as ShaderMaterial)
		return
	if not (source is SpatialMaterial):
		return
	if not _can_apply_occlusion_dither(source as SpatialMaterial):
		return

	if strip_shadow_on_convert:
		shape.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var new_mat = _convert_spatial_to_dither(source as SpatialMaterial)
	shape.material_override = new_mat
	register_material(new_mat)


func _convert_mesh_instance(mesh: MeshInstance) -> void:
	if _processed_meshes.has(mesh):
		return
	_processed_meshes[mesh] = true

	# Convert material_override if it's a SpatialMaterial
	var mat_override = mesh.material_override
	if mat_override is SpatialMaterial and _can_apply_occlusion_dither(mat_override as SpatialMaterial):
		if strip_shadow_on_convert:
			mesh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		var new_mat = _convert_spatial_to_dither(mat_override as SpatialMaterial)
		mesh.material_override = new_mat
		register_material(new_mat)
		return  # Override takes priority, no need to process surfaces
	elif mat_override is ShaderMaterial and _is_occlusion_shader((mat_override as ShaderMaterial).shader):
		register_material(mat_override as ShaderMaterial)
		return

	# Convert per-surface materials
	var surface_count: int = mesh.get_surface_material_count()
	for i in range(surface_count):
		var active_mat = mesh.get_active_material(i)
		if active_mat is SpatialMaterial and _can_apply_occlusion_dither(active_mat as SpatialMaterial):
			if strip_shadow_on_convert:
				mesh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
			var new_mat = _convert_spatial_to_dither(active_mat as SpatialMaterial)
			mesh.set_surface_material(i, new_mat)
			register_material(new_mat)
		elif active_mat is ShaderMaterial and _is_occlusion_shader((active_mat as ShaderMaterial).shader):
			register_material(active_mat as ShaderMaterial)

func _convert_multimesh_instance(inst: MultiMeshInstance) -> void:
	if _processed_meshes.has(inst):
		return
	_processed_meshes[inst] = true
	var mat_override = inst.material_override
	if mat_override is SpatialMaterial and _can_apply_occlusion_dither(mat_override as SpatialMaterial):
		if strip_shadow_on_convert:
			inst.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		var new_mat = _convert_spatial_to_dither(mat_override as SpatialMaterial)
		inst.material_override = new_mat
		register_material(new_mat)
	elif mat_override is ShaderMaterial and _is_occlusion_shader((mat_override as ShaderMaterial).shader):
		register_material(mat_override as ShaderMaterial)


# Shaders authored outside this manager (MetalFence, ElevatorDoor's ShaftFence/
# FencePanel) self-tag with this meta key instead of relying on Shader.code: the
# headless/Dummy rasterizer CI runs under never populates .code (shader_get_code
# returns "" with no GL driver), so a string-sniffing check silently sees every
# shader as non-occlusion there even though it works fine in the editor.
const OCCLUSION_UNIFORMS_META := "odisea_occlusion_uniforms"

# A shader that already carries the per-frame occlusion uniforms (player_pos/camera_pos/
# is_active/...) and just needs registering so _process keeps feeding it. The generic
# dither + parallax props, plus the duct maze hull.
func _is_occlusion_shader(shader: Shader) -> bool:
	if shader == null:
		return false
	if shader == _dither_shader or shader == _dither_shader_double_sided \
		or shader == _parallax_shader or shader == _duct_hull_shader:
		return true
	if shader.has_meta(OCCLUSION_UNIFORMS_META):
		return true
	# Procedural props such as MetalFence keep their authored shader, but expose
	# the same uniform contract so this manager can feed the occlusion cone.
	var code: String = shader.code
	return code.find("uniform vec3 player_pos") >= 0 \
		and code.find("uniform vec3 camera_pos") >= 0 \
		and code.find("uniform float is_active") >= 0


func _can_apply_occlusion_dither(mat: SpatialMaterial) -> bool:
	if mat.flags_transparent:
		# El alpha scissor NO es transparencia real: recorta el fragmento y lo que
		# queda se dibuja opaco. Godot 3 igual exige flags_transparent para
		# habilitarlo, asi que rechazar todo flags_transparent dejaba fuera de la
		# oclusion a las rejillas (steel grate) en toda la escena — decks de
		# SteelGratePlatform, pisos de ScaffoldHubRing y los combinados horneados.
		# El shader de dither ya implementa el scissor (use_alpha_scissor), solo
		# que este gate impedia que llegara a usarse.
		return mat.params_use_alpha_scissor
	return true


func _has_albedo_map(source: SpatialMaterial) -> bool:
	return source.albedo_texture != null


func _convert_spatial_to_dither(source: SpatialMaterial) -> ShaderMaterial:
	# Reuse the conversion for a source material we have already seen: the result
	# depends only on `source`, and the per-frame uniforms are global.
	var cached = _dither_cache.get(source)
	if cached is ShaderMaterial:
		return cached

	var new_mat := ShaderMaterial.new()
	# El render_mode no es un uniform en Godot 3: para no perder el doble lado de
	# las rejillas (un unico quad que tambien se mira desde abajo) hay una variante
	# del shader con cull_disabled.
	if source.params_cull_mode == SpatialMaterial.CULL_DISABLED:
		new_mat.shader = _dither_shader_double_sided
	else:
		new_mat.shader = _dither_shader
	_dither_cache[source] = new_mat

	# Albedo
	new_mat.set_shader_param("albedo", source.albedo_color)
	if _has_albedo_map(source):
		new_mat.set_shader_param("texture_albedo", source.albedo_texture)
		new_mat.set_shader_param("has_albedo_map", true)
	else:
		new_mat.set_shader_param("has_albedo_map", false)
	new_mat.set_shader_param("use_vertex_color", source.vertex_color_use_as_albedo)

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
	new_mat.set_shader_param("use_alpha_scissor", source.params_use_alpha_scissor)
	new_mat.set_shader_param("alpha_scissor_threshold", source.params_alpha_scissor_threshold)

	# Emission
	if source.emission_enabled:
		new_mat.set_shader_param("emission_enabled", true)
		new_mat.set_shader_param("emission_color", source.emission)
		new_mat.set_shader_param("emission_energy", source.emission_energy)
		new_mat.set_shader_param("emission_op", source.emission_operator)

	# Initial occlusion params
	new_mat.set_shader_param("hole_radius", _hole_radius)
	new_mat.set_shader_param("is_active", 1.0)
	new_mat.set_shader_param("stable_mobile_dither", OS.get_name() == "Android")
	for key in _shader_params:
		new_mat.set_shader_param(key, _shader_params[key])

	return new_mat
