extends GdUnitTestSuite

# FD-321 — contrato matemático de SpinFrame (marco rotante, eje Z).

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")

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
