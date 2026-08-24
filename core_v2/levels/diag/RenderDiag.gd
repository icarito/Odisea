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

func _ready() -> void:
	_build_panel()
	# Un frame para que el nivel termine de montar camara y BakedLightmap.
	yield(get_tree(), "idle_frame")
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
