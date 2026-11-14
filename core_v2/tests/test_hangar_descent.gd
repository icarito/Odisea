extends GdUnitTestSuite

# Test focalizado del descenso domo -> hangar (FD-289 §7.5/§7.9, tracker #319).
#
# Cierra la cadena: la plataforma movil + el trigger de transicion + la camara cinematica DE
# TRANSICION viven en el prefab `HangarDescent.tscn`, instanciado en `Dome_Intro.tscn` en el
# pozo de la compuerta (bajo DomeMachineLevel/Doors/BlastDoor). Las dos vias de descenso
# (plataforma + rampa de servicio ya existente en BlastDoorController.tscn) desembocan en el
# mismo trigger, que hace change_scene a Dome_Intro_Hangar con spawn `from_dome_intro_platform`.
#
# No corre la suite completa (AGENTS.md §6.1).

const DescentScene := preload("res://core_v2/props/hangar/HangarDescent.tscn")
const DomeIntroScene := preload("res://core_v2/levels/interiors/Dome_Intro.tscn")

const PlatformScript := preload("res://core_v2/props/hangar/HangarPlatform.gd")
const TransitionScript := preload("res://core_v2/props/hangar/HangarTransition.gd")
const CameraZoneScript := preload("res://core_v2/components/CameraZone.gd")
const CinematicRigScript := preload("res://core_v2/visual/CinematicRig.gd")

const HANGAR_SCENE := "res://core_v2/levels/interiors/Dome_Intro_Hangar.tscn"
const HANGAR_SPAWN := "from_dome_intro_platform"


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


func _spawn_descent() -> Node:
	var host: Spatial = auto_free(Spatial.new())
	add_child(host)
	var descent: Node = auto_free(DescentScene.instance())
	host.add_child(descent)
	yield(get_tree(), "idle_frame")
	return descent


# --- Prefab del descenso ---

func test_descent_prefab_has_platform_trigger_and_transition_camera() -> void:
	var descent = yield(_spawn_descent(), "completed")

	# Plataforma movil de carga en el pozo.
	var platforms := _nodes_with_script(descent, PlatformScript)
	assert_int(platforms.size()).is_equal(1)
	# Top justo bajo la compuerta (y≈-0.45) para que el jugador baje al abrir.
	assert_float(platforms[0].transform.origin.y).is_between(-1.5, -0.2)

	# Trigger de transicion al hangar.
	var triggers := _nodes_with_script(descent, TransitionScript)
	assert_int(triggers.size()).is_equal(1)
	assert_str(String(triggers[0].target_scene)).is_equal(HANGAR_SCENE)
	assert_str(String(triggers[0].target_spawn_id)).is_equal(HANGAR_SPAWN)
	# Es un Area de deteccion del jugador (layer 2), interior -> interior sin airlock.
	assert_int(triggers[0].collision_mask).is_equal(2)
	# El trigger cubre el FONDO del pozo, por debajo de la plataforma en reposo.
	assert_float(triggers[0].transform.origin.y).is_less(platforms[0].transform.origin.y)

	# Camara cinematica de transicion: CameraZone + CinematicRig.
	var zones := _nodes_with_script(descent, CameraZoneScript)
	assert_int(zones.size()).is_equal(1)
	assert_bool(zones[0].is_in_group("CameraZoneV2")).is_true()
	var rigs := _nodes_with_script(descent, CinematicRigScript)
	assert_int(rigs.size()).is_equal(1)
	assert_bool(rigs[0].is_in_group("cinematic_rigs")).is_true()

	var cam: Camera = rigs[0].get_node_or_null("Camera")
	assert_object(cam).is_not_null()
	# Encuadra el descenso: mira hacia ABAJO en el pozo, no al horizonte.
	var forward: Vector3 = -cam.global_transform.basis.z
	assert_float(forward.y).is_less(-0.2)


# --- Cableado en el domo real ---

func test_dome_intro_instances_the_descent_in_the_pozo() -> void:
	var level: Node = auto_free(DomeIntroScene.instance())
	add_child(level)
	yield(get_tree(), "idle_frame")

	var descent = level.get_node_or_null("HangarDescent")
	assert_object(descent).is_not_null()
	assert_int(_nodes_with_script(descent, PlatformScript).size()).is_equal(1)

	var triggers := _nodes_with_script(descent, TransitionScript)
	assert_int(triggers.size()).is_equal(1)
	assert_str(String(triggers[0].target_scene)).is_equal(HANGAR_SCENE)
	assert_str(String(triggers[0].target_spawn_id)).is_equal(HANGAR_SPAWN)

	level.free()
