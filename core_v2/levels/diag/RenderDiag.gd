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

var _label: Label
var _holder: Spatial = null
var _probe := ""

func _ready() -> void:
	_build_panel()
	# Un frame para que el nivel termine de montar camara y BakedLightmap.
	yield(get_tree(), "idle_frame")
	_build_shader_probe()
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

# --- Censo del arbol ------------------------------------------------------------
# La matriz de materiales ya dio negativo: ninguna configuracion falla en iOS. La
# pregunta ahora es si los objetos que faltan estan en el arbol y visibles, o si
# directamente no llegaron. Comparar estos numeros contra la linea base de escritorio
# separa "no cargo" de "cargo pero no se rasteriza".

func _census(node: Node, acc: Dictionary) -> void:
	if node is MeshInstance:
		acc["mi"] += 1
		if node.mesh == null:
			acc["nullmesh"] += 1
		else:
			acc["surf"] += node.mesh.get_surface_count()
			if node.is_visible_in_tree():
				acc["vis"] += 1
	for child in node.get_children():
		_census(child, acc)

func _node_line(label: String, path: String) -> String:
	var scene = get_tree().current_scene
	var n = scene.get_node_or_null(path) if scene else null
	if n == null:
		n = get_tree().get_root().find_node(path.get_file(), true, false)
	if n == null:
		return "%s: NO EXISTE" % label
	if not (n is MeshInstance):
		return "%s: no es MeshInstance" % label
	if n.mesh == null:
		return "%s: vis=%s SIN MESH" % [label, n.is_visible_in_tree()]
	var aabb = n.mesh.get_aabb()
	return "%s: vis=%s surf=%d aabb=%.1f layers=%d" % [
		label, n.is_visible_in_tree(), n.mesh.get_surface_count(),
		aabb.size.length(), n.layers,
	]


# --- Sonda del shader de oclusion -------------------------------------------------
# El dither estable no alcanzo. Quedan dos causas dentro del mismo shader y hay que
# separarlas: que no compile/linkee en iOS (el objeto no se dibuja nunca) o que
# compile y el cono descarte de mas. Tres quads lo deciden:
#   A control  : unshaded, sabemos que se dibuja
#   B shader/off: el shader REAL con is_active=0 -> ningun discard posible
#   C shader/on : el shader REAL con el cono lejos -> no deberia descartar
# A y B y C -> el shader esta sano, el problema es el cono.
# A solo     -> el shader no se dibuja en iOS: compila mal o excede limites.

func _build_shader_probe() -> void:
	var cam := get_viewport().get_camera()
	if cam == null:
		_probe = "PROBE: sin camara"
		return
	_holder = Spatial.new()
	add_child(_holder)

	var control := SpatialMaterial.new()
	control.flags_unshaded = true
	control.albedo_color = Color(0.2, 1.0, 0.3)

	var sh: Shader = load("res://shaders/prop_dither_occlusion.gdshader")
	if sh == null:
		_probe = "PROBE: el .gdshader NO CARGA"
		return

	var off := ShaderMaterial.new()
	off.shader = sh
	off.set_shader_param("albedo", Color(1.0, 0.4, 0.0))
	off.set_shader_param("is_active", 0.0)
	# Emision para que no dependa de que haya luz donde este parado el jugador: si el
	# quad esta apagado es porque el shader no dibuja, no porque el rincon sea oscuro.
	off.set_shader_param("emission_enabled", true)
	off.set_shader_param("emission_color", Color(1.0, 0.4, 0.0))
	off.set_shader_param("emission_energy", 1.0)

	var on := ShaderMaterial.new()
	on.shader = sh
	on.set_shader_param("albedo", Color(0.2, 0.4, 1.0))
	on.set_shader_param("is_active", 1.0)
	# Cono a mil metros de aca: ningun fragmento deberia caer adentro.
	on.set_shader_param("camera_pos", Vector3(1000, 1000, 1000))
	on.set_shader_param("player_pos", Vector3(1000, 1000, 1002))
	on.set_shader_param("hole_radius", 0.5)
	on.set_shader_param("emission_enabled", true)
	on.set_shader_param("emission_color", Color(0.2, 0.4, 1.0))
	on.set_shader_param("emission_energy", 1.0)

	var mats := [control, off, on]
	for i in range(mats.size()):
		var mi := MeshInstance.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.18, 0.18)
		mi.mesh = quad
		mi.material_override = mats[i]
		mi.cast_shadow = MeshInstance.SHADOW_CASTING_SETTING_OFF
		mi.translation = Vector3(-0.25 + 0.25 * i, -0.35, -1.2)
		_holder.add_child(mi)
	_probe = "PROBE: A=control(verde) B=shader/off(naranja) C=shader/on(azul)"
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
	var acc := {"mi": 0, "vis": 0, "nullmesh": 0, "surf": 0}
	var scene = get_tree().current_scene
	_census(scene if scene else get_tree().get_root(), acc)
	lines.append("MESHES: total=%d visibles=%d sin_mesh=%d surf=%d" % [acc["mi"], acc["vis"], acc["nullmesh"], acc["surf"]])
	lines.append(_node_line("CriopodGlass", "Spatial/Criopods1/Glass"))
	lines.append(_node_line("CriopodShell", "Spatial/Criopods1/Shell"))
	lines.append(_node_line("ScaffoldF1", "ScaffoldHubTower/Floor_1/CombinedMesh"))
	lines.append(_probe)
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
