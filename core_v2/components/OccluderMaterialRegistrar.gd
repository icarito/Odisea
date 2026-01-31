extends Spatial

# Attach this to any MeshInstance or CSG node that uses the Occlusion Shader
# It will automatically register the material with the global manager.

func _ready():
	# Wait one frame to ensure geometry is ready if it's a complex node
	call_deferred("_register_material")

func _register_material():
	var mat = null
	
	if self is MeshInstance:
		mat = self.get_active_material(0)
	elif self is CSGShape:
		mat = self.material
	
	if mat and mat is ShaderMaterial:
		WallOcclusionManager.register_material(mat)
		print("OccluderMaterialRegistrar: Registered material on ", name)
	else:
		print("OccluderMaterialRegistrar: Failed to find ShaderMaterial on ", name)

func _exit_tree():
	# Ideally unregister, but Manager handles null references strictly in _process
	# If we want to be clean:
	# var mat...
	# WallOcclusionManager.unregister_material(mat)
	pass
