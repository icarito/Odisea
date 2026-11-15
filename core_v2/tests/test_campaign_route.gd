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
const MachineLevelScript = preload("res://core_v2/props/machines/MachineLevel.gd")

const DOME_INTRO := "res://core_v2/levels/interiors/Dome_Intro.tscn"
const DOME_HANGAR := "res://core_v2/levels/interiors/Dome_Intro_Hangar.tscn"
const MAGRAIL_HANGAR_TO_RINGHUB := "res://core_v2/levels/MagRailHangarToRingHub.tscn"
const RING_HUB := "res://core_v2/levels/RingHub_Level.tscn"
const MACHINE_BAY := "res://core_v2/levels/machines/MachineBay.tscn"
const BAY_VERTICAL := "res://core_v2/levels/bay_vertical/BayVertical.tscn"

# Línea principal completa del slice, alcanzable desde FIRST_GAME_SCENE.
const REQUIRED_REACHABLE_SCENES := [
	DOME_INTRO,
	DOME_HANGAR,
	MAGRAIL_HANGAR_TO_RINGHUB,
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
			var t_airlock := _as_str(n.get("target_airlock_path")) if "target_airlock_path" in n else ""
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
							"airlock_path": "",
							"via": "%s(DomeRegistry:%s)" % [str(n.name), dome_id],
						})
			if t_scene != "":
				edges.append({
					"from": scene_path,
					"to": t_scene,
					"spawn_id": t_spawn,
					"airlock_path": t_airlock,
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


# Salida por la CIMA (fin del slice): buffer físico seamless BayVertical -> RingHub
# con spawn REAL y marcador de slice completado. Cableado por src-57 (pista E).
func test_bay_vertical_summit_exit_closes_slice() -> void:
	var packed := load(BAY_VERTICAL) as PackedScene
	assert_object(packed).is_not_null()
	var bay: Node = auto_free(packed.instance())
	add_child(bay)
	yield(get_tree(), "idle_frame")

	# El buffer de la cima es el que cierra el slice.
	var exit_buf: Node = bay.get_node_or_null("ExitBuffer")
	assert_object(exit_buf).is_not_null()
	assert_bool(bool(exit_buf.get("completes_slice"))).is_true()

	# Destino real: RingHub, con un spawn que EXISTE allí.
	var target := _as_scene_path(exit_buf.get("target_scene"))
	assert_str(target).is_equal(RING_HUB)
	assert_bool(ResourceLoader.exists(target)).is_true()
	var spawn_id := _as_str(exit_buf.get("target_spawn_id"))
	assert_str(spawn_id).is_equal("bay_vertical_return")
	var hub_packed := load(target) as PackedScene
	assert_object(hub_packed).is_not_null()
	var hub_root := hub_packed.instance()
	assert_array(_collect_spawn_ids(hub_root)).override_failure_message(
		"spawn_id '%s' no encontrado en '%s'" % [spawn_id, target]
	).contains([spawn_id])
	hub_root.free()

	# Marcador de "slice completado" (sin texto en el juego).
	var level: Node = bay.get_node_or_null("BayVerticalLevel")
	assert_object(level).is_not_null()
	assert_bool(bool(level.call("is_slice_completed"))).is_false()
	assert_bool(bool(level.call("complete_slice"))).is_true()
	assert_bool(bool(level.call("is_slice_completed"))).is_true()


# MachineBay -> BayVertical: la esclusa del ExitPad dispara la salida seamless hacia
# un spawn que EXISTE en la bahía radial y reenvía el payload de retorno al hub.
func test_machine_bay_exit_airlock_enters_bay_vertical_seamless() -> void:
	var manager := get_node_or_null("/root/SceneManager")
	var airlock := get_node_or_null("/root/AirlockManager")
	assert_object(manager).is_not_null()
	assert_object(airlock).is_not_null()

	var bay_root := (load(BAY_VERTICAL) as PackedScene).instance()
	assert_array(_collect_spawn_ids(bay_root)).contains([MachineLevelScript.BAY_VERTICAL_SPAWN_ID])
	bay_root.free()

	# El trigger vive dentro de la esclusa física y está cableado a la salida.
	var f := File.new()
	assert_int(f.open("res://core_v2/levels/machines/machine_bay.json", File.READ)).is_equal(OK)
	var items: Array = JSON.parse(f.get_as_text()).result["items"]
	f.close()
	var wired := false
	var names := []
	for item in items:
		names.append(str(item.get("name", "")))
		if item.get("type") == "link" and item.get("from") == "ExitLockTrigger" and item.get("to") == "@level":
			wired = str(item.get("method", "")) == "enter_bay_vertical"
	assert_bool(wired).is_true()
	assert_array(names).contains(["ExitLockWallL", "ExitLockWallR", "ExitLockBack", "ExitLockRoof", "ExitLockTrigger"])

	# Intercepción por la cola real del SceneManager (sin swap de escena en el test).
	var saved := {
		"is_transitioning": manager._is_transitioning,
		"pending_path": manager._pending_scene_path,
		"pending_params": manager._pending_transition_params.duplicate(true),
		"transition_params": manager._transition_params.duplicate(true),
	}
	# MachineLevel._ready() mueve las palancas de luz plana del gate: se devuelven al final.
	var gate := get_node_or_null("/root/GLES3VendorGate")
	var gate_saved := [] if gate == null else [gate.get("_flat_ambient"), gate.get("_world_light"), gate.get("_glow_floor")]
	var payload := {"wakeup": {"wakeup_completed": true}, "light_state": {"lit": true}}
	manager._transition_params = {"ringhub_return_state": payload.duplicate(true)}
	var level = MachineLevelScript.new()
	level.enable_player_multi_tool = false
	get_tree().root.add_child(level)
	manager._transition_params = saved["transition_params"].duplicate(true)
	manager._is_transitioning = true
	level.enter_bay_vertical()

	assert_str(manager._pending_scene_path).is_equal(BAY_VERTICAL)
	var params: Dictionary = manager._pending_transition_params
	assert_str(str(params.get("transition", ""))).is_equal("seamless")
	assert_bool(bool(params.get("preserve_player_state", true))).is_false()
	assert_str(str(params.get("target_spawn_id", ""))).is_equal("bay_vertical_entry")
	assert_dict(params.get("ringhub_return_state", {})).is_equal(payload)

	manager._is_transitioning = saved["is_transitioning"]
	manager._pending_scene_path = saved["pending_path"]
	manager._pending_transition_params = saved["pending_params"]
	level.free()
	if gate != null:
		gate.set_flat_ambient(gate_saved[0])
		gate.set_flat_world_light(gate_saved[1])
		gate.set_flat_glow_floor(gate_saved[2])


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
			var airlock_path := String(edge.get("airlock_path", ""))

			# Cada target_scene descubierto en la ruta debe existir en disco.
			assert_bool(ResourceLoader.exists(target)).override_failure_message(
				"target_scene inexistente '%s' desde '%s' via '%s'" % [target, current, edge["via"]]
			).is_true()

			# Si declara target_spawn_id o target_airlock_path, deben existir en la escena destino.
			if spawn_id != "" or airlock_path != "":
				var target_packed := load(target) as PackedScene
				assert_object(target_packed).is_not_null()
				var target_root := target_packed.instance()
				if spawn_id != "":
					var spawns := _collect_spawn_ids(target_root)
					assert_array(spawns).override_failure_message(
						"spawn_id '%s' no encontrado en '%s' (desde '%s' via '%s'). Spawns: %s" % [
							spawn_id, target, current, edge["via"], str(spawns)
						]
					).contains([spawn_id])
				if airlock_path != "":
					var target_airlock := target_root.get_node_or_null(NodePath(airlock_path))
					assert_object(target_airlock).override_failure_message(
						"target_airlock_path '%s' no encontrado en '%s' (desde '%s' via '%s')" % [
							airlock_path, target, current, edge["via"]
						]
					).is_not_null()
				target_root.free()

			if not visited.has(target):
				queue.append(target)

	# Todos los niveles requeridos del slice actual deben ser alcanzables desde FIRST_GAME_SCENE.
	for required in REQUIRED_REACHABLE_SCENES:
		assert_bool(visited.has(required)).override_failure_message(
			"Nivel '%s' inalcanzable desde '%s'. Visitados: %s | Aristas: %s" % [
				required, start_scene, str(visited.keys()), str(all_edges)
			]
		).is_true()


func test_hangar_to_ringhub_seamless_preposition_uses_matching_airlock() -> void:
	var hangar_packed := load(DOME_HANGAR) as PackedScene
	var magrail_packed := load(MAGRAIL_HANGAR_TO_RINGHUB) as PackedScene
	var hub_packed := load(RING_HUB) as PackedScene
	assert_object(hangar_packed).is_not_null()
	assert_object(magrail_packed).is_not_null()
	assert_object(hub_packed).is_not_null()

	var hangar: Node = auto_free(hangar_packed.instance())
	var magrail: Node = auto_free(magrail_packed.instance())
	var hub: Node = auto_free(hub_packed.instance())
	if "open_pod_terminal_on_start" in hub:
		hub.set("open_pod_terminal_on_start", false)
	add_child(hangar)
	add_child(magrail)
	add_child(hub)
	yield(get_tree(), "idle_frame")

	var hangar_exit_zone := hangar.get_node_or_null("Exit/Airlock_Exit/AirlockZoneV2") as Spatial
	var magrail_entry_airlock := magrail.get_node_or_null("Airlock_FromHangar") as Spatial
	var magrail_exit_zone := magrail.get_node_or_null("Airlock_ToRingHub/AirlockZoneV2") as Spatial
	var dest_airlock := hub.get_node_or_null("Hub/Airlock_FromHangar") as Spatial
	assert_object(hangar_exit_zone).is_not_null()
	assert_object(magrail_entry_airlock).is_not_null()
	assert_object(magrail_exit_zone).is_not_null()
	assert_object(dest_airlock).is_not_null()
	assert_str(String(hangar_exit_zone.get("target_airlock_path"))).is_equal("Airlock_FromHangar")
	assert_str(String(magrail_exit_zone.get("target_airlock_path"))).is_equal("Hub/Airlock_FromHangar")

	var airlock_mgr := get_node_or_null("/root/AirlockManager")
	assert_object(airlock_mgr).is_not_null()
	var dummy_player: Spatial = auto_free(Spatial.new())
	add_child(dummy_player)

	# 1. Hangar -> MagRail (entrada seamless)
	var params_in := {
		"transition": "seamless",
		"state_data": {
			"airlock_relative_transform": Transform(Basis.IDENTITY, Vector3(0.0, 0.0, 0.5)),
			"target_airlock_path": String(hangar_exit_zone.get("target_airlock_path")),
		}
	}
	airlock_mgr._pre_position_at_destination(dummy_player, magrail, params_in)
	var expected_in: Vector3 = magrail_entry_airlock.global_transform.xform(Vector3(0.0, 0.0, 0.5))
	assert_vector3(dummy_player.global_transform.origin).is_equal_approx(expected_in, Vector3(0.01, 0.01, 0.01))

	# 2. MagRail -> RingHub (salida seamless)
	var params_out := {
		"transition": "seamless",
		"state_data": {
			"airlock_relative_transform": Transform(Basis.IDENTITY, Vector3(0.0, 0.0, 0.5)),
			"target_airlock_path": String(magrail_exit_zone.get("target_airlock_path")),
		}
	}
	airlock_mgr._pre_position_at_destination(dummy_player, hub, params_out)
	var expected_out: Vector3 = dest_airlock.global_transform.xform(Vector3(0.0, 0.0, 0.5))
	assert_vector3(dummy_player.global_transform.origin).is_equal_approx(expected_out, Vector3(0.01, 0.01, 0.01))


func test_hangar_magrail_connector_fallback_flag() -> void:
	var hangar_packed := load(DOME_HANGAR) as PackedScene
	assert_object(hangar_packed).is_not_null()
	var hangar: Node = auto_free(hangar_packed.instance())
	var exit_node := hangar.get_node_or_null("Exit")
	assert_object(exit_node).is_not_null()
	exit_node.set("magrail_hangar_connector_enabled", false)
	add_child(hangar)
	yield(get_tree(), "idle_frame")

	var zone := hangar.get_node_or_null("Exit/Airlock_Exit/AirlockZoneV2")
	assert_object(zone).is_not_null()
	assert_str(String(zone.get("target_scene"))).is_equal(RING_HUB)
	assert_str(String(zone.get("target_spawn_id"))).is_equal("from_dome_intro_hangar")
	assert_str(String(zone.get("target_airlock_path"))).is_equal("Hub/Airlock_FromHangar")
