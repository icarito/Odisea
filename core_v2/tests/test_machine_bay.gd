extends GdUnitTestSuite

# FD-320: recorrido de la bahia de maquinas con el piloto real. Cada caso planta al piloto
# en una estacion, acciona el mecanismo y verifica que la fisica lo lleva a destino.

const BayScene = preload("res://core_v2/levels/machines/MachineBay.tscn")

# Modelo privado: los tests de cierre no escriben objetivos/comunicaciones de campaña.
class ClosureScreen extends Reference:
	var model: Reference = preload("res://core_v2/ui/hud/SuitModel.gd").new()

	func ensure_model() -> Reference:
		return model

	func notify_state_changed() -> void:
		pass

class ClosureLevel extends "res://core_v2/props/machines/MachineLevel.gd":
	var screen: Reference = ClosureScreen.new()

	func _get_suit_screen() -> Object:
		return screen

var _bay: Node = null
var debug_trace := false


func _load_bay(pilot_pos: Vector3) -> KinematicBody:
	_bay = BayScene.instance()
	var pilot: KinematicBody = _bay.get_node("Pilot")
	pilot.translation = pilot_pos
	get_tree().root.add_child(_bay)
	# El TeleportSystem (autoload) solo conoce al piloto de la escena actual; aca la bahia
	# cuelga de root, asi que los checkpoints fallarian al guardar. No son parte del caso.
	for zone in get_tree().get_nodes_in_group("CheckZoneV2"):
		if _bay.is_a_parent_of(zone):
			zone.queue_free()
	return pilot


func _free_bay() -> void:
	if is_instance_valid(_bay):
		_bay.queue_free()
	_bay = null
	yield(get_tree(), "idle_frame")


func _item(item_name: String) -> Node:
	return _bay.get_node("Level").get_item(item_name)


# Avanza `frames` ticks y devuelve [altura maxima, posicion final] del piloto.
func _fly(pilot: KinematicBody, frames: int) -> Array:
	var max_y: float = pilot.global_transform.origin.y
	for _i in range(frames):
		yield(get_tree(), "physics_frame")
		max_y = max(max_y, pilot.global_transform.origin.y)
		if debug_trace and _i % 30 == 0:
			prints("[machine_bay] t", _i, pilot.global_transform.origin, "vel", pilot.velocity, "floor", pilot.is_on_floor(), "plat", pilot._platform_collider)
	return [max_y, pilot.global_transform.origin]


# Conserva los checkpoints reales y aísla toda escritura de campaña del usuario.
func test_checkpoint_bases_and_real_fall_respawn_clear_the_floor() -> void:
	var tree: SceneTree = get_tree()
	var previous_scene: Node = tree.current_scene
	var persistence: Node = get_node("/root/PersistenceManager")
	var session: Node = get_node("/root/SessionManager")
	var checkpoints: Node = get_node("/root/CheckpointManager")
	var teleport: Node = session.get_node("TeleportSystem")
	var saved: Array = []
	for spec in [
		[persistence, ["checkpoint_directory", "checkpoint_resource", "_continue_requested", "registered_entities", "_scene_hash_cache"]],
		[session, ["player", "is_respawning", "_oys_input_override"]],
		[teleport, ["player_controller", "camera_controller", "initial_spawn_transform"]],
		[checkpoints, ["active_checkpoint_pos", "active_checkpoint_yaw", "active_checkpoint_pitch", "active_replay_snapshot", "default_respawn_position", "default_respawn_yaw", "default_respawn_pitch", "default_replay_snapshot", "_default_snapshot_scene_id", "_default_snapshot_ice_path"]]
	]:
		for key in spec[1]:
			var value = spec[0].get(key)
			if value is Dictionary or value is Array:
				value = value.duplicate(true)
			saved.append([spec[0], key, value])
	var test_directory: String = "user://test_machine_bay_respawn_%s" % OS.get_ticks_usec()
	persistence.checkpoint_directory = test_directory
	persistence.checkpoint_resource = null
	persistence._continue_requested = false
	_bay = BayScene.instance()
	tree.root.add_child(_bay)
	tree.current_scene = _bay
	var pilot: KinematicBody = _bay.get_node("Pilot")
	session.player = pilot
	teleport.player_controller = pilot
	teleport.camera_controller = pilot.get_node("CameraRig")
	yield(_fly(pilot, 5), "completed")
	for station in [["CheckEntry", "EntryFloor"], ["CheckLedge1", "Ledge1"], ["CheckLedge2", "Ledge2"], ["CheckLedge3", "Ledge3"]]:
		var zone: Area = _item(station[0])
		assert_object(zone).is_not_null()
		var base: Transform = zone._get_base_transform()
		var floor_body: StaticBody = _item(station[1])
		var floor_shape: CollisionShape = floor_body.get_child(0)
		var top: float = floor_shape.to_global(Vector3(0, floor_shape.shape.extents.y, 0)).y
		prints("[machine_bay] checkpoint", station[0], "base", base.origin, "floor", top)
		assert_float(base.origin.y).is_greater(top + 0.05)
		# Consulta la cápsula REAL, incluyendo su offset/orientación local; no un punto.
		var collision: CollisionShape = pilot.get_node("CollisionShape")
		var query := PhysicsShapeQueryParameters.new()
		query.set_shape(collision.shape)
		query.transform = base * collision.transform
		query.collision_mask = pilot.collision_mask
		query.exclude = [pilot.get_rid()]
		query.collide_with_areas = false
		assert_array(pilot.get_world().direct_space_state.intersect_shape(query)).is_empty()
		# Entrar por física debe guardar el mismo transform (sin invocar el callback a mano).
		var arrival: Transform = base
		arrival.origin.y = top + 1.2
		pilot.teleport_to(arrival)
		yield(_fly(pilot, 40), "completed")
		var resource: Resource = persistence.get_checkpoint_resource(_bay.filename)
		assert_bool(resource.slots.has("last")).is_true()
		if resource.slots.has("last"):
			assert_vector3(resource.slots["last"]["transform"].origin).is_equal(base.origin)
		# Caída real fuera de las plataformas: KillFloor -> TeleportSystem -> Pilot nuevo.
		var old_id: int = pilot.get_instance_id()
		pilot.teleport_to(Transform(Basis(), Vector3(40, -8, base.origin.z)))
		for _frame in range(480):
			yield(tree, "physics_frame")
			if is_instance_valid(teleport.player_controller) and teleport.player_controller.get_instance_id() != old_id and not session.is_respawning:
				break
		pilot = teleport.player_controller
		assert_bool(is_instance_valid(pilot)).is_true()
		assert_int(pilot.get_instance_id()).is_not_equal(old_id)
		assert_vector3(pilot.initial_transform.origin).is_equal(base.origin)
		yield(_fly(pilot, 40), "completed")
		assert_bool(pilot.is_on_floor()).is_true()
		assert_float(pilot.global_transform.origin.y).is_greater(top - 0.05)
		collision = pilot.get_node("CollisionShape")
		query.set_shape(collision.shape)
		query.transform = collision.global_transform
		# Despegar 5cm evita que el contacto tolerado del suelo cuente como penetración.
		query.transform.origin.y += 0.05
		query.exclude = [pilot.get_rid()]
		assert_array(pilot.get_world().direct_space_state.intersect_shape(query)).is_empty()
	# Drenar los deferred del respawn antes de devolver los autoloads al runner.
	yield(_free_bay(), "completed")
	tree.current_scene = previous_scene
	for entry in saved:
		entry[0].set(entry[1], entry[2])
	var directory := Directory.new()
	if directory.open(test_directory) == OK:
		directory.list_dir_begin(true, true)
		var filename: String = directory.get_next()
		while filename != "":
			directory.remove(filename)
			filename = directory.get_next()
		directory.list_dir_end()
	Directory.new().remove(test_directory)


func test_seesaw_launches_pilot_above_ledge() -> void:
	var pilot := _load_bay(Vector3(0, 0.6, 5.8))
	yield(_fly(pilot, 60), "completed")
	_item("SeesawLever").interact()
	var flight: Array = yield(_fly(pilot, 480), "completed")
	prints("[machine_bay] seesaw max_y", flight[0], "end", flight[1])
	# Ledge1 tiene el tope en y=2.5: el apogeo deja margen de sobra para corregir en el
	# aire y caer encima (el vuelo es casi vertical; llegar exige input del jugador).
	assert_float(flight[0]).is_greater(6.5)
	yield(_free_bay(), "completed")


func test_pendulum_carries_pilot_across() -> void:
	var pilot := _load_bay(Vector3(0, 6.7, 23.9))
	yield(_fly(pilot, 30), "completed")
	_item("PendulumLever").interact()
	var max_z: float = 0.0
	for _i in range(360):
		yield(get_tree(), "physics_frame")
		max_z = max(max_z, pilot.global_transform.origin.z)
		if debug_trace and _i % 20 == 0:
			prints("[machine_bay] pend t", _i, pilot.global_transform.origin, "floor", pilot.is_on_floor(), "plat", pilot._platform_collider, "gond", _item("Gondola").global_transform.origin, _item("Gondola").rotation_degrees)
	prints("[machine_bay] pendulum max_z", max_z)
	# La gondola llega nivelada al muelle opuesto (frente en z=36.2) con el piloto encima.
	assert_float(max_z).is_greater(34.0)
	yield(_free_bay(), "completed")


func _catapult_flight(levers: Array) -> Array:
	var pilot := _load_bay(Vector3(0, 4.0, 44.2))
	yield(_fly(pilot, 60), "completed")
	for lever_name in levers:
		_item(lever_name).interact()
	var flight: Array = yield(_fly(pilot, 600), "completed")
	prints("[machine_bay] catapult", levers, "max_y", flight[0], "end", flight[1])
	yield(_free_bay(), "completed")
	return flight


func test_catapult_mass_decides_height() -> void:
	var light: Array = yield(_catapult_flight(["LeverLight"]), "completed")
	var medium: Array = yield(_catapult_flight(["LeverMedium"]), "completed")
	var heavy: Array = yield(_catapult_flight(["LeverHeavy"]), "completed")
	var all: Array = yield(_catapult_flight(["LeverLight", "LeverMedium", "LeverHeavy"]), "completed")
	# Sistemas, no puzzles: mas masa = mas altura, sin umbral magico.
	assert_float(medium[0]).is_greater(light[0])
	assert_float(heavy[0]).is_greater(medium[0])
	assert_float(all[0]).is_greater(heavy[0])


func test_centrifuge_flings_pilot_to_exit() -> void:
	var pilot := _load_bay(Vector3(0, 13.2, 74.5))
	yield(_fly(pilot, 30), "completed")
	_item("CentrifugeLever").interact()
	# Retardo de 5 s + arranque del motor: se espera a que el brazo gire a regimen y la
	# punta apunte hacia la plataforma de salida (+Z) para saltar.
	var jumped := false
	for _i in range(1200):
		yield(get_tree(), "physics_frame")
		var pv: Vector3 = pilot._platform_velocity
		if debug_trace and _i > 355 and _i % 20 == 0:
			prints("[machine_bay] cent t", _i, pilot.global_transform.origin, "pv", pv, "floorvel", pilot.get_floor_velocity(), "floor", pilot.is_on_floor(), "armw", _item("CentrifugeArm").angular_velocity.y)
		if _i > 420 and pv.length() > 7.0 and pv.normalized().dot(Vector3(0, 0, 1)) > 0.995:
			pilot.jump_logic.buffer_jump()
			jumped = true
			break
	assert_bool(jumped).is_true()
	var flight: Array = yield(_fly(pilot, 300), "completed")
	prints("[machine_bay] centrifuge end", flight[1])
	# Aterriza en la plataforma de salida (tope y=10, z entre 79 y 95).
	assert_float(flight[1].y).is_between(9.9, 10.6)
	assert_float(flight[1].z).is_between(79.0, 95.0)
	yield(_free_bay(), "completed")


func test_laser_cut_strut_launches_pilot_and_reset_restores_station() -> void:
	var pilot := _load_bay(Vector3(0, 0.6, 5.8))
	yield(_fly(pilot, 40), "completed")
	var level: Node = _bay.get_node("Level")
	var strut: Spatial = _item("SeesawStrut")
	assert_bool(strut != null and strut.has_method("laser_hit")).is_true()
	# Simular disparo laser continuo al reten desde el balancin.
	for _i in range(25):
		strut.laser_hit()
		yield(get_tree(), "physics_frame")
	assert_bool(strut.is_cut()).is_true()
	var flight: Array = yield(_fly(pilot, 360), "completed")
	assert_float(flight[0]).is_greater(6.5)
	# El boton ResetStation1 rearma el reten y el contrapeso de la Estacion 1.
	_item("ResetStation1").interact()
	yield(_fly(pilot, 10), "completed")
	assert_bool(strut.is_cut()).is_false()
	assert_int(level.get_station_resets()).is_equal(1)
	assert_float(_item("SeesawWeight").translation.y).is_equal_approx(8.2, 0.05)
	yield(_free_bay(), "completed")


func _closure_level(names: Array) -> Node:
	var file := File.new()
	file.open("res://core_v2/levels/machines/machine_bay.json", File.READ)
	var layout: Dictionary = JSON.parse(file.get_as_text()).result
	file.close()
	var items: Array = []
	for item in layout["items"]:
		if names.has(item.get("name", "")) or (item["type"] == "link" and names.has(item.get("from", "")) and (names.has(item.get("to", "")) or item.get("to", "") == "@level")):
			items.append(item)
	var level: Node = ClosureLevel.new()
	get_tree().root.add_child(level)
	level.build({"items": items})
	level.set_physics_process(false)
	return level


func _step_level(level: Node, ticks: int) -> void:
	for _tick in range(ticks):
		level._physics_process(1.0 / float(Engine.iterations_per_second))


func test_administrative_close_requires_valve_and_is_idempotent() -> void:
	var level: Node = _closure_level(["MasterFlowValve", "OrderCompleteButton"])
	var model: Reference = level.screen.model
	level.start_work_order()
	assert_str(model.objective_state("lights")).is_equal(model.OBJ_ACTIVE)
	level.complete_work_order()
	var button: Node = level.get_item("OrderCompleteButton")
	button.interact()
	assert_bool(level.is_work_order_completed()).is_false()
	assert_str(model.objective_state("order_0001")).is_equal(model.OBJ_ACTIVE)
	assert_bool(model.objective_ids().has("return_hub")).is_false()
	assert_array(level._pending).is_empty()
	# Apertura real: su señal también pasa por el mismo guard, sin botón administrativo.
	level.get_item("MasterFlowValve").interact()
	level.get_item("MasterFlowValve").step(1.0)
	assert_bool(level.is_work_order_completed()).is_true()
	assert_str(model.objective_state("lights")).is_equal(model.OBJ_ACTIVE)
	assert_str(model.objective_state("order_0001")).is_equal(model.OBJ_DONE)
	assert_str(JSON.print(model.snapshot())).contains("Fin de la demo")
	assert_bool(JSON.print(model.snapshot()).find("Orden 0002") >= 0).is_false()
	var snapshot: Dictionary = model.snapshot().duplicate(true)
	var pending: Array = level.get_snapshot()["pending"]
	button.set_active(false, true)
	button.interact()
	level.complete_work_order()
	assert_dict(model.snapshot()).is_equal(snapshot)
	assert_array(level.get_snapshot()["pending"]).is_equal(pending)
	level.free()


func test_rotor_lever_starts_once_after_five_seconds() -> void:
	var level: Node = _closure_level(["CentrifugeLever", "CentrifugeJam", "CentrifugeHinge", "CentrifugeArm"])
	var ips: int = Engine.iterations_per_second
	var jam: Node = level.get_item("CentrifugeJam")
	var motor: Node = level.get_item("CentrifugeHinge")
	level.get_item("CentrifugeLever").interact()
	level.get_item("CentrifugeLever").step(2.0)
	_step_level(level, int(round(3.5 * ips)) - 1)
	assert_bool(jam.is_cut()).is_false()
	assert_bool(motor.motor_enabled).is_false()
	_step_level(level, 1)
	assert_bool(jam.is_cut()).is_true()
	assert_bool(motor.motor_enabled).is_false()
	assert_int(level._pending.size()).is_equal(1)
	_step_level(level, int(round(1.5 * ips)) - 1)
	assert_bool(motor.motor_enabled).is_false()
	_step_level(level, 1)
	assert_bool(motor.motor_enabled).is_true()
	assert_array(level._pending).is_empty()
	motor.set_active(false)
	_step_level(level, 2 * ips)
	assert_bool(motor.motor_enabled).is_false()
	level.free()


func test_rotor_early_cut_does_not_schedule_a_second_motor_start() -> void:
	var level: Node = _closure_level(["CentrifugeLever", "CentrifugeJam", "CentrifugeHinge", "CentrifugeArm"])
	var ips: int = Engine.iterations_per_second
	var motor: Node = level.get_item("CentrifugeHinge")
	level.get_item("CentrifugeLever").interact()
	level.get_item("CentrifugeLever").step(2.0)
	_step_level(level, ips)
	# Mismo corte terminal que produce el láser; el retardo de palanca sigue pendiente.
	level.get_item("CentrifugeJam").cut_now()
	_step_level(level, int(round(1.5 * ips)) - 1)
	assert_bool(motor.motor_enabled).is_false()
	_step_level(level, 1)
	assert_bool(motor.motor_enabled).is_true()
	motor.set_active(false)
	_step_level(level, 4 * ips)
	assert_bool(motor.motor_enabled).is_false()
	assert_array(level._pending).is_empty()
	level.free()


func test_master_flow_valve_completes_work_order_0001() -> void:
	var pilot := _load_bay(Vector3(0, 10.5, 81.5))
	yield(_fly(pilot, 20), "completed")
	var level: Node = _bay.get_node("Level")
	assert_bool(level.is_work_order_completed()).is_false()
	_item("MasterFlowValve").interact()
	# PipeValve gira 180 grados en 0.5 s (30 ticks) y emite `activated` al abrirse.
	yield(_fly(pilot, 40), "completed")
	assert_bool(level.is_work_order_completed()).is_true()
	yield(_free_bay(), "completed")


func test_spawn_on_floor_lighting_and_kill_floor_detection() -> void:
	# Simula haber venido desde RingHub_Level con posicion x=31.8 fuera de EntryFloor.
	_bay = BayScene.instance()
	var pilot: Spatial = _bay.get_node("Pilot")
	pilot.translation = Vector3(31.8, 0.0, 3.2)
	add_child(_bay)
	yield(_fly(pilot, 30), "completed")
	# 1. El jugador fue reubicado sobre EntryFloor (SpawnPointV2 en x=0, z=-2) y no cayo al vacio.
	assert_float(pilot.global_transform.origin.x).is_equal_approx(0.0, 0.2)
	assert_float(pilot.global_transform.origin.y).is_greater(-0.1)
	assert_object(_bay.get_node_or_null("SpawnPointV2")).is_not_null()
	# 2. Iluminacion interior: ambiente acotado para no lavar las marcas, con luces locales.
	var we := _bay.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert_object(we).is_not_null()
	assert_float(we.environment.ambient_light_energy).is_between(0.25, 0.6)
	assert_float(we.environment.glow_bloom).is_equal(0.0)
	assert_object(_bay.get_node_or_null("BayLights/LightStation1")).is_not_null()
	# 3. KillFloor detecta la capa de colision 2 del Pilot y dispara player_killed al caer.
	var kill_floor := _item("KillFloor") as Area
	assert_object(kill_floor).is_not_null()
	assert_int(kill_floor.collision_mask & 2).is_equal(2)
	# 4. Feedback diegetico y claridad de controles: ForwardInteract reenvia titulo/descripcion/verbo
	#    de las palancas, los botones de rearme ya no dicen "Botón de ascensor", y hay carteles 3D y conductos.
	var seesaw_lever := _item("SeesawLever")
	var lever_body := seesaw_lever.get_node_or_null("InteractionBody")
	assert_object(lever_body).is_not_null()
	assert_str(lever_body.screen_title()).contains("Estación 1")
	assert_str(lever_body.get_interaction_description()).contains("400 kg")
	assert_str(lever_body.get_interaction_prompt()).contains("Soltar contrapeso")
	var reset_btn := _item("ResetStation1")
	assert_str(reset_btn.interaction_title).contains("Rearme")
	assert_bool(reset_btn.momentary).is_true()
	var sign1 := _item("SignStation1")
	assert_object(sign1).is_not_null()
	assert_str(String(sign1.get("text"))).contains("ESTACIÓN 1")
	var level_node := _bay.get_node("Level")
	assert_object(level_node.get_node_or_null("Conduit_SeesawLever_SeesawStrut")).is_not_null()
	yield(_free_bay(), "completed")
