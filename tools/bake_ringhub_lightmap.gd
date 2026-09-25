extends SceneTree

# tools/bake_ringhub_lightmap.gd — Bake headless de RingHub_Level (setup "todo encendido").
#
# Arma el pase de bake sin abrir el editor: instancia RingHub_Level, materializa el
# rig de luces de bake (RingHubBakeLights, que en la escena es un InstancePlaceholder
# para no costar en runtime), pone TODAS esas luces + el DirectionalLight en BAKE_ALL
# (encendidas para el bake) y hornea el BakedLightmap con las mismas perillas que el
# EditorScript (MEDIUM, denoiser on, atlas off, HDR off, color on, capture off).
#
# Uso:
#   tools/godot --path . --no-window -s tools/bake_ringhub_lightmap.gd
#
# Equivale a tools/editor_bake_ringhub_lightmap.gd, pero por -s (headless). Con el fork
# que trae el patch lightmap_bake_import (v0.5.0-nightly+), el run headless ya registra
# los importers y escribe PNG + .import igual que el editor; después corré
#   make bake-lightmap-postprocess DOME_LIGHTMAP_DATA_PATH=core_v2/levels/RingHub.lmbake \
#     DOME_LIGHTMAP_STAMP_DIR=build/lightmap-postprocess/ringhub \
#     DOME_LIGHTMAP_RAW_DIR=build/lightmap-raw/ringhub
# para el tinte Dome_Intro. Sin ese patch, cae a .tex crudos (lo que el postproceso no procesa).

const SCENE := "res://core_v2/levels/RingHub_Level.tscn"
const OUT := "res://core_v2/levels/RingHub.lmbake"
const RIG := "RingHubBakeLights"
# Multiplicador de energia SOLO para el bake ("full light"): previsualizar el domo
# bien claro sin tocar la escena ni las luces del rig. Default 1.0 = identico.
#   ODISEA_BAKE_LIGHT_MULT=3 tools/godot --path . --no-window -s tools/bake_ringhub_lightmap.gd
var _light_mult := 1.0
var _fast := false

func _init():
	var mult_env := OS.get_environment("ODISEA_BAKE_LIGHT_MULT").strip_edges()
	if mult_env.is_valid_float() and float(mult_env) > 0.0:
		_light_mult = float(mult_env)
	# Godot 3 no puede hornear MultiMeshInstance: los anillos superiores cambian a
	# pods instanciados (bakeables) cuando el script ve esta env. El runtime la
	# necesita igual para que existan los pods y reciban el lightmap.
	OS.set_environment("ODISEA_CRIOPOD_RING_INSTANCED", "1")
	# Iteracion rapida: ODISEA_BAKE_FAST=1 baja calidad y resoluciones (solo para
	# verificar membresia/estructura; el bake de produccion va a HIGH).
	_fast = OS.get_environment("ODISEA_BAKE_FAST") in ["1", "true", "yes", "on"]
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("bake: no pude cargar ", SCENE)
		quit(1)
		return
	var root: Node = ps.instance()
	get_root().add_child(root)

	var rig = root.get_node_or_null(RIG)
	if rig is InstancePlaceholder:
		(rig as InstancePlaceholder).replace_by_instance()
		rig = root.get_node_or_null(RIG)
	if rig == null:
		print("bake: sin rig ", RIG)
		quit(1)
		return
	if "bake_rig_enabled" in rig:
		rig.set("bake_rig_enabled", true)

	# El pool de luces runtime (MobileLightBudget) apaga luces fuera de presupuesto;
	# en el bake las queremos TODAS encendidas a la vez.
	_disable_light_pool()
	# Todas las luces del nivel encendidas para el bake, salvo las dinamicas del
	# jugador (linterna/fill): hornearlas dejaria un foco frito en el spawn.
	var lights := _enable_all_lights(root)
	print("bake: luces encendidas=", lights, " mult=", _light_mult)
	# lightmap_size_hint vive en el MESH (no en el MeshInstance). Se aplica aca a
	# las piezas grandes de bajo poligonaje para que el gradiente horneado sea mas
	# suave (el spotlight mostraba facetas sobre sus triangulos).
	_apply_bake_hints(root)
	# Los anillos de criopods superiores son MultiMeshInstance bajo
	# ScaffoldStreamRoot y el streamer los oculta/no-marca hasta acercarse. Para el
	# bake los queremos todos visibles y marcados.
	_force_criopod_visuals(root)
	# Andamios/domo/piso/pods proyectan sombra entre si en el bake (halos definidos).
	_enable_bake_shadows(root)

	var lm := _find_lm(root)
	if lm == null:
		print("bake: sin BakedLightmap")
		quit(1)
		return
	if lm.light_data == null or lm.light_data.resource_path == "":
		var data := BakedLightmapData.new()
		ResourceSaver.save(OUT, data)
		lm.light_data = load(OUT)
	lm.capture_enabled = false
	lm.quality = BakedLightmap.BAKE_QUALITY_LOW if _fast else BakedLightmap.BAKE_QUALITY_HIGH
	lm.set("atlas_generate", false)
	lm.use_denoiser = true
	lm.use_hdr = false
	lm.use_color = true
	print("bake: start -> ", OUT)
	var err: int = lm.bake(root, OUT)
	print("bake: result=", err)
	if lm.light_data != null:
		var ring := 0
		for i in range(lm.light_data.get_user_count()):
			var up := String(lm.light_data.get_user_path(i))
			if up.find("Criopods_Visual") != -1:
				ring += 1
				print("bake:   ring user ", up)
		print("bake: usuarios ring=", ring, " total=", lm.light_data.get_user_count())
	quit(0 if err == BakedLightmap.BAKE_ERROR_OK else 2)

func _disable_light_pool() -> void:
	var budget = get_root().get_node_or_null("MobileLightBudget")
	if budget != null and budget.has_method("set_budget_enabled"):
		budget.call("set_budget_enabled", false)
		print("bake: pool de luces (MobileLightBudget) desactivado")

func _force_criopod_visuals(n: Node) -> void:
	for c in n.get_children():
		if c is Spatial and String(c.get_path()).find("Criopods_Visual") != -1:
			(c as Spatial).visible = true
			if c is MultiMeshInstance:
				(c as MultiMeshInstance).use_in_baked_light = true
				print("bake:   visual anillo ", c.get_path())
		_force_criopod_visuals(c)

func _enable_bake_shadows(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance:
			var mi := c as MeshInstance
			var p := String(c.get_path())
			var name := String(mi.name)
			if (p.find("ScaffoldStreamRoot") != -1 or p.find("DomeInteriorLowPoly/DomeMesh") != -1 \
			or p.find("CombinedMesh") != -1 or p.find("Criopod") != -1) \
			and name.find("Glass") == -1 and name.find("PersonCard") == -1:
				mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_ON
		_enable_bake_shadows(c)

func _apply_bake_hints(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance and (c as MeshInstance).mesh != null:
			var p := String(c.get_path())
			if p.find("DomeInteriorLowPoly/DomeMesh") != -1 \
			or p.find("/RingFloor/CombinedMesh") != -1 \
			or p.find("/Floor_2/CombinedMesh") != -1 or p.find("/Floor_3/CombinedMesh") != -1 \
			or p.find("/Floor_4/CombinedMesh") != -1 or p.find("/Floor_5/CombinedMesh") != -1:
				var m = (c as MeshInstance).mesh
				if "lightmap_size_hint" in m:
					m.set("lightmap_size_hint", Vector2(256, 256) if _fast else Vector2(2048, 2048))
					print("bake:   hint -> ", p)
		_apply_bake_hints(c)

func _is_dynamic_light(path: String) -> bool:
	# Luces que NO deben hornearearse: linterna/fill del jugador e indicador del
	# pedestal (dinamicos, cambian en runtime).
	return path.find("/Pilot/") != -1 or path.find("/PedestalLight/") != -1

func _enable_all_lights(n: Node) -> int:
	var count := 0
	for c in n.get_children():
		if c is Light:
			var l := c as Light
			if _is_dynamic_light(String(l.get_path())):
				# Luces dinamicas (jugador e indicadores del pedestal): fuera del bake.
				l.visible = false
				l.light_bake_mode = Light.BAKE_DISABLED
				print("bake:   (excluida) ", l.get_path())
			else:
				l.visible = true
				l.light_bake_mode = Light.BAKE_ALL
				l.shadow_enabled = true
				l.light_energy *= _light_mult
				print("bake:   luz ", l.get_path(), " energy=", l.light_energy)
				count += 1
		count += _enable_all_lights(c)
	return count

func _find_dir(n: Node) -> DirectionalLight:
	for c in n.get_children():
		if c is DirectionalLight:
			return c
		var r := _find_dir(c)
		if r != null:
			return r
	return null

func _find_lm(n: Node) -> BakedLightmap:
	for c in n.get_children():
		if c is BakedLightmap:
			return c
		var r := _find_lm(c)
		if r != null:
			return r
	return null
