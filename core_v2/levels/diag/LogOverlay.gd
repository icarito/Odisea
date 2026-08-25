extends Node

# Muestra en pantalla el final del log del motor. SOLO iOS.
#
# En iOS no hay consola ni comandos remotos: ANNAV2 los bloquea en release, y en debug
# el build no se puede archivar para distribucion (xcodebuild: "ARCHIVE FAILED"). Los
# errores de compilacion de shaders del driver solo viven en user://logs/godot.log, que
# se activa con logging/file_logging/enable_file_logging.iOS.
#
# Uso: instanciar LogOverlay.tscn en la escena del nivel y sacarlo al terminar. En
# escritorio y Android se libera solo sin dibujar nada.

# Segundos antes de leer: los shaders se compilan al renderizar los primeros frames,
# asi que leer en _ready mostraria un log sin los errores que interesan.
const READ_DELAY := 6.0
const MAX_LINES := 14
const ENV_FLAG := "ODISEA_LOG_OVERLAY"

# Se muestran solo las lineas que contengan alguno de estos. Un log completo no entra
# en una pantalla y lo que importa es lo que el driver tenga para decir.
const KEYWORDS := ["ERROR", "error", "shader", "Shader", "SHADER", "WARNING", "GLES", "lightmap"]

var _label: Label
var _elapsed := 0.0
var _done := false

static func _wants_overlay(os_name: String, env_value: String) -> bool:
	if env_value.to_lower().strip_edges() in ["1", "true", "yes", "on"]:
		return true
	return os_name == "iOS"

func _ready() -> void:
	if not _wants_overlay(OS.get_name(), OS.get_environment(ENV_FLAG)):
		queue_free()
		return
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	layer.add_child(bg)
	_label = Label.new()
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.margin_left = 10
	_label.margin_top = 8
	_label.autowrap = true
	_label.text = "LOG OVERLAY: leyendo en %ds..." % int(READ_DELAY)
	layer.add_child(_label)
	call_deferred("_build_shading_probe")
	call_deferred("_reassign_lightmaps")
	set_process(true)


# La sonda de sombreado ya mostro que la iluminacion por pixel funciona en iOS (los dos
# planos degradan igual que en escritorio), y el censo mostro que de las 39 mallas
# horneadas solo UNA tiene material con mas de una textura. O sea que no hay agotamiento
# de unidades de textura: el shader de esas mallas es albedo + lightmap y nada mas.
#
# Lo que queda es la ASIGNACION del lightmap. BakedLightmap la hace al entrar al arbol
# resolviendo la ruta de cada usuario contra si mismo; si esa resolucion falla, o si el
# renderer de iOS ignora la asignacion, el resultado se ve igual: albedo crudo.
#
# Esta prueba la rehace a mano y cuenta que paso:
#   reasignados=39 y aparece el verde -> era la asignacion (timing o rutas)
#   reasignados=39 y sigue morado     -> el renderer de iOS ignora el lightmap; es
#                                        limitacion del motor, no del proyecto
#   reasignados<39                    -> hay rutas que no resuelven, y el numero dice
#                                        cuantas
var _lm_ok := 0
var _lm_fail := 0

func _reassign_lightmaps() -> void:
	var baked = _find_baked(get_tree().get_root())
	if baked == null or baked.light_data == null:
		_lm_fail = -1
		return
	var data = baked.light_data
	for i in range(data.get_user_count()):
		var tex = data.get_user_lightmap(i)
		var node = baked.get_node_or_null(data.get_user_path(i))
		if tex == null or node == null or not (node is VisualInstance):
			_lm_fail += 1
			continue
		VisualServer.instance_set_use_lightmap(
			node.get_instance(), baked.get_instance(), tex.get_rid(), -1, Rect2(0, 0, 1, 1))
		_lm_ok += 1

func _find_baked(node: Node):
	if node is BakedLightmap:
		return node
	for child in node.get_children():
		var found = _find_baked(child)
		if found != null:
			return found
	return null


# Dos planos IGUALES salvo en cantidad de vertices, con su propia luz, frente a la
# camara. Separa las dos causas que quedan y que desde afuera se ven igual:
#
#   el subdividido degrada suave y el plano entero no  -> iluminacion POR VERTICE
#   los dos se ven igual de mal (planos, o uno negro)  -> NORMALES rotas
#   los dos degradan suave                             -> la iluminacion esta bien
#                                                         aca y el problema es del
#                                                         lightmap de las mallas
func _build_shading_probe() -> void:
	var cam := get_viewport().get_camera()
	if cam == null:
		return
	var holder := Spatial.new()
	cam.add_child(holder)
	holder.translation = Vector3(0, -0.30, -1.4)

	var mat := SpatialMaterial.new()
	mat.albedo_color = Color(0.85, 0.85, 0.85)
	mat.roughness = 1.0
	mat.metallic = 0.0

	for i in range(2):
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.5, 0.5)
		# 0 subdivisiones = 4 vertices; 24 = una malla densa. Misma superficie.
		plane.subdivide_width = 0 if i == 0 else 24
		plane.subdivide_depth = 0 if i == 0 else 24
		var mi := MeshInstance.new()
		mi.mesh = plane
		mi.material_override = mat
		mi.cast_shadow = MeshInstance.SHADOW_CASTING_SETTING_OFF
		mi.rotation_degrees = Vector3(90, 0, 0) # el plano mira a la camara
		mi.translation = Vector3(-0.32 + 0.64 * i, 0, 0)
		holder.add_child(mi)

	# Luz propia, para no depender de como este iluminado el lugar. Calibrada contra una
	# captura en escritorio: tiene que quedar un degradado CLARO a lo ancho del plano,
	# ni saturado en blanco ni tan tenue que no se distinga.
	var light := OmniLight.new()
	light.omni_range = 0.55
	light.light_energy = 1.1
	light.omni_attenuation = 1.0
	light.translation = Vector3(0, 0.34, 0.16)
	light.shadow_enabled = false
	holder.add_child(light)

func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed < READ_DELAY:
		return
	_done = true
	set_process(false)
	_label.text = _read_report()

func _list_dir(dir_path: String) -> String:
	var d := Directory.new()
	if d.open(dir_path) != OK:
		return "(no abre)"
	var names := []
	d.list_dir_begin(true, true)
	var n := d.get_next()
	while n != "" and names.size() < 8:
		names.append(n)
		n = d.get_next()
	d.list_dir_end()
	if names.empty():
		return "(vacio)"
	return PoolStringArray(names).join(", ")


func _read_report() -> String:
	var path := String(ProjectSettings.get_setting("logging/file_logging/log_path"))
	if path == "":
		path = "user://logs/godot.log"

	var f := File.new()
	if not f.file_exists(path):
		# Que no este el archivo ya nos costo un build. Si vuelve a faltar, que al menos
		# diga que SI hay en user://, para saber si el problema es el setting o la ruta.
		return "LOG OVERLAY  lightmap ok=%d fallos=%d\nNO EXISTE %s\nenable=%s\nuser:// -> %s\nuser://logs -> %s" % [
			_lm_ok,
			_lm_fail,
			path,
			ProjectSettings.get_setting("logging/file_logging/enable_file_logging"),
			_list_dir("user://"),
			_list_dir("user://logs"),
		]
	if f.open(path, File.READ) != OK:
		return "LOG OVERLAY\nno se pudo abrir %s" % path

	var hits := []
	var total := 0
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		total += 1
		for k in KEYWORDS:
			if line.find(k) != -1:
				hits.append(line)
				break
	f.close()

	var head := "LOG OVERLAY  lineas=%d  interesantes=%d  lightmap ok=%d fallos=%d" % [
		total, hits.size(), _lm_ok, _lm_fail]
	if hits.empty():
		# Que no haya ni un error tambien es un resultado: los shaders linkean y el
		# problema esta en la asignacion, no en la compilacion.
		return head + "\n(sin errores ni warnings en el log)"
	var shown = hits
	if shown.size() > MAX_LINES:
		shown = shown.slice(shown.size() - MAX_LINES, shown.size() - 1)
	return head + "\n" + PoolStringArray(shown).join("\n")
