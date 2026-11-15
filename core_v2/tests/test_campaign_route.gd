extends GdUnitTestSuite

# Test de alcanzabilidad de la ruta principal de campaña (Transit-Run).
#
# Recorre el grafo de transiciones REAL desde Menu.FIRST_GAME_SCENE inspeccionando:
#   - Nodos con `target_scene` / `target_spawn_id` (HangarTransition, AirlockZoneV2,
#     TubeAirlock, BayTransitionBuffer, TransitionPortal)
#   - Config del domo (DomeSystemDirector / DomeEnvConfig) y DomeRegistry
#   - Scripts activos de conectores (p.ej. BayAirlockTrigger -> RingHubLightState.enter_machine_bay)
#     y llamadas literales a `goto_scene(...)` en scripts de la escena
#   - Existencia real de cada `target_scene` y de cada `SpawnPointV2.spawn_id` en destino.
#
# Falla si algún nivel requerido del slice queda inalcanzable desde FIRST_GAME_SCENE
# o si un target_scene / target_spawn_id apunta a un destino inexistente.

const MenuScript = preload("res://core_v2/ui/Menu.gd")
const BayAirlockTriggerScript = preload("res://core_v2/props/tube/BayAirlockTrigger.gd")
const HangarTransitionScript = preload("res://core_v2/props/hangar/HangarTransition.gd")
const AirlockZoneScript = preload("res://core_v2/components/AirlockZoneV2.gd")

const DOME_INTRO := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const DOME_HANGAR := "res://core_v2/levels/interiors/Dome_Intro_Hangar.tscn"
const RING_HUB := "res://core_v2/levels/RingHub_Level.tscn"
const MACHINE_BAY := "res://core_v2/levels/machines/MachineBay.tscn"
const BAY_VERTICAL := "res://core_v2/levels/bay_vertical/BayVertical.tscn"

# Niveles alcanzables ya cableados en la línea principal desde FIRST_GAME_SCENE.
const REQUIRED_REACHABLE_SCENES := [
	DOME_INTRO,
	DOME_HANGAR,
	RING_HUB,
	MACHINE_BAY,
]

# TODO(src-61, src-57): mover BayVertical y la salida por la cima a REQUIRED_REACHABLE_SCENES
# cuando las pistas paralelas cableen MachineBay -> BayVertical -> cima;
# TODO(src-63): insertar el tramo MagRail entre Dome_Intro_Hangar y RingHub_Level.
const SLICE_FULL_LINE_SCENES := [
	DOME_INTRO,
	DOME_HANGAR,
	RING_HUB,
	MACHINE_BAY,
	BAY_VERTICAL,
]


func _as_str(val) -> String:
	if val == null:
		return ""
	return str(val).strip_edges()


func _as_scene_path(val) -> String:
	if typeof(val) != TYPE_STRING:
		return ""
	return String(val).strip_edges()


func _collect_nodes(root: Node, out: Array) -> void:
	out.append(root)
	for child in root.get_children():
		_collect_nodes(child, out)


func _collect_spawn_ids(scene_root: Node) -> Array:
	var ids := []
	var nodes := []
	_collect_nodes(scene_root, nodes)
	for n in nodes:
		if n is Position3D and "spawn_id" in n:
			var sid := String(n.get("spawn_id")).strip_edges()
			if sid != "":
				ids.append(sid)
	return ids


func _extract_goto_scene_literals(script_res: Script) -> Array:
	var targets := []
	if script_res == null:
		return targets
	var path := String(script_res.resource_path)
	if path == "" or not File.new().file_exists(path):
		return targets
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return targets
	var src := f.get_as_text()
	f.close()

	var regex := RegEx.new()
	regex.compile("goto_scene\\(\\s*\"(res://[^\"]+\\.tscn)\"")
	for m in regex.search_all(src):
		var target := String(m.get_string(1)).strip_edges()
		if target != "" and not targets.has(target):
			targets.append(target)
	return targets


func _discover_edges_for_scene(scene_path: String) -> Array:
	var edges := []
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return edges
	var root := packed.instance()
	if root == null:
		return edges

	# Evitar que RingHubWakeup abra UI diferida durante la inspección estática.
	if "open_pod_terminal_on_start" in root:
		root.set("open_pod_terminal_on_start", false)

	var nodes := []
	_collect_nodes(root, nodes)

	var light_state: Node = root.get_node_or_null("LightState")
	var director := get_node_or_null("/root/DomeSystemDirector")

	for n in nodes:
		var scr: Script = n.get_script() as Script

		# 1. HangarTransition: usa export o DomeSystemDirector.get_hangar_scene()
		if scr == HangarTransitionScript or n is HangarTransitionScript:
			var ht_target := _as_str(n.get("target_scene"))
			var ht_spawn := _as_str(n.get("target_spawn_id"))
			if ht_target == "" and bool(n.get("use_dome_config")) and director != null:
				ht_target = _as_str(director.call("get_hangar_scene"))
				if ht_spawn == "":
					ht_spawn = _as_str(director.call("get_hangar_spawn_id"))
			if ht_target != "":
				edges.append({
					"from": scene_path,
					"to": ht_target,
					"spawn_id": ht_spawn,
					"via": str(n.name),
				})
			continue

		# 2. BayAirlockTrigger (conector real RingHub -> MachineBay)
		if scr == BayAirlockTriggerScript or n is BayAirlockTriggerScript:
			var bay_target := "res://core_v2/levels/machines/MachineBay.tscn"
			if light_state != null and "machine_bay_scene_path" in light_state:
				bay_target = _as_str(light_state.get("machine_bay_scene_path"))
			edges.append({
				"from": scene_path,
				"to": bay_target,
				"spawn_id": "",
				"via": str(n.name),
			})
			continue

		# 3. Nodos con target_scene explícito (AirlockZoneV2, TubeAirlock, BayTransitionBuffer, etc.)
		if "target_scene" in n:
			var t_scene := _as_scene_path(n.get("target_scene"))
			var t_spawn := _as_str(n.get("target_spawn_id")) if "target_spawn_id" in n else ""
			if scr == AirlockZoneScript or n is AirlockZoneScript:
				var dome_id := _as_str(n.get("dome_id")) if "dome_id" in n else ""
				var dome_registry := get_node_or_null("/root/DomeRegistry")
				if dome_id != "" and dome_registry != null and dome_registry.has_method("get_dome"):
					var info: Dictionary = dome_registry.get_dome(dome_id)
					if not info.empty() and _as_str(info.get("interior_scene", "")) != "":
						var interior := _as_str(info.get("interior_scene", ""))
						var ext_spawn := _as_str(info.get("spawn_id_from_exterior", ""))
						edges.append({
							"from": scene_path,
							"to": interior,
							"spawn_id": ext_spawn,
							"via": "%s(DomeRegistry:%s)" % [str(n.name), dome_id],
						})
			if t_scene != "":
				edges.append({
					"from": scene_path,
					"to": t_scene,
					"spawn_id": t_spawn,
					"via": str(n.name),
				})
			continue

		# 4. Scripts de la escena con llamadas literales a goto_scene("res://...tscn")
		# (excluyendo RingHubLightState cuando los pedestales de debug están desactivados).
		if scr != null:
			if n == light_state and "debug_pedestals_enabled" in n and not bool(n.get("debug_pedestals_enabled")):
				continue
			for lit_target in _extract_goto_scene_literals(scr):
				edges.append({
					"from": scene_path,
					"to": lit_target,
					"spawn_id": "",
					"via": "%s(%s)" % [String(n.name), String(scr.resource_path).get_file()],
				})

	root.free()
	return edges


func test_first_game_scene_is_dome_intro_and_maintenance_enabled() -> void:
	assert_str(MenuScript.FIRST_GAME_SCENE).is_equal(DOME_INTRO)
	var director := get_node_or_null("/root/DomeSystemDirector")
	assert_object(director).is_not_null()
	assert_bool(director.is_maintenance_override_enabled()).is_true()


func test_ringhub_debug_pedestals_disabled_by_default() -> void:
	var packed := load(RING_HUB) as PackedScene
	assert_object(packed).is_not_null()
	var hub: Node = auto_free(packed.instance())
	if "open_pod_terminal_on_start" in hub:
		hub.set("open_pod_terminal_on_start", false)
	add_child(hub)
	yield(get_tree(), "idle_frame")
	var light_state: Node = hub.get_node_or_null("LightState")
	assert_object(light_state).is_not_null()
	assert_bool(bool(light_state.get("debug_pedestals_enabled"))).is_false()
	var ped_bay := hub.get_node_or_null("Hub/PedestalMachineBay") as Spatial
	var ped_vert := hub.get_node_or_null("Hub/PedestalBayVertical") as Spatial
	assert_object(ped_bay).is_not_null()
	assert_object(ped_vert).is_not_null()
	assert_bool(ped_bay.visible).is_false()
	assert_bool(ped_vert.visible).is_false()


func test_campaign_route_reachability_and_valid_targets() -> void:
	var start_scene := String(MenuScript.FIRST_GAME_SCENE).strip_edges()
	assert_bool(ResourceLoader.exists(start_scene)).is_true()

	var visited := {}
	var queue := [start_scene]
	var all_edges := []

	while not queue.empty():
		var current := String(queue.pop_front())
		if visited.has(current):
			continue
		visited[current] = true
		assert_bool(ResourceLoader.exists(current)).is_true()

		var edges := _discover_edges_for_scene(current)
		for edge in edges:
			all_edges.append(edge)
			var target := String(edge["to"])
			var spawn_id := String(edge["spawn_id"])

			# Cada target_scene descubierto en la ruta debe existir en disco.
			assert_bool(ResourceLoader.exists(target)).override_failure_message(
				"target_scene inexistente '%s' desde '%s' via '%s'" % [target, current, edge["via"]]
			).is_true()

			# Si declara target_spawn_id, debe existir un SpawnPointV2 en el destino.
			if spawn_id != "":
				var target_packed := load(target) as PackedScene
				assert_object(target_packed).is_not_null()
				var target_root := target_packed.instance()
				var spawns := _collect_spawn_ids(target_root)
				target_root.free()
				assert_array(spawns).override_failure_message(
					"spawn_id '%s' no encontrado en '%s' (desde '%s' via '%s'). Spawns: %s" % [
						spawn_id, target, current, edge["via"], str(spawns)
					]
				).contains([spawn_id])

			if not visited.has(target):
				queue.append(target)

	# Todos los niveles requeridos del slice actual deben ser alcanzables desde FIRST_GAME_SCENE.
	for required in REQUIRED_REACHABLE_SCENES:
		assert_bool(visited.has(required)).override_failure_message(
			"Nivel '%s' inalcanzable desde '%s'. Visitados: %s | Aristas: %s" % [
				required, start_scene, str(visited.keys()), str(all_edges)
			]
		).is_true()

	# Verificar que todas las escenas del slice completo existen (incluyendo las cableadas por pistas paralelas).
	for slice_scene in SLICE_FULL_LINE_SCENES:
		assert_bool(ResourceLoader.exists(slice_scene)).is_true()
