extends GdUnitTestSuite

const ElevatorPropScene = preload("res://core_v2/props/machinery/ElevatorProp.tscn")
const CriopodScene = preload("res://core_v2/props/criopod/Criopod_vert.tscn")

func _scene_host() -> Node:
	return get_tree().current_scene if get_tree().current_scene else self

func test_world_snapshot_includes_elevator_platform_and_criopod_door_state() -> void:
	var host = _scene_host()
	var root := Spatial.new()
	root.name = "ReplayPropSnapshotRoot"
	host.add_child(root)

	var elevator = ElevatorPropScene.instance()
	elevator.name = "ElevatorUnderTest"
	root.add_child(elevator)

	var criopod = CriopodScene.instance()
	criopod.name = "CriopodUnderTest"
	root.add_child(criopod)

	yield (get_tree(), "idle_frame")

	var door = criopod.get_node("RotatingObjectV2")
	var platform = elevator.get_node("Platform")
	door.set_active(true, true)
	var door_snapshot = door.get_snapshot()
	var platform_snapshot = platform.get_snapshot()

	assert_bool(platform.is_in_group("replay_sync")).is_true()
	assert_bool(door.is_in_group("replay_sync")).is_true()
	assert_bool(bool(door_snapshot.get("active", false))).is_true()
	assert_bool(platform_snapshot.has("target_height")).is_true()

	root.queue_free()
	yield (get_tree(), "idle_frame")

func test_world_snapshot_includes_scene_root_itself_when_in_replay_sync() -> void:
	# Regresion: _get_replay_sync_nodes() filtraba con is_a_parent_of(), que excluye al
	# propio nodo (un nodo no es padre de si mismo). Un script de nivel pegado a la RAIZ
	# de la escena (ej. RingHubWakeup en RingHub_Level) quedaba fuera del snapshot y su
	# estado (que criopod eligio) nunca se restauraba en el replay.
	# set_current_scene() exige que el nodo sea hijo directo de la raiz del arbol
	# (Viewport), igual que una escena real montada por SceneManager.
	var root := Spatial.new()
	root.name = "SceneRootUnderTest"
	root.set_script(preload("res://core_v2/tests/helpers/ReplaySyncRootStub.gd"))
	root.add_to_group("replay_sync")
	get_tree().get_root().add_child(root)
	yield (get_tree(), "idle_frame")

	var previous_scene = get_tree().current_scene
	get_tree().current_scene = root
	# Forzar recomputo del cache de replay_sync bajo el nuevo current_scene: el cache
	# solo se invalida por señales node_added/node_removed del arbol, no por cambiar
	# current_scene, así que otro frame de proceso ya lo puede haber recalculado bajo
	# el active_scene viejo (dejandolo "limpio" y ocultando el bug que este test cubre).
	SessionManager._replay_sync_cache_dirty = true
	var snapshot = SessionManager._get_world_state_snapshot()
	get_tree().current_scene = previous_scene
	SessionManager._replay_sync_cache_dirty = true

	assert_dict(snapshot).contains_keys([root.get_path()])

	root.queue_free()
	yield (get_tree(), "idle_frame")

func test_expand_buffer_recovers_full_frame_count_from_hold_compression() -> void:
	# Regresion: tools/dbg_replay_run.gd media el "total" de frames leyendo
	# data["buffer"].size() directo del JSON grabado, pero ese array esta
	# comprimido por compress_buffer() (runs de input identico colapsan a un
	# solo {"hold": N}). Un replay de 714 frames grabados con mucho input
	# sostenido (caminar, quieto) podia comprimir a un array mucho mas chico
	# y el script reportaba "termino en frame 1647 de 714", dando la falsa
	# impresion de que el SessionManager tardaba de mas en terminar cuando en
	# realidad corrio exactamente los frames que tenia. expand_buffer() es la
	# fuente de verdad del conteo real.
	var same_input = {"move": Vector2(1, 0)}
	var raw_buffer = [{"snapshot": {}}]
	for _i in range(50):
		raw_buffer.append({"input": same_input})

	var compact = SessionManager.compress_buffer(raw_buffer)
	assert_int(compact.size()).is_less(raw_buffer.size())

	var expanded = SessionManager.expand_buffer(compact)
	assert_int(expanded.size()).is_equal(raw_buffer.size())

func test_elevator_controller_snapshot_roundtrip_preserves_runtime_state() -> void:
	var host = _scene_host()
	var elevator = ElevatorPropScene.instance()
	host.add_child(elevator)
	yield (get_tree(), "idle_frame")

	elevator.requests = [2, 1]
	elevator.current_floor = 1
	elevator.target_floor = 2
	elevator.is_moving = true
	var snapshot = elevator.get_snapshot()

	var restored = ElevatorPropScene.instance()
	host.add_child(restored)
	yield (get_tree(), "idle_frame")
	restored.restore_snapshot(snapshot)

	assert_array(restored.requests).contains_exactly([2, 1])
	assert_int(restored.current_floor).is_equal(1)
	assert_int(restored.target_floor).is_equal(2)
	assert_bool(restored.is_moving).is_true()

	elevator.queue_free()
	restored.queue_free()
	yield (get_tree(), "idle_frame")

func test_elevator_platform_snapshot_roundtrip_preserves_motion_state() -> void:
	var host = _scene_host()
	var elevator = ElevatorPropScene.instance()
	host.add_child(elevator)
	yield (get_tree(), "idle_frame")

	var platform = elevator.get_node("Platform")
	platform.global_transform.origin = Vector3(0, 3.5, 0)
	platform.target_height = 5.0
	platform.current_velocity_y = 1.25
	platform.is_moving = true
	var snapshot = platform.get_snapshot()

	var restored_elevator = ElevatorPropScene.instance()
	host.add_child(restored_elevator)
	yield (get_tree(), "idle_frame")
	var restored_platform = restored_elevator.get_node("Platform")
	restored_platform.restore_snapshot(snapshot)

	assert_float(restored_platform.global_transform.origin.y).is_equal(3.5)
	assert_float(restored_platform.target_height).is_equal(5.0)
	assert_float(restored_platform.current_velocity_y).is_equal(1.25)
	assert_bool(restored_platform.is_moving).is_true()
	assert_bool(restored_platform.is_in_group("replay_sync")).is_true()

	elevator.queue_free()
	restored_elevator.queue_free()
	yield (get_tree(), "idle_frame")
