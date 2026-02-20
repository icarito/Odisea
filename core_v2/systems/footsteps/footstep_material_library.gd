extends Resource
class_name FootstepMaterialLibrary

export(Array) var footstep_material_library: Array = []

func get_footstep_stream_by_material(material: Material) -> AudioStream:
	for profile in footstep_material_library:
		if profile is FootstepMaterialProfile:
			if profile.material == material and profile.footstep_profile:
				return profile.footstep_profile
	return null
