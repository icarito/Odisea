extends Node

# Aplica a mano el lightmap horneado, sampleandolo via uniform en lugar del camino del motor.
#
# HISTORICO: esto fue el camino por defecto de iOS cuando el proyecto corria GLES2 ahi.
# Godot ata la textura del lightmap a "max_texture_image_units - 4": unidad 12 en Android,
# 4 en iOS (8 unidades), en el medio de las texturas del material y compartida con
# screen/depth_texture. La colision es silenciosa (sin error de linkeo) y el bake no se
# dibuja. La salida definitiva no fue un workaround sino cambiar de renderer: iOS corre
# GLES3 (quality/driver/driver_name.iOS en project.godot), donde el lightmap nativo del
# motor si se dibuja y todo el camino estandar funciona.
#
# HOY: opt-in puro por variable de entorno (ODISEA_MANUAL_LIGHTMAP=1), para comparar A/B
# contra el camino nativo en el dispositivo sin gastar otro build. Sin la variable, este
# nodo se auto-libera y no toca nada, en ninguna plataforma.
#
# Esto NO rehornea nada: usa el mismo .lmbake, las mismas texturas y la misma UV2, solo
# que muestreadas desde un shader propio, donde el sampler recibe una unidad secuencial.
#
# Se instancia en la escena del nivel; necesita el BakedLightmap de esa escena.

const SHADER := preload("res://core_v2/visual/lightmap_manual.shader")
const ENV_FLAG := "ODISEA_MANUAL_LIGHTMAP"
const META_KEY := "ios_lightmap_applied"

static func _wants_fallback(_os_name: String, env_value: String) -> bool:
	# El OS ya no decide: iOS corre GLES3 con el lightmap nativo. Solo la variable de
	# entorno fuerza el camino manual, para A/B en el dispositivo. El parametro queda
	# en la firma porque test_ios_lightmap_fallback la ejercita en varios OS.
	return env_value.to_lower().strip_edges() in ["1", "true", "yes", "on"]

func _ready() -> void:
	Engine.set_meta(META_KEY, -1)
	if not _wants_fallback(OS.get_name(), OS.get_environment(ENV_FLAG)):
		queue_free()
		return
	# Diferido: el BakedLightmap tiene que haber entrado al arbol y resuelto su light_data.
	call_deferred("_apply")

func _apply() -> void:
	# DomeLightState llama _apply() por nombre cuando cambia el bake, sin saber si este
	# nodo quedo vivo. Sin el gate aca, un call_deferred suelto podria reaplicar el
	# camino manual encima del nativo (doble bake) en builds sin la variable de entorno.
	if not _wants_fallback(OS.get_name(), OS.get_environment(ENV_FLAG)):
		return
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
		# Apagar el lightmap del motor en esta instancia: no se dibuja igual, y libera la
		# unidad de textura 4, que es donde lo ata y donde chocaria con nuestro sampler.
		VisualServer.instance_set_use_lightmap(mi.get_instance(), RID(), RID(), -1, Rect2(0, 0, 1, 1))
		for s in range(mi.mesh.get_surface_count()):
			var source = mi.get_surface_material(s)
			if source == null:
				source = mi.mesh.surface_get_material(s)
			if source is ShaderMaterial:
				# Los shaders del proyecto ya traen los uniforms: NO se reemplaza el
				# material. Reemplazarlo se llevaba puestas texturas, tiling, dither y
				# parallax -- 84 de las 92 superficies horneadas son ShaderMaterial.
				# Se setea sin preguntar: Shader.has_param() no sirve como gate (devuelve
				# false hasta para uniforms que existen, porque necesita que el servidor
				# de render haya compilado el shader). Setear un uniform que el shader no
				# declara no hace nada, asi que es seguro.
				var sh := source as ShaderMaterial
				sh.set_shader_param("lightmap_tex", tex)
				sh.set_shader_param("lightmap_energy", energy)
				applied += 1
			elif source is SpatialMaterial:
				mi.set_surface_material(s, _build(source, tex, energy))
				applied += 1
			else:
				skipped += 1

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
