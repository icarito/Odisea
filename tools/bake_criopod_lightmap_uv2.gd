extends SceneTree

# tools/bake_criopod_lightmap_uv2.gd
#
# Genera UV2 (lightmap_unwrap) en los MeshInstance con use_in_baked_light de los
# props de criopod y lo persiste en la escena. Sin UV2 el BakedLightmap saltea la
# malla (el pod de Elias y los parallax no recibian luz cocinada). El UV2 queda
# guardado: tanto el bake como el runtime leen el mismo.
#
# Uso:
#   tools/godot --path . --no-window -s tools/bake_criopod_lightmap_uv2.gd

const SCENES := [
	"res://core_v2/props/criopod/Criopod_vert.tscn",
	"res://core_v2/props/criopod/CriopodParallax.tscn",
	"res://core_v2/props/criopod/CriopodParallaxFull.tscn",
	# Anillos 3..6: capas MultiMesh (shell/glass/cards) decorativas.
	"res://core_v2/levels/chunks/ringhub/RingHub_Criopods3_visual.tscn",
	"res://core_v2/levels/chunks/ringhub/RingHub_Criopods4_visual.tscn",
	"res://core_v2/levels/chunks/ringhub/RingHub_Criopods5_visual.tscn",
	"res://core_v2/levels/chunks/ringhub/RingHub_Criopods6_visual.tscn",
]
const TEXEL_SIZE := 4.0

func _init():
	var total := 0
	for path in SCENES:
		var ps: PackedScene = load(path)
		if ps == null:
			print("uv2: no pude cargar ", path)
			continue
		var root = ps.instance()
		var n := _process(root)
		total += n
		if n > 0:
			var out := PackedScene.new()
			var err: int = out.pack(root)
			if err == OK:
				err = ResourceSaver.save(path, out)
			print("uv2: ", path, " mallas=", n, " save err=", err)
		else:
			print("uv2: ", path, " sin cambios")
		root.free()
	print("uv2: total mallas con UV2 nueva=", total)
	quit()

func _process(n: Node) -> int:
	var count := 0
	if n is MultiMeshInstance:
		count += _fix_multimesh(n as MultiMeshInstance)
	elif n is MeshInstance:
		count += _fix(n as MeshInstance)
	for c in n.get_children():
		count += _process(c)
	return count

func _fix_multimesh(mmi: MultiMeshInstance) -> int:
	if not mmi.use_in_baked_light or mmi.multimesh == null or not (mmi.multimesh.mesh is ArrayMesh):
		return 0
	var am := mmi.multimesh.mesh as ArrayMesh
	if _has_uv2(am):
		return 0
	var err: int = am.lightmap_unwrap(mmi.transform, TEXEL_SIZE)
	if err != OK:
		print("uv2:   (fallo unwrap multim) ", mmi.name, " err=", err)
		return 0
	mmi.multimesh.mesh = am
	_persist(am)
	print("uv2:   unwrap multim ", mmi.name, " count=", mmi.multimesh.instance_count)
	return 1

# Los .mesh externos se comparten entre escenas: si el UV2 queda solo en memoria,
# al recargar el archivo no lo tiene. Guardarlo en su resource_path lo fija para
# todas las escenas que lo referencian.
func _persist(am: ArrayMesh) -> void:
	if am.resource_path != "":
		var e: int = ResourceSaver.save(am.resource_path, am)
		print("uv2:     persist ", am.resource_path, " err=", e)

func _fix(mi: MeshInstance) -> int:
	if not mi.use_in_baked_light or mi.mesh == null:
		return 0
	if not (mi.mesh is ArrayMesh):
		print("uv2:   (primitivo, sin UV2 posible) ", mi.name, " class=", mi.mesh.get_class())
		return 0
	var am := mi.mesh as ArrayMesh
	if _has_uv2(am):
		return 0
	# En Godot 3 lightmap_unwrap() es IN-PLACE y devuelve Error.
	var err: int = am.lightmap_unwrap(mi.transform, TEXEL_SIZE)
	if err != OK:
		print("uv2:   (fallo unwrap) ", mi.name, " err=", err)
		return 0
	mi.mesh = am
	_persist(am)
	print("uv2:   unwrap ", mi.name, " surfaces=", am.get_surface_count())
	return 1

func _has_uv2(am: ArrayMesh) -> bool:
	for s in range(am.get_surface_count()):
		if am.surface_get_format(s) & Mesh.ARRAY_FORMAT_TEX_UV2:
			return true
	return false
