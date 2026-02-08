class_name SciFiFloorPanelV2
extends StaticBody

func _ready():
	var mesh_inst = $MeshInstance
	if mesh_inst and mesh_inst.material_override:
		var mat = mesh_inst.material_override
		if mat is ShaderMaterial:
			# Configure shader visuals
			mat.set_shader_param("spherePos1", Vector3(1, 0.2, -1))
			mat.set_shader_param("sphereRad1", 0.1)
			mat.set_shader_param("spherecol1", Color(1, 0.7, 0.2))

			mat.set_shader_param("spherePos2", Vector3(-1, 0.2, 1))
			mat.set_shader_param("sphereRad2", 0.1)
			mat.set_shader_param("spherecol2", Color(0.2, 0.5, 1.0))

			mat.set_shader_param("tubeStart1", Vector3(-1.0, 0.05, -1.0))
			mat.set_shader_param("tubeEnd1", Vector3(1.0, 0.05, 1.0))
			mat.set_shader_param("tubeRad1", 0.03)
			mat.set_shader_param("tubecol1", Color(0.9, 0.1, 0.1))

			mat.set_shader_param("tubeStart2", Vector3(-1.0, 0.05, 1.0))
			mat.set_shader_param("tubeEnd2", Vector3(1.0, 0.05, -1.0))
			mat.set_shader_param("tubeRad2", 0.03)
			mat.set_shader_param("tubecol2", Color(0.1, 0.9, 0.1))
