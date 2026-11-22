extends GdUnitTestSuite

# FD-323 Fase 2B — cámara 2.5D co-rotante y predictor de aterrizaje.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const ControllerScript = preload("res://core_v2/camera/SpinRealCameraController.gd")
const PredictorScript = preload("res://core_v2/camera/SpinLandingPredictor.gd")

const EPS := 1e-5

class DummyPilot extends Spatial:
	var camera_basis_prefix: Basis = Basis.IDENTITY

func _up_at(theta: float) -> Vector3:
	return -Vector3(cos(theta), sin(theta), 0.0)

func test_compute_altitude_uses_radial_distance() -> void:
	assert_float(ControllerScript.compute_altitude(Vector3(220.0, 0.0, 5.0), 240.0)) \
		.is_equal_approx(20.0, EPS)
	assert_float(ControllerScript.compute_altitude(Vector3.ZERO, 240.0)).is_equal_approx(240.0, EPS)
	assert_float(ControllerScript.compute_altitude(Vector3(236.0, 0.0, 0.0), 240.0)) \
		.is_equal_approx(4.0, EPS)

func test_hysteresis_enters_at_h_in_and_exits_at_h_out() -> void:
	var controller = auto_free(ControllerScript.new())
	controller.blend_speed = 100.0
	assert_float(controller.h_in).is_greater(controller.h_out)

	var up: Vector3 = _up_at(0.0)
	var state: Dictionary = controller.step_camera(Vector3(220.0, 0.0, 0.0), up, 240.0, 0.1)
	assert_bool(state["in_25d"]).is_true()
	assert_float(state["blend_25d"]).is_equal_approx(1.0, EPS)

	# h = 14: dentro de la banda (h_out < 14 < h_in), sigue en 2.5D.
	state = controller.step_camera(Vector3(226.0, 0.0, 0.0), up, 240.0, 0.1)
	assert_bool(state["in_25d"]).is_true()

	# h = 11 < h_out: vuelve a tercera persona.
	state = controller.step_camera(Vector3(229.0, 0.0, 0.0), up, 240.0, 0.1)
	assert_bool(state["in_25d"]).is_false()
	assert_float(state["blend_25d"]).is_equal_approx(0.0, EPS)

	# h = 14 < h_in: la banda impide re-entrar.
	state = controller.step_camera(Vector3(226.0, 0.0, 0.0), up, 240.0, 0.1)
	assert_bool(state["in_25d"]).is_false()

	state = controller.step_camera(Vector3(220.0, 0.0, 0.0), up, 240.0, 0.1)
	assert_bool(state["in_25d"]).is_true()

func test_blend_25d_is_rate_limited_and_clamped() -> void:
	var controller = auto_free(ControllerScript.new())
	controller.blend_speed = 4.0
	var up: Vector3 = _up_at(0.0)

	var state: Dictionary = controller.step_camera(Vector3(220.0, 0.0, 0.0), up, 240.0, 0.05)
	assert_float(state["blend_25d"]).is_equal_approx(0.2, EPS)
	state = controller.step_camera(Vector3(220.0, 0.0, 0.0), up, 240.0, 0.05)
	assert_float(state["blend_25d"]).is_equal_approx(0.4, EPS)
	state = controller.step_camera(Vector3(229.0, 0.0, 0.0), up, 240.0, 0.05)
	assert_float(state["blend_25d"]).is_equal_approx(0.2, EPS)

	for _i in range(50):
		state = controller.step_camera(Vector3(220.0, 0.0, 0.0), up, 240.0, 0.05)
	assert_float(state["blend_25d"]).is_equal_approx(1.0, EPS)
	for _i in range(50):
		state = controller.step_camera(Vector3(229.0, 0.0, 0.0), up, 240.0, 0.05)
	assert_float(state["blend_25d"]).is_equal_approx(0.0, EPS)

func test_aligned_prefix_is_continuous_over_360_degrees() -> void:
	var initial: Basis = ControllerScript.compute_aligned_prefix(
		Basis(Vector3.UP, PI), Vector3.UP, _up_at(0.0)
	)
	var prefix: Basis = initial
	var previous_up: Vector3 = _up_at(0.0)
	var steps: int = 240

	for i in range(1, steps + 1):
		var target: Vector3 = _up_at(TAU * float(i) / float(steps))
		var next_prefix: Basis = ControllerScript.compute_aligned_prefix(prefix, previous_up, target)
		assert_float(next_prefix.y.normalized().dot(target)).is_greater(0.9999)
		assert_float(next_prefix.x.dot(prefix.x)).is_greater(0.999)
		assert_float(next_prefix.z.dot(initial.z)).is_greater(0.999)
		assert_float(next_prefix.determinant()).is_equal_approx(1.0, 0.001)
		previous_up = target
		prefix = next_prefix

	assert_float(prefix.x.dot(initial.x)).is_greater(0.999)
	assert_float(prefix.z.dot(initial.z)).is_greater(0.999)

func test_compute_25d_basis_is_corotating_and_three_quarter() -> void:
	var up0: Vector3 = _up_at(0.0)
	var basis0: Basis = ControllerScript.compute_25d_basis(up0, 22.0)
	var tilt: float = cos(deg2rad(22.0))

	assert_float(basis0.z.dot(Vector3(0.0, 0.0, 1.0))).is_equal_approx(tilt, 1e-4)
	assert_float(basis0.y.dot(up0)).is_equal_approx(tilt, 1e-4)
	assert_float(basis0.x.dot(up0.cross(Vector3(0.0, 0.0, 1.0)))).is_equal_approx(1.0, 1e-4)
	assert_float(basis0.determinant()).is_equal_approx(1.0, 1e-4)

	# Co-rotante: al girar el up 90° alrededor de Z, la base gira igual.
	var theta: float = PI * 0.5
	var basis1: Basis = ControllerScript.compute_25d_basis(_up_at(theta), 22.0)
	var expected: Basis = Basis(Vector3(0.0, 0.0, 1.0), theta) * basis0
	var tolerance := Vector3(1e-4, 1e-4, 1e-4)
	assert_vector3(basis1.x).is_equal_approx(expected.x, tolerance)
	assert_vector3(basis1.y).is_equal_approx(expected.y, tolerance)
	assert_vector3(basis1.z).is_equal_approx(expected.z, tolerance)

func test_step_camera_full_blend_matches_25d_basis() -> void:
	var controller = auto_free(ControllerScript.new())
	controller.blend_speed = 1000.0
	var up: Vector3 = _up_at(0.0)
	var state: Dictionary = controller.step_camera(Vector3(220.0, 0.0, 0.0), up, 240.0, 0.1)
	assert_float(state["blend_25d"]).is_equal_approx(1.0, EPS)

	var expected: Basis = ControllerScript.compute_25d_basis(
		up, controller.view_25d_axial_angle_deg
	)
	var basis: Basis = state["basis"]
	var tolerance := Vector3(1e-4, 1e-4, 1e-4)
	assert_vector3(basis.x).is_equal_approx(expected.x, tolerance)
	assert_vector3(basis.y).is_equal_approx(expected.y, tolerance)
	assert_vector3(basis.z).is_equal_approx(expected.z, tolerance)

func test_apply_to_pilot_reuses_existing_rig() -> void:
	var pilot = auto_free(DummyPilot.new())
	var rig := Spatial.new()
	rig.name = "CameraRig"
	pilot.add_child(rig)
	pilot.translation = Vector3(220.0, 0.0, 0.0)
	# Como en placa 0: el Pilot ya tiene +Y alineado a _up (= -X).
	var up: Vector3 = SpinFrame.up(pilot.translation)
	var t: Transform = pilot.transform
	t.basis = Basis(Vector3(0.0, 0.0, 1.0), PI * 0.5)
	pilot.transform = t
	add_child(pilot)

	var controller = auto_free(ControllerScript.new())
	controller.blend_speed = 1000.0
	var state: Dictionary = controller.apply_to_pilot(pilot, 240.0, 0.1)
	assert_float(state["blend_25d"]).is_equal_approx(1.0, EPS)

	# El rig es hijo del Pilot: el 2.5D (mundo) debe llegar convertido a local.
	var world_target: Basis = ControllerScript.compute_25d_basis(
		up, controller.view_25d_axial_angle_deg
	)
	var expected: Basis = pilot.global_transform.basis.inverse() * world_target
	var tolerance := Vector3(1e-4, 1e-4, 1e-4)
	assert_vector3(rig.transform.basis.x).is_equal_approx(expected.x, tolerance)
	assert_vector3(rig.transform.basis.y).is_equal_approx(expected.y, tolerance)
	assert_vector3(rig.transform.basis.z).is_equal_approx(expected.z, tolerance)
	# En 3ra persona el prefijo debe seguir siendo local (identidad), sin duplicar
	# la rotación que el Pilot ya aplica a +Y.
	assert_bool(pilot.camera_basis_prefix.is_equal_approx(Basis.IDENTITY)).is_true()

func test_predict_landing_from_hub_matches_inertial_impact() -> void:
	var omega: float = SpinFrame.omega_for()
	var p0 := Vector3(0.5, 0.0, 0.0)
	var v0 := Vector3(10.0, 0.0, 0.0)
	var prediction: Dictionary = PredictorScript.predict_landing(p0, v0, omega, 240.0)

	assert_bool(prediction["hit"]).is_true()
	assert_int(int(prediction["steps"])).is_greater(0)
	var flight_time: float = float(prediction["flight_time"])
	assert_float(flight_time).is_greater(0.0)
	assert_float(float(prediction["impact_speed"])).is_greater(0.0)

	var trajectory: Array = prediction["trajectory"]
	assert_int(trajectory.size()).is_greater(1)
	var point: Vector3 = prediction["point"]
	assert_float((trajectory[trajectory.size() - 1] as Vector3).distance_to(point)).is_less(1e-5)

	var inertial_point: Vector3 = SpinFrame.to_inertial_position(point, omega, flight_time)
	var inertial_velocity: Vector3 = v0 + Vector3(0.0, 0.0, omega).cross(p0)
	var expected_point: Vector3 = p0 + inertial_velocity * flight_time
	assert_float(inertial_point.distance_to(expected_point)).is_less(0.5)

	# Pureza: no muta los argumentos.
	assert_vector3(p0).is_equal(Vector3(0.5, 0.0, 0.0))
	assert_vector3(v0).is_equal(Vector3(10.0, 0.0, 0.0))

func test_predict_landing_immediate_hit_outside_surface() -> void:
	var prediction: Dictionary = PredictorScript.predict_landing(
		Vector3(241.0, 0.0, 0.0), Vector3.ZERO, 0.2, 240.0
	)
	assert_bool(prediction["hit"]).is_true()
	assert_int(int(prediction["steps"])).is_equal(0)
	assert_float(float(prediction["flight_time"])).is_equal_approx(0.0, EPS)

func test_preview_is_visible_only_in_free_flight() -> void:
	var predictor = auto_free(PredictorScript.new())
	add_child(predictor)
	var omega: float = SpinFrame.omega_for()

	var prediction: Dictionary = predictor.update_preview(
		Vector3(0.5, 0.0, 0.0), Vector3(10.0, 0.0, 0.0), omega, 240.0, true
	)
	assert_bool(prediction["hit"]).is_true()
	assert_bool(predictor.visible).is_true()

	var ring: Spatial = predictor.get_node("LandingRing") as Spatial
	var trail: Spatial = predictor.get_node("LandingTrajectory") as Spatial
	assert_object(ring).is_not_null()
	assert_object(trail).is_not_null()
	assert_bool(ring.visible).is_true()
	assert_bool(trail.visible).is_true()

	predictor.update_preview(
		Vector3(0.5, 0.0, 0.0), Vector3(10.0, 0.0, 0.0), omega, 240.0, false
	)
	assert_bool(predictor.visible).is_false()
	assert_bool(ring.visible).is_false()
	assert_bool(trail.visible).is_false()
