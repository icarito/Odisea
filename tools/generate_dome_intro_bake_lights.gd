extends SceneTree

# Genera el rig de luces de bake desde los fixtures reales de una escena de domo.
# Es una fuente reproducible: las posiciones de los OmniLights no se copian a
# mano desde el editor ni dependen de los pools dinámicos de LightPathV2.
#
# Uso:
#   godot3-bin --no-window -s tools/generate_dome_intro_bake_lights.gd
#   godot3-bin --no-window -s tools/generate_dome_intro_bake_lights.gd -- --mode=dark
#   godot3-bin --no-window -s tools/generate_dome_intro_bake_lights.gd -- --scene=Dome_Prologue
#
# --mode (FD-284):
#   full  Todas las luces del rig. Es el rig histórico y el default.
#   near  Alias de `full`, por compatibilidad. NO existe ningún filtro de cercanía
#         en el horneado: el recorte "por cercanía" es el pool runtime de
#         LightPathV2/MobileLightBudget, que ocurre en juego y no en el bake.
#   dark  Rig sin ningún fixture: el .lmbake resultante lleva solo el ambiente de
#         BakedLightmap. Es el estado OSCURAS / la base de BAJO CONSUMO.
#
# --wall-energy / --wall-range (FD-284): energia y alcance de las luces de fixture
# de pared EN EL HORNEADO. Es la perilla real para "que los wall lights aporten mas
# luz, como si siempre estuviesen encendidos": el postproceso del PNG
# (BRIGHTNESS/CONTRAST) solo re-grada lo ya horneado y levanta por igual las zonas
# que ningun fixture ilumino, que es lo que aplana la escena. Subir esto y volver a
# hornear es lo unico que hace que la luz salga DE los fixtures.
#
# --scene: nombre de la escena de domo (default Dome_Intro). Dome_Prologue no
# tiene BakedLightmap propio hoy, pero el nombre no se hardcodea para no repetir
# el bug de rutas que dejó este script apuntando a nodos que ya no existían.

const SCENE_DIR := "res://core_v2/levels/interiors"
# Los pools de luces y los marcadores viven en Dome_Base, que Dome_Intro y
# Dome_Prologue instancian. Antes se buscaban en la raíz y el script emitía cero
# luces en silencio desde que Dome_Base se extrajo.
const BASE_PATH := "Dome_Base"

func _init() -> void:
	var mode := _arg("mode", "full")
	var scene_name := _arg("scene", "Dome_Intro")
	var wall_energy := float(_arg("wall-energy", "0.72"))
	var wall_range := float(_arg("wall-range", "8.0"))
	if mode == "near":
		print("[bake_lights] AVISO: 'near' es alias de 'full'; el bake nunca filtró por cercanía.")
		mode = "full"
	if not mode in ["full", "dark"]:
		push_error("[bake_lights] modo inválido '%s' (full|dark|near)" % mode)
		quit(1)
		return

	var source_path := "%s/%s.tscn" % [SCENE_DIR, scene_name]
	var source := load(source_path) as PackedScene
	if source == null:
		push_error("[bake_lights] missing source %s" % source_path)
		quit(1)
		return
	var dome := source.instance()
	var rig := Spatial.new()
	rig.name = "DomeIntroBakeLights"
	rig.script = load("res://core_v2/levels/interiors/DomeIntroBakeLightRig.gd")
	rig.set("bake_rig_enabled", false)

	if mode == "full":
		_add_wall_fixture_lights(dome, rig, wall_energy, wall_range)
		_add_position_lights(dome, rig, "HubExitLights", Color(1.0, 0.14, 0.1, 1.0), 1.2, 5.0, "HubExit")
		_add_position_lights(dome, rig, "DomeLamp", Color(1.0, 0.97, 0.88, 1.0), 1.8, 24.0, "DomeCore")
		_add_position_lights(dome, rig, "DomeLampCrown", Color(0.78, 0.9, 1.0, 1.0), 0.9, 10.0, "DomeCrown")
	else:
		print("[bake_lights] modo dark: rig sin fixtures, solo ambiente de BakedLightmap.")

	var packed := PackedScene.new()
	var packed_error: int = packed.pack(rig)
	if packed_error != OK:
		push_error("[bake_lights] pack failed: %d" % packed_error)
		quit(1)
		return
	var out_scene := _out_scene(scene_name, mode)
	var save_error: int = ResourceSaver.save(out_scene, packed)
	if save_error != OK:
		push_error("[bake_lights] save failed: %d" % save_error)
		quit(1)
		return
	print("[bake_lights] saved %s (%d static bake lights, mode=%s)" % [out_scene, rig.get_child_count(), mode])
	quit(0)

# El rig `full` conserva su nombre histórico: Dome_Intro.tscn lo referencia por
# ruta como instance_placeholder y renombrarlo rompería la escena.
static func _out_scene(scene_name: String, mode: String) -> String:
	var stem: String = scene_name.replace("_", "")
	if mode == "full":
		return "%s/%s_BakeLights.tscn" % [SCENE_DIR, stem]
	return "%s/%s_BakeLights_%s.tscn" % [SCENE_DIR, stem, mode]

func _arg(name: String, fallback: String) -> String:
	for raw in OS.get_cmdline_args():
		var arg := String(raw)
		if arg.begins_with("--%s=" % name):
			return arg.substr(len(name) + 3, len(arg))
	return fallback

func _add_wall_fixture_lights(dome: Node, rig: Spatial, energy: float, light_range: float) -> void:
	var wall_lights := dome.get_node_or_null("%s/WallLights" % BASE_PATH)
	if wall_lights == null:
		push_error("[bake_lights] WallLights missing")
		return
	var added := 0
	for child in wall_lights.get_children():
		if not (child is MultiMeshInstance) or not String(child.name).begins_with("FixtureBatch_"):
			continue
		var fixture_batch := child as MultiMeshInstance
		if fixture_batch.multimesh == null:
			continue
		for index in range(fixture_batch.multimesh.instance_count):
			# La escena se carga fuera del SceneTree para no inicializar gameplay;
			# por eso se compone el transform local explícitamente en vez de pedir
			# global_transform (que Godot devuelve como identidad fuera del árbol).
			# El pool de luces cuelga de Dome_Base, así que hay que arrastrar
			# también el transform de esa instancia.
			var fixture_xform: Transform = _to_dome(fixture_batch, dome) * fixture_batch.multimesh.get_instance_transform(index)
			var light := _make_light("WallFixture_%03d" % added, Color(0.72, 0.84, 1.0, 1.0), energy, light_range)
			light.transform = Transform(Basis(), fixture_xform.xform(Vector3(0.0, 0.0, 0.11)))
			rig.add_child(light)
			light.owner = rig
			added += 1
	print("[bake_lights] wall fixtures: %d (energy=%.2f range=%.1f)" % [added, energy, light_range])

func _add_position_lights(dome: Node, rig: Spatial, path: String, color: Color, energy: float, light_range: float, prefix: String) -> void:
	var source := dome.get_node_or_null("%s/%s" % [BASE_PATH, path])
	if source == null:
		push_error("[bake_lights] %s missing" % path)
		return
	var added := 0
	for child in source.get_children():
		if not (child is Position3D):
			continue
		var marker := child as Position3D
		var light := _make_light("%s_%02d" % [prefix, added], color, energy, light_range)
		light.transform = Transform(Basis(), _to_dome(marker, dome).origin)
		rig.add_child(light)
		light.owner = rig
		added += 1
	print("[bake_lights] %s: %d" % [prefix, added])

# Transform del nodo relativo a la raíz del domo. Se compone a mano porque la
# escena está fuera del SceneTree (global_transform ahí devuelve identidad) y
# porque los pools ya no cuelgan de la raíz sino de la instancia Dome_Base.
static func _to_dome(node: Spatial, dome: Node) -> Transform:
	var xform := Transform()
	var current: Node = node
	while current != null and current != dome:
		if current is Spatial:
			xform = (current as Spatial).transform * xform
		current = current.get_parent()
	return xform

func _make_light(light_name: String, color: Color, energy: float, light_range: float) -> OmniLight:
	var light := OmniLight.new()
	light.name = light_name
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	light.light_bake_mode = 0
	light.visible = false
	return light
