extends Node

# Aplica a mano el lightmap horneado en iOS, donde el camino del motor no lo dibuja.
#
# Medido en el dispositivo: las 39 asignaciones entran sin fallos
# (VisualServer.instance_set_use_lightmap, ok=39 fallos=0) y aun asi la escena se ve con
# el albedo crudo. Descartados antes: atlas, HDR, no-POT, mipmaps, repeat, compresion de
# textura y de vertices, UV2, iluminacion por pixel, normales y presion de samplers.
#
# La unica diferencia estructural que queda entre iOS y Android en ese camino es donde
# el motor ata la textura: "max_texture_image_units - 4". Android da 16 unidades (cae en
# la 12), iOS da 8 (cae en la 4, compartida con screen_texture y depth_texture).
#
# Esto NO rehornea nada: usa el mismo .lmbake, las mismas texturas y la misma UV2, solo
# que muestreadas desde un shader propio, donde el sampler recibe una unidad secuencial.
#
# Se instancia en la escena del nivel; necesita el BakedLightmap de esa escena.

const SHADER := preload("res://core_v2/visual/lightmap_manual.shader")
const ENV_FLAG := "ODISEA_MANUAL_LIGHTMAP"
const META_KEY := "ios_lightmap_applied"

static func _wants_fallback(os_name: String, env_value: String) -> bool:
	if env_value.to_lower().strip_edges() in ["1", "true", "yes", "on"]:
		return true
	return os_name == "iOS"

func _ready() -> void:
	Engine.set_meta(META_KEY, -1)
	if not _wants_fallback(OS.get_name(), OS.get_environment(ENV_FLAG)):
		queue_free()
		return
	# Diferido: el BakedLightmap tiene que haber entrado al arbol y resuelto su light_data.
	call_deferred("_apply")

func _apply() -> void:
	var baked = _find_baked(get_tree().get_root())
	if baked == null or baked.light_data == null:
		Engine.set_meta(META_KEY, -2)
		print("[IOSLightmap] no hay BakedLightmap con light_data")
		return

	var data = baked.light_data
	var energy: float = float(data.energy)
	var applied := 0
	var skipped := 0

	for i in range(data.get_user_count()):
		var tex = data.get_user_lightmap(i)
		var node = baked.get_node_or_null(data.get_user_path(i))
		if tex == null or not (node is MeshInstance) or node.mesh == null:
			skipped += 1
			continue
		var mi := node as MeshInstance
		for s in range(mi.mesh.get_surface_count()):
			var source = mi.get_surface_material(s)
			if source == null:
				source = mi.mesh.surface_get_material(s)
			var mat := _build(source, tex, energy)
			mi.set_surface_material(s, mat)
			applied += 1

	Engine.set_meta(META_KEY, applied)
	print("[IOSLightmap] superficies=%d omitidas=%d energy=%.2f" % [applied, skipped, energy])

# Copia lo que el material original aportaba al color y le suma el lightmap. Los otros
# mapas (normal, ao, metallic) se pierden a proposito: de las 39 mallas horneadas solo
# una usa mas de una textura, asi que el costo visual es practicamente nulo y mantiene el
# shader en un solo sampler ademas del bake.
func _build(source, lightmap: Texture, energy: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_param("lightmap_tex", lightmap)
	mat.set_shader_param("lightmap_energy", energy)
	if source is SpatialMaterial:
		var sm := source as SpatialMaterial
		mat.set_shader_param("albedo_color", sm.albedo_color)
		mat.set_shader_param("roughness_value", sm.roughness)
		mat.set_shader_param("metallic_value", sm.metallic)
		mat.set_shader_param("specular_value", sm.metallic_specular)
		if sm.albedo_texture != null:
			mat.set_shader_param("texture_albedo", sm.albedo_texture)
			mat.set_shader_param("has_albedo_map", true)
	else:
		mat.set_shader_param("albedo_color", Color(1, 1, 1, 1))
	return mat

func _find_baked(node: Node):
	if node is BakedLightmap:
		return node
	for child in node.get_children():
		var found = _find_baked(child)
		if found != null:
			return found
	return null
