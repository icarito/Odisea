extends GdUnitTestSuite

# FD-320: recorrido de la bahia de maquinas con el piloto real. Cada caso planta al piloto
# en una estacion, acciona el mecanismo y verifica que la fisica lo lleva a destino.

const BayScene = preload("res://core_v2/levels/machines/MachineBay.tscn")

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
