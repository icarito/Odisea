extends Reference
class_name ArkRunTronMaterials

# FD-324 — fabricas de ShaderMaterial del pase visual del Ark-Run. Centraliza los
# shaders procedurales (terrazas, domos, pluma del propulsor y sombra falsa) para
# no repetir codigo entre los modulos de presentacion. Ningun material agrega
# draw calls: reemplazan el material del mesh/MultiMesh existente.

const TerraceShader = preload("res://core_v2/levels/ark_run/shaders/ark_run_terrace.shader")
const DomeShader = preload("res://core_v2/levels/ark_run/shaders/ark_run_dome.shader")
const PlumeShader = preload("res://core_v2/levels/ark_run/shaders/ark_run_thruster_plume.shader")
const ShadowShader = preload("res://core_v2/levels/ark_run/shaders/ark_run_gravity_shadow.shader")

static func plate_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TerraceShader
	return material

static func dome_material(tint: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = DomeShader
	material.set_shader_param("base_color", tint)
	return material

static func plume_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PlumeShader
	return material

static func shadow_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = ShadowShader
	return material
