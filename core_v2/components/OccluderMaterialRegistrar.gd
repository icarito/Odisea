extends Spatial

# Attach this to any MeshInstance or CSG node that uses the Occlusion Shader
# It will automatically register the material with the global manager.
# The node should have a CollisionObject (StaticBody, etc.) as parent or sibling
# for raycast-based occlusion detection to work properly.

# --- Shader Parameters (adjust in Inspector) ---
export(float, 0.0, 2.0) var blur_softness: float = 0.8 setget set_blur_softness
export(float, 0.1, 3.0) var edge_fade: float = 1.2 setget set_edge_fade
export(float, 0.0, 1.0) var transparency_min: float = 0.3 setget set_transparency_min
export(float, 0.0, 1.0) var transparency_max: float = 0.95 setget set_transparency_max
export(float, 0.5, 5.0) var floor_protect_radius: float = 2.0 setget set_floor_protect_radius

var _material: ShaderMaterial = null

func _ready():
	# Wait one frame to ensure geometry is ready if it's a complex node
	call_deferred("_register_material")

func _register_material():
	var mat = null
	
	if has_method("get_active_material"):
		mat = call("get_active_material", 0)
	elif "material" in self:
		mat = self.material
	
	if mat and mat is ShaderMaterial:
		_material = mat
		# Apply initial values from export vars
		_apply_shader_params()
		# Find the nearest spatial ancestor to use as owner for raycast detection
		var owner_node = _find_collision_ancestor()
		WallOcclusionManager.register_material(mat, owner_node if owner_node else self)
		print("OccluderMaterialRegistrar: Registered material on ", name, " owner: ", owner_node.name if owner_node else self.name)
	else:
		print("OccluderMaterialRegistrar: Failed to find ShaderMaterial on ", name)

func _apply_shader_params():
	if _material:
		_material.set_shader_param("blur_softness", blur_softness)
		_material.set_shader_param("edge_fade", edge_fade)
		_material.set_shader_param("transparency_min", transparency_min)
		_material.set_shader_param("transparency_max", transparency_max)
		_material.set_shader_param("floor_protect_radius", floor_protect_radius)

# Setters for live preview in editor
func set_blur_softness(value: float):
	blur_softness = value
	_apply_shader_params()

func set_edge_fade(value: float):
	edge_fade = value
	_apply_shader_params()

func set_transparency_min(value: float):
	transparency_min = value
	_apply_shader_params()

func set_transparency_max(value: float):
	transparency_max = value
	_apply_shader_params()

func set_floor_protect_radius(value: float):
	floor_protect_radius = value
	_apply_shader_params()

func _find_collision_ancestor() -> Spatial:
	# Look for a CollisionObject in ancestors (most common setup)
	var node = get_parent()
	while node:
		if node is CollisionObject:
			return node
		node = node.get_parent()
	# If no collision object found, return self as fallback
	return self

func _exit_tree():
	# Ideally unregister, but Manager handles null references strictly in _process
	# If we want to be clean:
	# var mat...
	# WallOcclusionManager.unregister_material(mat)
	pass
