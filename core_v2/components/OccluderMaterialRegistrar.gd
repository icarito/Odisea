extends Spatial

# Attach this to any MeshInstance or CSG node that uses the Occlusion Shader
# It will automatically register the material with the global manager.
# The node should have a CollisionObject (StaticBody, etc.) as parent or sibling
# for raycast-based occlusion detection to work properly.

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
		# Find the nearest spatial ancestor to use as owner for raycast detection
		var owner_node = _find_collision_ancestor()
		WallOcclusionManager.register_material(mat, owner_node if owner_node else self)
		print("OccluderMaterialRegistrar: Registered material on ", name, " owner: ", owner_node.name if owner_node else self.name)
	else:
		print("OccluderMaterialRegistrar: Failed to find ShaderMaterial on ", name)

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
