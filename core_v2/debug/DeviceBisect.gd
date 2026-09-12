extends Spatial

# Escena de biseccion para hardware sin editor ni comandos remotos (handhelds de
# PortMaster: build release). Un solo .pck cubre todos los pasos; se elige con
# ODISEA_BISECT_STEP y cada paso AGREGA al anterior, asi el primero que falla
# nombra al culpable. Se llega aca con ODISEA_BOOT_SCENE.
#
#   0  nada: solo camara y luz ambiente          (linea base del pipeline)
#   1  + cubo sin textura                        (geometria + material default)
#   2  + cubo con textura VRAM comprimida        (ETC1/ETC2 en la GPU)
#   3  + malla horneada de Dome_Intro            (.mesh del bake)
#   4  + material de Dome_Intro sobre esa malla  (shaders propios)

const TEX_PATH := "res://assets/textures/Ice/ice_0002_normal_directx_1k.png"
const MESH_PATH := "res://core_v2/levels/interiors/DomeIntro_Criopods2_shell.mesh"

var _step := 0
var _frames := 0

func _ready() -> void:
	_step = int(OS.get_environment("ODISEA_BISECT_STEP"))
	print("[Bisect] step=%d" % _step)

	var cam := Camera.new()
	cam.translation = Vector3(0, 1.5, 4)
	cam.current = true
	add_child(cam)

	var light := DirectionalLight.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	add_child(light)
	print("[Bisect] 0 camara+luz OK")

	if _step >= 1:
		var plain := MeshInstance.new()
		plain.mesh = CubeMesh.new()
		plain.translation = Vector3(-1.5, 1, 0)
		add_child(plain)
		print("[Bisect] 1 cubo sin textura OK")

	if _step >= 2:
		_add_textured_cube()

	if _step >= 3:
		_add_baked_mesh(false)

	if _step >= 4:
		_add_baked_mesh(true)

func _add_textured_cube() -> void:
	if not ResourceLoader.exists(TEX_PATH):
		printerr("[Bisect] 2 FALTA la textura en el pack: %s" % TEX_PATH)
		return
	var tex = load(TEX_PATH)
	if tex == null:
		printerr("[Bisect] 2 la textura no cargo: %s" % TEX_PATH)
		return
	var mat := SpatialMaterial.new()
	mat.albedo_texture = tex
	var mi := MeshInstance.new()
	mi.mesh = CubeMesh.new()
	mi.material_override = mat
	mi.translation = Vector3(1.5, 1, 0)
	add_child(mi)
	print("[Bisect] 2 cubo con textura VRAM OK (%dx%d)" % [tex.get_width(), tex.get_height()])

func _add_baked_mesh(keep_material: bool) -> void:
	var label := "4 malla horneada CON su material" if keep_material else "3 malla horneada SIN material"
	if not ResourceLoader.exists(MESH_PATH):
		printerr("[Bisect] %s FALTA en el pack: %s" % [label, MESH_PATH])
		return
	var mesh = load(MESH_PATH)
	if mesh == null:
		printerr("[Bisect] %s no cargo" % label)
		return
	var mi := MeshInstance.new()
	mi.mesh = mesh
	mi.translation = Vector3(0, 0, -2) if keep_material else Vector3(0, 0, -6)
	if not keep_material:
		# Sin material propio: aisla la geometria del shader.
		mi.material_override = SpatialMaterial.new()
	add_child(mi)
	print("[Bisect] %s OK (surfaces=%d)" % [label, mesh.get_surface_count()])

func _process(_delta: float) -> void:
	_frames += 1
	# Un reporte tardio: para entonces ya se dibujaron frames de verdad y el conteo
	# de draw calls dice si la GPU recibio trabajo o si no se emitio nada.
	if _frames == 120:
		print("[Bisect] frames=%d draws=%d verts=%d objetos=%d vram=%.1fMB" % [
			_frames,
			VisualServer.get_render_info(VisualServer.INFO_DRAW_CALLS_IN_FRAME),
			VisualServer.get_render_info(VisualServer.INFO_VERTICES_IN_FRAME),
			VisualServer.get_render_info(VisualServer.INFO_OBJECTS_IN_FRAME),
			VisualServer.get_render_info(VisualServer.INFO_VIDEO_MEM_USED) / 1048576.0
		])
		print("[Bisect] LISTO step=%d" % _step)
