extends SceneTree

# inspect_scaffold_materials.gd — Lista, por malla horneada, cuantas superficies
# tiene y que material lleva cada una. Sirve para detectar que el horneado se
# quedo con el ShaderMaterial de dither que PropDitherManager aplica en runtime
# en vez del SpatialMaterial autorizado.
#
# Run: ODISEA_INSPECT_DIR=res://... godot3-bin --no-window -s tools/inspect_scaffold_materials.gd

const DIR := "res://core_v2/levels/interiors/"
const MESHES := [
	"DomeIntro_SpiralStairs_baked.mesh",
	"DomeIntro_HubSpokes_baked.mesh",
	"DomeIntro_SpiralWalkways_baked.mesh",
]

func _init() -> void:
	for name in MESHES:
		var mesh: ArrayMesh = load(DIR + name)
		if mesh == null:
			print("INSPECT:%s <missing>" % name)
			continue
		print("INSPECT:%s surfaces=%d" % [name, mesh.get_surface_count()])
		for i in range(mesh.get_surface_count()):
			var mat: Material = mesh.surface_get_material(i)
			var verts: int = (mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PoolVector3Array).size()
			var desc := "<null>"
			if mat is ShaderMaterial:
				var sm := mat as ShaderMaterial
				desc = "ShaderMaterial shader=%s uv1_scale=%s alpha_scissor=%s" % [
					sm.shader.resource_path if sm.shader else "-",
					str(sm.get_shader_param("uv1_scale")),
					str(sm.get_shader_param("use_alpha_scissor"))]
			elif mat is SpatialMaterial:
				var sp := mat as SpatialMaterial
				desc = "SpatialMaterial albedo=%s tex=%s uv1_scale=%s scissor=%s" % [
					str(sp.albedo_color),
					sp.albedo_texture.resource_path if sp.albedo_texture else "-",
					str(sp.uv1_scale), str(sp.params_use_alpha_scissor)]
			print("  surf %d verts=%6d %s" % [i, verts, desc])
	quit(0)
