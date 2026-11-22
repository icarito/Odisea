extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# FD-323 Fase 3B — base de SpinLab: escena limpia sin WorldRotator, una espiral
# de ~200 placas, Pilot en SPIN_REAL estable sobre la placa 0, y presentación
# 2.5D + predictor sin mutar la simulación.

const LabScene = preload("res://core_v2/levels/spin_lab/SpinLab.tscn")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")
const DT := 1.0 / 60.0

func _instantiate_lab():
	var lab = auto_free(LabScene.instance())
	add_child(lab)
	lab.set_physics_process(false)
	var pilot = lab.get_node("Pilot")
	pilot.set_physics_process(false)
	return lab

func test_scene_loads_headless_without_world_rotator() -> void:
	var lab = _instantiate_lab()
	assert_object(lab).is_not_null()
	assert_bool(lab.find_node("WorldRotator", true, false) == null).is_true()

	var field = lab.get_node_or_null("DomeSpiralField")
	assert_object(field).is_not_null()
	assert_int(field.get_spiral_count()).is_equal(1)

	var body = field.get_collision_body(0)
	assert_object(body).is_not_null()
	var box_count := 0
	for child in body.get_children():
		if child is CollisionShape and (child as CollisionShape).shape is BoxShape:
			box_count += 1
	assert_int(box_count).is_equal(200)

	var multimesh = field.get_plate_multimesh(0)
	assert_object(multimesh).is_not_null()
	assert_int(multimesh.instance_count).is_equal(200)
	assert_object(field.get_node_or_null("SpiralDetailPool")).is_not_null()

func test_pilot_starts_on_plate_zero_and_does_not_fall() -> void:
	var lab = _instantiate_lab()
	var pilot = lab.get_node("Pilot")
	var plate: Transform = SpiralGeometry.plate_transform(lab.get_spiral_config(), 0)
	var plate_up: Vector3 = plate.basis.y.normalized()

	assert_bool(pilot.is_spin_real_active()).is_true()
	assert_float(pilot.get_sim_up().dot(plate_up)).is_greater(0.99)

	var radial_before: float = SpinFrame.r_perp(pilot.global_transform.origin).length()
	for _i in range(120):
		pilot.step(DT, InputDataV2.new())
	var radial_after: float = SpinFrame.r_perp(pilot.global_transform.origin).length()

	# No se cae al eje ni atraviesa la placa: se mantiene en el radio del piso.
	assert_float(radial_after).is_greater(radial_before - 5.0)
	assert_float(abs(pilot.global_transform.origin.z - plate.origin.z)).is_less(5.0)
	assert_bool(pilot.is_on_floor()).is_true()

func test_spin_camera_transitions_and_predictor_is_pure() -> void:
	var lab = _instantiate_lab()
	var pilot = lab.get_node("Pilot")
	var camera = lab.get_node("SpinRealCamera")
	var predictor = lab.get_node("SpinLandingPredictor")

	# En placa: tercera persona (altitud ~0).
	lab.spawn_at_plate(0)
	pilot.step(DT, InputDataV2.new())
	for _i in range(20):
		lab.update_spin_presentation(0.1)
	assert_bool(camera.in_25d).is_false()
	assert_float(camera.blend_25d).is_less(0.1)

	# Cerca del eje: 2.5D con blend completo.
	lab.spawn_at_hub_drop(0)
	for _i in range(20):
		lab.update_spin_presentation(0.1)
	assert_bool(camera.in_25d).is_true()
	assert_float(camera.blend_25d).is_greater(0.9)

	# El predictor no muta posición ni velocidad del Pilot.
	var position_before: Vector3 = pilot.global_transform.origin
	var velocity_before: Vector3 = pilot.velocity
	var r_local: float = lab.r_local_for_position(position_before)
	var prediction: Dictionary = predictor.update_preview(
		position_before, velocity_before, lab.spin_omega, r_local, true, DT, 4000
	)
	assert_bool(prediction["hit"]).is_true()
	assert_bool(predictor.visible).is_true()
	assert_float(pilot.global_transform.origin.distance_to(position_before)).is_less(0.000001)
	assert_float(pilot.velocity.distance_to(velocity_before)).is_less(0.000001)
