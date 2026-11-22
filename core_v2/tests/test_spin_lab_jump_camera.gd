extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# FD-323 — regresiones en SpinLab.tscn: salto real sobre la placa 0 y cámara/WASD
# alineados al `_up` radial (placa 0 => _up = -X). Corre Box3D headless con el
# mismo camino de física que el juego (sin WorldRotator).

const LabScene = preload("res://core_v2/levels/spin_lab/SpinLab.tscn")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")
const DT := 1.0 / 60.0

func _instantiate_lab():
	var lab = auto_free(LabScene.instance())
	add_child(lab)
	lab.set_physics_process(false)
	var pilot = lab.get_node("Pilot")
	pilot.set_physics_process(false)
	return lab

func _step(pilot, ticks: int, input = null) -> void:
	if input == null:
		input = InputDataV2.new()
	for _i in range(ticks):
		pilot.step(DT, input)

# Deja al Pilot apoyado en la placa 0 (spawn con clearance y caída incluidos).
func _settle_on_plate_zero(lab):
	var pilot = lab.get_node("Pilot")
	lab.spawn_at_plate(0)
	_step(pilot, 180)
	return pilot

func test_jump_on_plate_zero_rises_above_half_meter_and_lands() -> void:
	var lab = _instantiate_lab()
	var pilot = _settle_on_plate_zero(lab)
	var physics = pilot.get_spin_physics()
	assert_object(physics).is_not_null()
	assert_bool(physics._was_grounded).is_true()

	var start: Vector3 = pilot.global_transform.origin
	var up: Vector3 = pilot.get_sim_up()
	assert_float(up.dot(Vector3.LEFT)).is_greater(0.99)

	# Un único press de salto; el buffer no debe repetirlo en ticks siguientes.
	var input = InputDataV2.new()
	input.jump = true
	pilot.step(DT, input)
	var peak: float = (pilot.global_transform.origin - start).dot(up)
	input.jump = false
	for _i in range(240):
		pilot.step(DT, input)
		peak = max(peak, (pilot.global_transform.origin - start).dot(up))

	assert_float(peak).is_greater(0.5)
	# Vuelve a aterrizar sobre la placa, al nivel de partida.
	assert_bool(physics._was_grounded or pilot.is_on_floor()).is_true()
	assert_float(abs((pilot.global_transform.origin - start).dot(up))).is_less(0.6)

func test_camera_third_person_and_wasd_follow_radial_up_on_plate_zero() -> void:
	var lab = _instantiate_lab()
	var pilot = _settle_on_plate_zero(lab)
	var rig: Spatial = pilot.get_node("CameraRig")
	var cam: Camera = pilot.get_node("CameraRig/Yaw/Pitch/OTS_Offset/SpringArm/Camera")
	var up: Vector3 = pilot.get_sim_up()
	assert_float(up.dot(Vector3.LEFT)).is_greater(0.99)

	# Ticks de presentación para que rig y prefijo queden aplicados.
	_step(pilot, 4)
	lab.update_spin_presentation(DT)

	# No hay doble rotación: el +Y global del rig sigue el up del Pilot.
	assert_float(rig.global_transform.basis.y.normalized().dot(up)).is_greater(0.99)
	# El rig está sobre el jugador a lo largo de _up, no en el Y de mundo.
	var offset: Vector3 = rig.global_transform.origin - pilot.global_transform.origin
	assert_float(offset.normalized().dot(up)).is_greater(0.99)
	assert_float(offset.length()).is_greater(0.5)

	# W (Vector2(0,-1)) avanza hacia el forward de cámara en el plano de _up.
	var move_dir: Vector3 = pilot._get_move_direction(Vector2(0.0, -1.0))
	var expected: Vector3 = -cam.global_transform.basis.z
	expected -= up * expected.dot(up)
	expected = expected.normalized()
	assert_float(move_dir.normalized().dot(expected)).is_greater(0.99)

	# D (Vector2(1,0)) va hacia la derecha de cámara en ese mismo plano.
	var right_dir: Vector3 = pilot._get_move_direction(Vector2(1.0, 0.0))
	var expected_right: Vector3 = cam.global_transform.basis.x
	expected_right -= up * expected_right.dot(up)
	expected_right = expected_right.normalized()
	assert_float(right_dir.normalized().dot(expected_right)).is_greater(0.99)
