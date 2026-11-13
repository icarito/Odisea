extends GdUnitTestSuite

# FD-289 T4 — Blockout del hangar como escena separada (tests focalizados de carga/estructura).
#
# El hangar es la escena INTERCAMBIABLE por domo: recibe el `change_scene` del blast door del
# domo (spawn de llegada `from_dome_intro_platform`) y cierra el vertical slice con una esclusa
# al ScaffoldOrbit (spawn `from_dome_intro_hangar`, unica frontera presurizada -> vacio).
#
# No valida arte (QA visual la confirma un humano): verifica que la escena CARGA, que declara el
# spawn correcto, que tiene dos niveles (piso + catwalks), que coloca los puzzles fisicos con los
# props existentes y que la esclusa de salida apunta al exterior.

const HangarScene := preload("res://core_v2/levels/interiors/Dome_Intro_Hangar.tscn")

const SPAWN_SCRIPT := preload("res://core_v2/components/SpawnPointV2.gd")
const PUSHABLE_BOX_SCRIPT := preload("res://core_v2/components/PushableBoxV2.gd")
const CONVEYOR_SCRIPT := preload("res://core_v2/components/Conveyor.gd")
const CARROUSEL_SCRIPT := preload("res://core_v2/components/ConveyorCarrousel.gd")
const PLATE_SCRIPT := preload("res://core_v2/components/PressurePlateV2.gd")
const TRIPOD_SCRIPT := preload("res://core_v2/props/scifi_lights/SciFiWorkLightV2.gd")
const AIRLOCK_SCRIPT := preload("res://core_v2/components/AirlockControllerV2.gd")
const AIRLOCK_ZONE_SCRIPT := preload("res://core_v2/components/AirlockZoneV2.gd")
const GRATE_PLATFORM_SCRIPT := preload("res://core_v2/props/scaffold/SteelGratePlatform.gd")


func _spawn_hangar() -> Node:
	# Igual que el resto de los tests de escena: un host en el arbol hace correr los _ready
	# reales (SteelGratePlatform, Conveyor, AirlockControllerV2) y detecta errores de carga.
	var host: Spatial = auto_free(Spatial.new())
	add_child(host)
	var hangar: Node = auto_free(HangarScene.instance())
	host.add_child(hangar)
	yield(get_tree(), "idle_frame")
	return hangar


func _flatten(node: Node, out: Array) -> Array:
	out.append(node)
	for child in node.get_children():
		_flatten(child, out)
	return out


func _nodes_with_script(root: Node, script: Script) -> Array:
	var matches := []
	for node in _flatten(root, []):
		if node.get_script() == script:
			matches.append(node)
	return matches


func test_hangar_scene_loads() -> void:
	var hangar = yield(_spawn_hangar(), "completed")
	assert_object(hangar).is_not_null()
	assert_str(String(hangar.name)).is_equal("Dome_Intro_Hangar")
	assert_object(hangar.get_node_or_null("WorldEnvironment")).is_not_null()


func test_arrival_spawn_point_from_dome_intro_platform() -> void:
	var hangar = yield(_spawn_hangar(), "completed")
	var spawns := _nodes_with_script(hangar, SPAWN_SCRIPT)
	assert_array(spawns).is_not_empty()
	var ids := []
	for spawn in spawns:
		ids.append(String(spawn.get("spawn_id")))
	assert_array(ids).contains(["from_dome_intro_platform"])
	# La convencion de niveles del repo es embeber el Pilot en la escena (si no, un
	# goto_scene no tiene camara): el hangar debe traerlo en el punto de llegada.
	assert_object(hangar.get_node_or_null("Pilot")).is_not_null()


func test_two_levels_catwalks_above_the_floor() -> void:
	var hangar = yield(_spawn_hangar(), "completed")
	# 3 catwalks (izquierda / derecha / fondo) + 1 rampa de descenso, todos SteelGratePlatform.
	var platforms := _nodes_with_script(hangar, GRATE_PLATFORM_SCRIPT)
	assert_int(platforms.size()).is_greater_equal(4)
	var elevated := 0
	for platform in platforms:
		if float(platform.get("platform_height")) >= 4.0:
			elevated += 1
	assert_int(elevated).is_greater_equal(3)


func test_physical_puzzles_use_existing_props() -> void:
	var hangar = yield(_spawn_hangar(), "completed")
	assert_array(_nodes_with_script(hangar, PUSHABLE_BOX_SCRIPT)).is_not_empty()
	assert_array(_nodes_with_script(hangar, CONVEYOR_SCRIPT)).is_not_empty()
	assert_array(_nodes_with_script(hangar, CARROUSEL_SCRIPT)).is_not_empty()
	assert_array(_nodes_with_script(hangar, PLATE_SCRIPT)).is_not_empty()


func test_work_lighting_present() -> void:
	var hangar = yield(_spawn_hangar(), "completed")
	assert_array(_nodes_with_script(hangar, TRIPOD_SCRIPT)).is_not_empty()


func test_exit_airlock_targets_scaffold_orbit_with_spawn() -> void:
	var hangar = yield(_spawn_hangar(), "completed")
	# Una sola frontera presurizada -> vacio: exactamente una esclusa de salida.
	assert_array(_nodes_with_script(hangar, AIRLOCK_SCRIPT)).has_size(1)
	var zones := _nodes_with_script(hangar, AIRLOCK_ZONE_SCRIPT)
	assert_array(zones).is_not_empty()
	var found := false
	for zone in zones:
		var target_scene := String(zone.get("target_scene"))
		var target_spawn := String(zone.get("target_spawn_id"))
		if target_scene.find("ScaffoldOrbit") >= 0 and target_spawn == "from_dome_intro_hangar":
			found = true
	assert_bool(found).is_true()
