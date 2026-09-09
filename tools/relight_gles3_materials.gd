extends SceneTree

# Migracion GLES2 -> GLES3 de los materiales horneados del domo.
#
# Los materiales del andamio se autoraron cuando el proyecto corria en GLES2, que
# no soporta ReflectionProbe: sin fuente de entorno, el metal se veia plano y
# oscuro, asi que se compensaba a mano con tres trucos que en GLES3 quedan
# duplicados y se leen como "brillo de mas":
#
#   1. baranda naranja  -> emission = albedo * 0.18   (falso rebote; ahora glow real)
#   2. reja de acero    -> metallic_specular = 0.9    (falso especular directo)
#   3. tubos del marco  -> rim = 0.4                  (falso fresnel de borde)
#
# La fuente de estos materiales es core_v2/props/scaffold/SteelGratePlatform.gd
# (ya corregido), pero la geometria del domo esta horneada y sus .mesh apuntan a
# archivos .material externos y compartidos: parcharlos aca evita rehornear.
#
# Correr con:
#   godot3-bin --no-window --audio-driver Dummy --path . \
#     -s res://tools/relight_gles3_materials.gd
#
# Es idempotente: volver a correrlo no cambia nada.

const MAT_DIR := "res://core_v2/levels/interiors"

# Pase de metales. GLES2 no tiene ReflectionProbe, asi que un metallic alto se
# veia mate y se podia dejar en 1.0 sin costo. En GLES3 el probe del domo (y el
# especular GGX) lo convierten en espejo: los tubos de refrigerante y las valvulas
# quedaron con glare. Se baja el metallic y se sube el piso de rugosidad.
#
# Solo aplica a materiales SIN textura de metallic/roughness. Cuando hay textura
# ARM el 1.0 es un multiplicador y la textura es la autoridad: bajar el metallic
# ahi no quita glare, empuja la superficie a la zona medio-metal (~0.58 efectivo
# en los tubos del refrigerante) donde no lee ni como metal ni como plastico. El
# glare de esos tubos se ataca desde la luz (light_specular) y desde el probe,
# no desde el material.
const METAL_ROOTS := ["res://core_v2", "res://materials"]
const METAL_THRESHOLD := 0.8
const METAL_TARGET := 0.75
const ROUGHNESS_FLOOR := 0.45
# El vidrio no es metal: su reflejo es intencional.
const METAL_SKIP := ["res://core_v2/visual/GlassPanel.tres"]

# NO hay pase de doble cara. Lo hubo y estaba mal: los materiales horneados de los
# risers y los .mesh del kit de valvula estan en CULL_DISABLED a proposito, porque
# los tubos son CASCARAS ABIERTAS, no solidos. Medido cambiando el shader a la
# variante de doble cara y diferenciando el cuadro: la cara interna aporta 4-10%
# de los pixeles segun el angulo (valvula 7.4/9.8/4.4%, riser L1 6.8%), o sea que
# se ve por los extremos. Con CULL_BACK esos pixeles pasan a mostrar el fondo.
#
# El brillo del interior de los tubos que motivo todo esto NO venia de aca: era el
# overlay de interact_highlight.shader, que clonaba la malla con cull_disabled y la
# sumaba sin sombrear. Arreglado en core_v2/visual/interact_highlight.shader.

const LAMP_MESHES := [
	"res://core_v2/props/scifi_lights/IndustrialWallLampLow.mesh",
	"res://core_v2/props/scifi_lights/IndustrialWallLampLOD.mesh",
]
const LAMP_GLASS_SURFACE := 1
const LAMP_GLASS_ALBEDO := Color(0.45, 0.53, 0.63, 1)

var _changed := 0

func _init() -> void:
	_patch_materials()
	_patch_lamp_glass()
	_patch_metals()
	print("[relight] listo, recursos modificados: %d" % _changed)
	quit()

func _patch_materials() -> void:
	var dir := Directory.new()
	if dir.open(MAT_DIR) != OK:
		printerr("[relight] no pude abrir %s" % MAT_DIR)
		return
	dir.list_dir_begin(true, true)
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".material"):
			_patch_one(MAT_DIR.plus_file(name))
		name = dir.get_next()
	dir.list_dir_end()

func _patch_one(path: String) -> void:
	var mat = load(path)
	if not (mat is SpatialMaterial):
		return
	var m := mat as SpatialMaterial
	var notes := []

	# 1. Baranda: la firma del material naranja de SteelGratePlatform.
	if m.emission_enabled and _near(m.metallic, 0.32) and _near(m.roughness, 0.44):
		m.emission_enabled = false
		notes.append("emission off")

	# 2. Reja: el boost de especular directo ya no hace falta con ReflectionProbe.
	if _near(m.metallic_specular, 0.9):
		m.metallic_specular = 0.5
		notes.append("specular 0.9->0.5")

	# 3. Marco y baranda: el rim era un fresnel falso, ahora se suma al real.
	if m.rim_enabled:
		m.rim_enabled = false
		notes.append("rim off")

	if notes.empty():
		return
	var err := ResourceSaver.save(path, m)
	if err != OK:
		printerr("[relight] no pude guardar %s (%d)" % [path, err])
		return
	_changed += 1
	print("[relight] %s: %s" % [path.get_file(), PoolStringArray(notes).join(", ")])

func _patch_lamp_glass() -> void:
	for path in LAMP_MESHES:
		var mesh = load(path)
		if not (mesh is ArrayMesh):
			printerr("[relight] %s no es ArrayMesh" % path)
			continue
		var am := mesh as ArrayMesh
		if am.get_surface_count() <= LAMP_GLASS_SURFACE:
			printerr("[relight] %s no tiene superficie de vidrio" % path)
			continue
		var mat = am.surface_get_material(LAMP_GLASS_SURFACE)
		if not (mat is SpatialMaterial):
			continue
		var m := mat as SpatialMaterial
		if m.albedo_color.is_equal_approx(LAMP_GLASS_ALBEDO):
			continue
		m.albedo_color = LAMP_GLASS_ALBEDO
		var err := ResourceSaver.save(path, am)
		if err != OK:
			printerr("[relight] no pude guardar %s (%d)" % [path, err])
			continue
		_changed += 1
		print("[relight] %s: vidrio -> %s" % [path.get_file(), str(LAMP_GLASS_ALBEDO)])

func _patch_metals() -> void:
	var files := []
	for root in METAL_ROOTS:
		_collect(root, files)
	for path in files:
		var res = load(path)
		if res is SpatialMaterial:
			if _tame_metal(res, path) and _save(path, res):
				print("[relight] %s: metal domado" % path.get_file())
		elif res is ArrayMesh:
			var mesh := res as ArrayMesh
			var touched := false
			for i in range(mesh.get_surface_count()):
				var m = mesh.surface_get_material(i)
				# Solo materiales embebidos: los externos ya se visitan por su archivo.
				if m is SpatialMaterial and m.resource_path.find("::") != -1:
					touched = _tame_metal(m, path) or touched
			if touched and _save(path, mesh):
				print("[relight] %s: metal domado" % path.get_file())

func _tame_metal(m: SpatialMaterial, path: String) -> bool:
	if path in METAL_SKIP:
		return false
	# PBR guiado por textura: la textura manda, no se toca.
	if m.metallic_texture != null or m.roughness_texture != null:
		return false
	# Solo el metal que de verdad espejea: metallic alto Y rugosidad baja.
	if m.metallic < METAL_THRESHOLD or m.roughness >= ROUGHNESS_FLOOR:
		return false
	m.metallic = METAL_TARGET
	m.roughness = ROUGHNESS_FLOOR
	return true

func _save(path: String, res: Resource) -> bool:
	var err := ResourceSaver.save(path, res)
	if err != OK:
		printerr("[relight] no pude guardar %s (%d)" % [path, err])
		return false
	_changed += 1
	return true

func _collect(dir_path: String, out: Array) -> void:
	var d := Directory.new()
	if d.open(dir_path) != OK:
		return
	d.list_dir_begin(true, true)
	var name := d.get_next()
	while name != "":
		var full := dir_path.plus_file(name)
		if d.current_is_dir():
			_collect(full, out)
		elif name.ends_with(".tres") or name.ends_with(".material") or name.ends_with(".mesh"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()

func _near(a: float, b: float) -> bool:
	return abs(a - b) < 0.001
