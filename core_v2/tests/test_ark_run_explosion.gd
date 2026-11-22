extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# FD-324 F1 - inicio ZERO_G en el nucleo, eyeccion al Puente y propulsores LT.
# Todo puro/headless: no depende de input real ni de escenas pesadas.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const ExplosionScript = preload("res://core_v2/levels/ark_run/ArkRunExplosion.gd")
const HandrailsScript = preload("res://core_v2/levels/ark_run/ArkRunHubHandrails.gd")
const ThrusterScript = preload("res://core_v2/levels/ark_run/ArkRunThrusterInput.gd")
const SpinRealPhysicsV2 = preload("res://core_v2/player/SpinRealPhysicsV2.gd")

const DT := 1.0 / 60.0
const EPS := 0.000001
const LANDING_SLIDE := 1
const LANDING_TUMBLE := 2

class FakePilot:
	extends KinematicBody
	var velocity := Vector3.ZERO
	var spin_enabled := false
	var sim_up := Vector3.UP
	func set_spin_real_enabled(enabled: bool) -> void:
		spin_enabled = enabled
	func set_sim_up(up_vec: Vector3) -> void:
		sim_up = up_vec
	func get_sim_up() -> Vector3:
		return sim_up
	func get_spin_physics():
		return null

func _spiral_config() -> Dictionary:
	return {"turns": 2.0, "total_height": 2000.0, "plate_step": 40.0, "r_min": 220.0, "r_max": 260.0, "phase": 0.0}

func _bridge_target() -> Vector3:
	return SpiralGeometry.plate_transform(_spiral_config(), 48).origin
func _steps(seconds: float) -> int:
	return int(round(seconds / DT))

func _integrate(start: Vector3, v0: Vector3, omega: float, steps: int) -> Dictionary:
	var p: Vector3 = start
	var v: Vector3 = v0
	for _i in range(steps):
		var state: Dictionary = SpinFrame.step_free_flight(p, v, omega, DT)
		p = state["position"]
		v = state["velocity"]
	return {"position": p, "velocity": v}

func _run_launch(seconds: float) -> Dictionary:
	var omega: float = SpinFrame.omega_for()
	var start := Vector3(4.0, 0.0, 0.0)
	var solution: Dictionary = ExplosionScript.solve_bridge_launch(
		start, _bridge_target(), omega, seconds
	)
	var end: Dictionary = _integrate(start, solution["velocity"], omega, _steps(seconds))
	return {"solution": solution, "end": end}

# 1. Nucleo co-rotante: pared a ~1.6 m/s y agarre con tiron suave sin saltos.
func test_core_handrail_converges_smoothly() -> void:
	var omega: float = SpinFrame.omega_for()
	assert_float(HandrailsScript.wall_speed(omega)).is_equal_approx(1.6, 0.05)
	var position := Vector3(8.0, 0.0, 0.0)
	assert_bool(HandrailsScript.is_in_core(position)).is_true()
	assert_bool(HandrailsScript.is_in_core(Vector3(0.0, 0.0, 500.0))).is_false()

	var rail: Vector3 = HandrailsScript.rail_velocity_at(position, omega)
	assert_float(rail.length()).is_equal_approx(omega * 8.0, 1e-5)
	assert_float(rail.z).is_equal_approx(0.0, EPS)
	assert_float(rail.dot(Vector3(1.0, 0.0, 0.0))).is_equal_approx(0.0, 1e-5)

	var max_accel := 6.0
	var max_step: float = max_accel * DT
	var current := Vector3.ZERO
	for _i in range(30):
		var next: Vector3 = HandrailsScript.converge_velocity(current, rail, DT, max_accel)
		assert_float((next - current).length()).is_less_equal(max_step + EPS)
		current = next
	assert_float(current.distance_to(rail)).is_less(0.01)
	# Determinismo: dos corridas identicas.
	var replay := Vector3.ZERO
	for _i in range(30):
		replay = HandrailsScript.converge_velocity(replay, rail, DT, max_accel)
	assert_vector3(replay).is_equal(current)

	# Nodo de pasamanos sobre un piloto real (fake en ZERO_G).
	var fake := FakePilot.new()
	auto_free(fake)
	fake.translation = Vector3(8.0, 0.0, 0.0)
	var handrails = auto_free(HandrailsScript.new())
	handrails.grab(fake)
	assert_bool(handrails.is_grabbed()).is_true()
	var stepped: Vector3 = handrails.convergence_step(position, Vector3.ZERO, DT)
	assert_float(stepped.length()).is_less_equal(max_step + EPS)
	assert_float(stepped.angle_to(rail)).is_less(1e-5)
	handrails.release()
	assert_bool(handrails.is_grabbed()).is_false()

# 2. Eyeccion: ventana 15-25 s, llegada al Puente < 1 m y slide sin muerte.
func test_solve_bridge_launch_lands_slide() -> void:
	var omega: float = SpinFrame.omega_for()
	var target: Vector3 = _bridge_target()
	assert_float(target.z).is_greater(880.0)

	var run: Dictionary = _run_launch(20.0)
	var solution: Dictionary = run["solution"]
	var end: Dictionary = run["end"]
	assert_float(float(solution["flight_time"])).is_equal_approx(20.0, EPS)
	var distance: float = Vector3(4.0, 0.0, 0.0).distance_to(target)
	var inertial_speed: float = float(solution["inertial_speed"])
	assert_float(abs(inertial_speed - distance / 20.0)).is_less(distance * 0.01)
	assert_float(end["position"].distance_to(target)).is_less(1.0)

	var physics = auto_free(SpinRealPhysicsV2.new())
	var up: Vector3 = SpinFrame.up(target)
	var entry: float = ExplosionScript.landing_entry_speed(end["velocity"], up)
	assert_float(entry).is_greater_equal(physics.spin_v_safe)
	assert_float(entry).is_less(physics.spin_v_slide)
	assert_int(physics.classify_landing(entry)).is_equal(LANDING_SLIDE)

	# En toda la ventana 15-25 s nunca hay tumble (sin muerte).
	for seconds in [15.0, 20.0, 25.0]:
		var window: Dictionary = _run_launch(seconds)
		assert_float(window["end"]["position"].distance_to(target)).is_less(1.0)
		var w_entry: float = ExplosionScript.landing_entry_speed(window["end"]["velocity"], up)
		assert_int(physics.classify_landing(w_entry)).is_not_equal(LANDING_TUMBLE)

	# Entrada de alta velocidad se acota a SLIDE (aterrizaje grande sin muerte).
	var resolved: Dictionary = ExplosionScript.resolve_bridge_landing(
		physics, null, -up * 50.0, up
	)
	assert_float(float(resolved["entry_speed"])).is_equal_approx(50.0, 0.1)
	assert_int(int(resolved["landing"])).is_equal(LANDING_SLIDE)

	# El tiempo de vuelo se acota a la ventana publicada.
	assert_float(float(ExplosionScript.solve_bridge_launch(Vector3(4.0, 0.0, 0.0), target, omega, 5.0)["flight_time"])).is_equal_approx(15.0, EPS)
	assert_float(float(ExplosionScript.solve_bridge_launch(Vector3(4.0, 0.0, 0.0), target, omega, 99.0)["flight_time"])).is_equal_approx(25.0, EPS)

# 3. Propulsores LT: desvian el aterrizaje y respetan el presupuesto finito de dv.
func test_thrusters_deflect_and_respect_dv_budget() -> void:
	var ballistic: Dictionary = _run_launch(20.0)
	var solution: Dictionary = ballistic["solution"]
	var start := Vector3(4.0, 0.0, 0.0)
	var physics = auto_free(SpinRealPhysicsV2.new())
	var p: Vector3 = start
	var v: Vector3 = solution["velocity"]
	var total_dv := 0.0
	var direction := Vector3(0.0, 1.0, 0.0)
	for _i in range(_steps(20.0)):
		var state: Dictionary = ThrusterScript.step_with_thrust(
			physics, p, v, DT, direction, 1.0, false
		)
		p = state["position"]
		v = state["velocity"]
		total_dv += float(state["dv"])

	assert_float(total_dv).is_equal_approx(physics.spin_thruster_dv_max, 0.01)
	assert_float(total_dv).is_less_equal(physics.spin_thruster_dv_max + EPS)
	assert_float(physics.spin_thruster_dv_remaining).is_less(EPS)
	assert_float(p.distance_to(ballistic["end"]["position"])).is_greater(10.0)

	# Gating LT / tecla y mapeo de direccion.
	assert_bool(ThrusterScript.is_thrusting(0.0, false)).is_false()
	assert_bool(ThrusterScript.is_thrusting(0.9, false)).is_true()
	assert_bool(ThrusterScript.is_thrusting(0.0, true)).is_true()
	var forward: Vector3 = ThrusterScript.thrust_direction(Vector2(0.0, -1.0), Basis.IDENTITY, Vector3.UP)
	assert_float(forward.distance_to(Vector3(0.0, 0.0, -1.0))).is_less(1e-6)
	var right: Vector3 = ThrusterScript.thrust_direction(Vector2(1.0, 0.0), Basis.IDENTITY, Vector3.UP)
	assert_float(right.distance_to(Vector3(1.0, 0.0, 0.0))).is_less(1e-6)

# 4. Predictor solo en vuelo libre fuera del hub; detonacion y determinismo.
func test_predictor_gating_detonate_and_determinism() -> void:
	assert_bool(ExplosionScript.should_show_predictor(
		Vector3(4.0, 0.0, 0.0), Vector3.ZERO, 8.0, false, false)).is_false()
	assert_bool(ExplosionScript.should_show_predictor(
		Vector3(6.0, 0.0, 0.0), Vector3(0.0, 0.0, 40.0), 8.0, true, false)).is_false()
	assert_bool(ExplosionScript.should_show_predictor(
		Vector3(6.0, 0.0, 400.0), Vector3(0.0, 0.0, 40.0), 8.0, true, false)).is_false()
	assert_bool(ExplosionScript.should_show_predictor(
		Vector3(40.0, 0.0, 50.0), Vector3(0.0, 0.0, 40.0), 8.0, true, false)).is_true()
	assert_bool(ExplosionScript.should_show_predictor(
		Vector3(40.0, 0.0, 50.0), Vector3(0.0, 0.0, 40.0), 8.0, true, true)).is_false()

	var explosion = auto_free(ExplosionScript.new())
	explosion.bridge_target = _bridge_target()
	explosion.flight_time = 20.0
	var fake := FakePilot.new()
	auto_free(fake)
	fake.translation = Vector3(4.0, 0.0, 0.0)
	add_child(fake)
	var result: Dictionary = explosion.detonate(fake)
	assert_bool(fake.spin_enabled).is_true()
	assert_vector3(fake.velocity).is_equal(result["velocity"])
	assert_bool(explosion.launched).is_true()
	assert_float(explosion.get_flight_elapsed()).is_equal_approx(0.0, EPS)

	var run_a: Dictionary = _run_launch(20.0)
	var run_b: Dictionary = _run_launch(20.0)
	assert_vector3(run_a["end"]["position"]).is_equal(run_b["end"]["position"])
	assert_vector3(run_a["end"]["velocity"]).is_equal(run_b["end"]["velocity"])
