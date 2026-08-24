extends Node

# Diagnostico de render para builds de tienda (iOS), donde no hay consola ni comandos
# remotos: ANNAV2 los bloquea en release. Todo lo que necesitamos saber tiene que caber
# en UNA captura de pantalla del dispositivo.
#
# Uso: instanciar RenderDiag.tscn como hijo de la escena del nivel, exportar, mirar la
# captura, sacarlo. No se autoregistra en ningun lado a proposito.
#
# Responde dos preguntas:
#   1. Que configuracion de material se dibuja  -> la fila de quads frente a la camara.
#   2. Si el lightmap horneado cargo de verdad  -> la linea LIGHTMAP del panel.

const QUAD_SIZE := 0.18
const QUAD_DISTANCE := -1.2

var _label: Label
var _holder: Spatial = null
var _quads := 0

func _ready() -> void:
	_build_panel()
	# Un frame para que el nivel termine de montar camara y BakedLightmap.
	yield(get_tree(), "idle_frame")
	_build_quads()
	_label.text = _report()

func _build_panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	bg.anchor_right = 1.0
	bg.margin_bottom = 170
	layer.add_child(bg)
	_label = Label.new()
	_label.anchor_right = 1.0
	_label.margin_left = 12
	_label.margin_top = 8
	layer.add_child(_label)

# --- Quads: una configuracion de material por columna -------------------------------
# Todas comparten geometria y color. Lo unico que cambia es el modo de material, asi
# que la que falte en la captura es exactamente la que iOS no dibuja.

func _material_variants() -> Array:
	var opaque := SpatialMaterial.new()
	opaque.flags_unshaded = true
	opaque.albedo_color = Color(0.2, 1.0, 0.3)

	var blend := SpatialMaterial.new()
	blend.flags_transparent = true
	blend.albedo_color = Color(1.0, 0.5, 0.1, 0.55)

	var scissor := SpatialMaterial.new()
	scissor.flags_transparent = true
	scissor.params_use_alpha_scissor = true
	scissor.params_alpha_scissor_threshold = 0.5
	scissor.albedo_color = Color(0.3, 0.6, 1.0, 1.0)

	var blend_unshaded := SpatialMaterial.new()
	blend_unshaded.flags_transparent = true
	blend_unshaded.flags_unshaded = true
	blend_unshaded.albedo_color = Color(1.0, 1.0, 0.2, 0.55)

	# Igual que el vidrio del criopod: transparente, metalico y con cull apagado.
	var glass := SpatialMaterial.new()
	glass.flags_transparent = true
	glass.params_cull_mode = SpatialMaterial.CULL_DISABLED
	glass.metallic = 1.0
	glass.albedo_color = Color(0.29, 0.51, 0.61, 0.49)

	var shader_mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode blend_mix, unshaded;
void fragment() { ALBEDO = vec3(1.0, 0.2, 0.8); ALPHA = 0.6; }
"""
	shader_mat.shader = sh

	return [
		["opaco", opaque],
		["blend", blend],
		["scissor", scissor],
		["blend+unsh", blend_unshaded],
		["glass", glass],
		["shader", shader_mat],
	]

func _build_quads() -> void:
	# Los quads NO cuelgan de la camara: Dome_Intro alterna VCameras y al cambiar la
	# activa se irian con la vieja. Un holder propio que se pega a la camara del
	# viewport cada frame sobrevive los cambios, y asi que un quad no aparezca
	# significa que el material no se dibuja, no que el nodo se quedo en otro lado.
	_holder = Spatial.new()
	add_child(_holder)
	var variants := _material_variants()
	var span := QUAD_SIZE * 1.4
	var start := -span * (variants.size() - 1) * 0.5
	for i in range(variants.size()):
		var mi := MeshInstance.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(QUAD_SIZE, QUAD_SIZE)
		mi.mesh = quad
		mi.material_override = variants[i][1]
		mi.cast_shadow = MeshInstance.SHADOW_CASTING_SETTING_OFF
		mi.translation = Vector3(start + span * i, -0.35, QUAD_DISTANCE)
		_holder.add_child(mi)
	_quads = variants.size()
	set_process(true)

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera()
	if cam != null and _holder != null:
		_holder.global_transform = cam.global_transform

# --- Reporte -----------------------------------------------------------------------

func _report() -> String:
	var lines := []
	lines.append("RENDER DIAG  %s | %s" % [OS.get_name(), OS.get_video_driver_name(OS.get_current_video_driver())])
	lines.append("gpu: %s" % VisualServer.get_video_adapter_name())
	lines.append("msaa=%s fxaa=%s vertex_shading=%s" % [
		ProjectSettings.get_setting("rendering/quality/filters/msaa"),
		ProjectSettings.get_setting("rendering/quality/filters/use_fxaa"),
		ProjectSettings.get_setting("rendering/quality/shading/force_vertex_shading"),
	])
	# La duda de fondo: si el override ".mobile" se resuelve en iOS. Godot trae
	# force_vertex_shading.mobile=true de fabrica, asi que si "mobile" NO es feature
	# en este dispositivo, el .mobile=false del proyecto tampoco lo apaga.
	lines.append("features: mobile=%s iOS=%s pvrtc=%s etc=%s etc2=%s" % [
		OS.has_feature("mobile"), OS.has_feature("iOS"),
		OS.has_feature("pvrtc"), OS.has_feature("etc"), OS.has_feature("etc2"),
	])
	var cam := get_viewport().get_camera()
	lines.append("quads: n=%d cam=%s | opaco blend scissor blend+unsh glass shader" % [_quads, cam.name if cam else "NULL"])
	lines.append(_lightmap_report())
	return PoolStringArray(lines).join("\n")

func _lightmap_report() -> String:
	var baked = _find_baked_lightmap(get_tree().get_root())
	if baked == null:
		return "LIGHTMAP: no hay BakedLightmap en el arbol"
	var data = baked.light_data
	if data == null:
		return "LIGHTMAP: BakedLightmap sin light_data (el .lmbake no cargo)"
	var users: int = data.get_user_count()
	# Una textura nula o de tamano 0 significa que el .stex del lightmap no llego al
	# dispositivo o el driver la rechazo: el bake existe pero no se aplica.
	var null_tex := 0
	var sizes := []
	for i in range(users):
		var tex = data.get_user_lightmap(i)
		if tex == null or tex.get_width() == 0:
			null_tex += 1
		elif sizes.size() < 3:
			sizes.append("%dx%d" % [tex.get_width(), tex.get_height()])
	return "LIGHTMAP: users=%d nulas=%d tex=%s" % [users, null_tex, PoolStringArray(sizes).join(",")]

func _find_baked_lightmap(node: Node):
	if node is BakedLightmap:
		return node
	for child in node.get_children():
		var found = _find_baked_lightmap(child)
		if found != null:
			return found
	return null
