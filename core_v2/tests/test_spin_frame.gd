extends GdUnitTestSuite

# FD-323 — contrato matemático de SpinFrame (marco rotante, eje Z).

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const PredictorScript = preload("res://core_v2/camera/SpinLandingPredictor.gd")

func test_omega_for_matches_reference_cylinder() -> void:
	var omega: float = SpinFrame.omega_for()
	assert_float(omega).is_equal_approx(sqrt(9.8 / 240.0), 1e-9)
	assert_float(omega).is_equal_approx(0.2020725942, 1e-9)
	assert_float(SpinFrame.omega_for(14.0, 240.0)).is_equal_approx(sqrt(14.0 / 240.0), 1e-9)
	assert_float(SpinFrame.omega_for(9.8, 0.0)).is_equal_approx(0.0, 1e-12)

func test_r_perp_projects_onto_xy_plane() -> void:
	assert_vector3(SpinFrame.r_perp(Vector3(3.0, -4.0, 7.0))).is_equal(Vector3(3.0, -4.0, 0.0))
	assert_vector3(SpinFrame.r_perp(Vector3(0.0, 0.0, 4000.0))).is_equal(Vector3.ZERO)

func test_up_points_towards_cylinder_axis() -> void:
	var up: Vector3 = SpinFrame.up(Vector3(3.0, -4.0, 7.0))
	assert_float(up.distance_to(Vector3(-0.6, 0.8, 0.0))).is_less(1e-6)
	assert_float(up.length()).is_equal_approx(1.0, 1e-6)

func test_up_uses_fallback_near_axis() -> void:
	var fallback: Vector3 = Vector3(0.0, 0.0, 2.0)
	var up: Vector3 = SpinFrame.up(Vector3(1e-4, 0.0, 5.0), fallback)
	assert_float(up.distance_to(Vector3(0.0, 0.0, 1.0))).is_less(1e-6)

	# Fallback cero no debe producir NaN: se usa Vector3.UP.
	var zero_fallback: Vector3 = SpinFrame.up(Vector3.ZERO, Vector3.ZERO)
	assert_float(zero_fallback.distance_to(Vector3.UP)).is_less(1e-6)

	# r_eps configurable: por dentro usa fallback, por fuera usa el radial.
	var inside: Vector3 = SpinFrame.up(Vector3(0.01, 0.0, 0.0), Vector3.UP, 0.02)
	assert_float(inside.distance_to(Vector3.UP)).is_less(1e-6)
	var outside: Vector3 = SpinFrame.up(Vector3(0.03, 0.0, 0.0), Vector3.UP, 0.02)
	assert_float(outside.distance_to(Vector3.LEFT)).is_less(1e-6)

func test_centrifugal_and_coriolis_accelerations() -> void:
	assert_vector3(SpinFrame.a_centrif(Vector3(2.0, 3.0, 9.0), 0.5)) \
		.is_equal_approx(Vector3(0.5, 0.75, 0.0), Vector3(1e-9, 1e-9, 1e-9))
	# -2 * (0,0,0.5) x (1,2,3) = (2,-1,0)
	assert_vector3(SpinFrame.a_coriolis(Vector3(1.0, 2.0, 3.0), 0.5)) \
		.is_equal_approx(Vector3(2.0, -1.0, 0.0), Vector3(1e-9, 1e-9, 1e-9))
	assert_vector3(SpinFrame.a_coriolis(Vector3(4.0, -2.0, 0.0), 0.0)).is_equal(Vector3.ZERO)
	assert_vector3(SpinFrame.a_coriolis(Vector3(0.0, 0.0, 5.0), 0.7)).is_equal(Vector3.ZERO)

func test_rotate_coriolis_is_exact_norm_preserving_rotation() -> void:
	var v: Vector3 = Vector3(3.0, -2.0, 1.0)
	var rotated: Vector3 = SpinFrame.rotate_coriolis(v, 0.7, 1.0 / 60.0)
	assert_float(rotated.length()).is_equal_approx(v.length(), 1e-6)
	assert_float(rotated.z).is_equal_approx(v.z, 1e-9)

	# -2*omega*dt = -pi/2: (1,0,0) -> (0,-1,0).
	var quarter: Vector3 = SpinFrame.rotate_coriolis(Vector3(1.0, 0.0, 0.0), PI * 0.5, 0.5)
	assert_float(quarter.distance_to(Vector3(0.0, -1.0, 0.0))).is_less(1e-6)

func test_jacobi_analytic_values() -> void:
	assert_float(SpinFrame.jacobi(Vector3(2.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), 0.5)) \
		.is_equal_approx(0.0, 1e-9)
	assert_float(SpinFrame.jacobi(Vector3(0.0, 0.0, 10.0), Vector3(0.0, 0.0, 2.0), 0.5)) \
		.is_equal_approx(2.0, 1e-9)

func test_free_flight_conserves_jacobi_over_30_seconds() -> void:
	var omega: float = SpinFrame.omega_for()
	var dt: float = 1.0 / 60.0
	var cases: Array = [
		{"p": Vector3(200.0, 0.0, 0.0), "v": Vector3(0.0, 30.0, 0.0)},
		{"p": Vector3(0.0, 150.0, 10.0), "v": Vector3(20.0, 0.0, -5.0)},
		{"p": Vector3(240.0, 0.0, 0.0), "v": Vector3.ZERO},
		{"p": Vector3(50.0, 50.0, 0.0), "v": Vector3(-10.0, 5.0, 2.0)}
	]

	for case_data in cases:
		var p: Vector3 = case_data["p"]
		var v: Vector3 = case_data["v"]
		var j0: float = SpinFrame.jacobi(p, v, omega)

		for i in range(1800):
			var state: Dictionary = SpinFrame.step_free_flight(p, v, omega, dt)
			assert_bool(state.has("position")).is_true()
			assert_bool(state.has("velocity")).is_true()
			p = state["position"]
			v = state["velocity"]

		var j1: float = SpinFrame.jacobi(p, v, omega)
		var relative_error: float = abs(j1 - j0) / max(abs(j0), 1e-9)
		assert_float(relative_error).is_less(1e-3)

func test_free_flight_step_is_deterministic() -> void:
	var omega: float = SpinFrame.omega_for()
	var dt: float = 1.0 / 60.0
	var p: Vector3 = Vector3(120.0, -40.0, 7.0)
	var v: Vector3 = Vector3(3.0, 12.0, -2.0)

	var a: Dictionary = SpinFrame.step_free_flight(p, v, omega, dt)
	var b: Dictionary = SpinFrame.step_free_flight(p, v, omega, dt)
	assert_vector3(a["position"]).is_equal(b["position"])
	assert_vector3(a["velocity"]).is_equal(b["velocity"])

func test_free_fall_impact_matches_inertial_straight_line() -> void:
	var omega: float = SpinFrame.omega_for()
	var dt: float = 1.0 / 60.0
	var p0: Vector3 = Vector3(0.5, 0.0, 0.0)
	var v0: Vector3 = Vector3(10.0, 0.0, 0.0)
	var p: Vector3 = p0
	var v: Vector3 = v0
	var t: float = 0.0
	var steps: int = 0

	while SpinFrame.r_perp(p).length() < 240.0 and steps < 20000:
		var state: Dictionary = SpinFrame.step_free_flight(p, v, omega, dt)
		p = state["position"]
		v = state["velocity"]
		t += dt
		steps += 1

	assert_bool(SpinFrame.r_perp(p).length() >= 240.0).is_true()

	# Sin fuerza externa, en el marco inercial la partícula va en línea recta.
	var v_inertial: Vector3 = v0 + Vector3(0.0, 0.0, omega).cross(p0)
	var expected: Vector3 = p0 + v_inertial * t
	var actual: Vector3 = SpinFrame.to_inertial_position(p, omega, t)
	assert_float(actual.distance_to(expected)).is_less(0.5)

	# Ida y vuelta rotante <-> inercial.
	var round_trip: Vector3 = SpinFrame.from_inertial_position(actual, omega, t)
	assert_float(round_trip.distance_to(p)).is_less(1e-6)

func test_a_axial_vec_points_towards_stern() -> void:
	assert_vector3(SpinFrame.a_axial_vec(9.8)) \
		.is_equal_approx(Vector3(0.0, 0.0, -9.8), Vector3(1e-9, 1e-9, 1e-9))
	assert_vector3(SpinFrame.a_axial_vec(0.0)).is_equal(Vector3.ZERO)
	assert_vector3(SpinFrame.a_axial_vec(-3.0)) \
		.is_equal_approx(Vector3(0.0, 0.0, 3.0), Vector3(1e-9, 1e-9, 1e-9))

func test_g_eff_and_up_eff_analytic() -> void:
	var p := Vector3(3.0, -4.0, 7.0)
	var tol := Vector3(1e-9, 1e-9, 1e-9)
	# Centrífuga pura (a_axial = 0): idéntica a a_centrif.
	assert_vector3(SpinFrame.g_eff(p, 0.5)) \
		.is_equal_approx(Vector3(0.75, -1.0, 0.0), tol)
	# Con empuje axial: se suma sobre Z, hacia popa.
	assert_vector3(SpinFrame.g_eff(p, 0.5, 9.8)) \
		.is_equal_approx(Vector3(0.75, -1.0, -9.8), tol)

	# Sin axial, up_eff coincide con up (radial hacia el eje).
	assert_float(SpinFrame.up_eff(p, 0.5).distance_to(Vector3(-0.6, 0.8, 0.0))) \
		.is_less(1e-6)
	# Cerca del eje el axial solo define el arriba: -Z de gravedad -> +Z.
	var near_axis := Vector3(0.0001, 0.0, 5.0)
	assert_float(SpinFrame.up_eff(near_axis, 0.0, 9.8).distance_to(Vector3(0.0, 0.0, 1.0))) \
		.is_less(1e-6)
	# Sin gravedad efectiva se usa el fallback normalizado.
	assert_float(SpinFrame.up_eff(near_axis, 0.0, 0.0, Vector3(0.0, 0.0, 2.0)) \
		.distance_to(Vector3(0.0, 0.0, 1.0))).is_less(1e-6)
	# Fallback cero no produce NaN: se conserva Vector3.UP.
	assert_float(SpinFrame.up_eff(Vector3.ZERO, 0.0, 0.0, Vector3.ZERO) \
		.distance_to(Vector3.UP)).is_less(1e-6)
	assert_float(SpinFrame.up_eff(near_axis, 0.0, 9.8).length()).is_equal_approx(1.0, 1e-6)

func test_step_free_flight_axial_matches_analytic_and_keeps_xy() -> void:
	var omega: float = SpinFrame.omega_for()
	var dt: float = 1.0 / 60.0
	var steps: int = 1800
	var total_t: float = float(steps) * dt

	# Vector3 usa float32: para exigir error ABSOLUTO < 1e-4 en 30 s se usa una
	# magnitud axial chica (z ~ -4.5 m). Ignorar o escalar mal a_axial falla por
	# órdenes de magnitud, así que la prueba sigue siendo discriminante.
	var p0 := Vector3(200.0, 0.0, 0.0)
	var v0 := Vector3(0.0, 30.0, 0.0)
	var a_axial := 0.01
	var p_axial: Vector3 = p0
	var v_axial: Vector3 = v0
	var p_flat: Vector3 = p0
	var v_flat: Vector3 = v0
	for _i in range(steps):
		var axial_state: Dictionary = SpinFrame.step_free_flight_axial(
			p_axial, v_axial, omega, dt, a_axial
		)
		p_axial = axial_state["position"]
		v_axial = axial_state["velocity"]
		var flat_state: Dictionary = SpinFrame.step_free_flight(p_flat, v_flat, omega, dt)
		p_flat = flat_state["position"]
		v_flat = flat_state["velocity"]

	var expected_z: float = p0.z + v0.z * total_t - 0.5 * a_axial * total_t * total_t
	assert_float(abs(p_axial.z - expected_z)).is_less(1e-4)
	assert_float(abs(v_axial.z - (v0.z - a_axial * total_t))).is_less(1e-4)
	# El axial sólo toca Z: el plano XY queda exactamente igual al vuelo libre.
	assert_float(abs(p_axial.x - p_flat.x)).is_less(1e-9)
	assert_float(abs(p_axial.y - p_flat.y)).is_less(1e-9)

	# Perfil completo (9.8 m/s²): con float32 el error absoluto a 30 s es ~0.07 m,
	# así que se valida la exactitud relativa contra la misma fórmula analítica.
	var p_full := Vector3(200.0, 0.0, 50.0)
	var v_full := Vector3(0.0, 30.0, -4.0)
	var p_full_run: Vector3 = p_full
	var v_full_run: Vector3 = v_full
	for _i in range(steps):
		var state: Dictionary = SpinFrame.step_free_flight_axial(
			p_full_run, v_full_run, omega, dt, 9.8
		)
		p_full_run = state["position"]
		v_full_run = state["velocity"]
	var full_expected_z: float = p_full.z + v_full.z * total_t - 0.5 * 9.8 * total_t * total_t
	var relative_error: float = abs(p_full_run.z - full_expected_z) / abs(full_expected_z)
	assert_float(relative_error).is_less(1e-4)
	assert_float(abs(p_full_run.z - full_expected_z)).is_less(0.5)

func test_predict_landing_with_axial_matches_analytic_z() -> void:
	var omega: float = SpinFrame.omega_for()
	var p0 := Vector3(0.5, 0.0, 0.0)
	var v0 := Vector3(10.0, 0.0, 0.0)
	var a_axial := 9.8

	var flat: Dictionary = PredictorScript.predict_landing(p0, v0, omega, 240.0)
	var axial: Dictionary = PredictorScript.predict_landing(
		p0, v0, omega, 240.0, 1.0 / 60.0, 1800, a_axial
	)

	assert_bool(axial["hit"]).is_true()
	# El axial no cambia la dinámica radial: mismo tiempo de vuelo y pasos.
	assert_float(float(axial["flight_time"])).is_equal_approx(float(flat["flight_time"]), 1e-6)
	assert_int(int(axial["steps"])).is_equal(int(flat["steps"]))

	var flight_time: float = float(axial["flight_time"])
	var point: Vector3 = axial["point"]
	var expected_z: float = -0.5 * a_axial * flight_time * flight_time
	assert_float(abs(point.z - expected_z)).is_less(0.5)
	assert_float(SpinFrame.r_perp(point).length()).is_equal_approx(240.0, 1.0)

	# Pureza: no muta los argumentos.
	assert_vector3(p0).is_equal(Vector3(0.5, 0.0, 0.0))
	assert_vector3(v0).is_equal(Vector3(10.0, 0.0, 0.0))
