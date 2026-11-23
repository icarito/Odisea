extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# FD-324 F5 — disparo por cruce z<=0 de regreso, perfil axial, conversión de
# terrazas con tracking de plataformas en SPIN_REAL, predictor analítico y
# falla estática determinista (industria + ascensores + escalera de respaldo).

const IgnitionScript = preload("res://core_v2/levels/ark_run/ArkRunEngineIgnition.gd")
const ConversionScript = preload("res://core_v2/levels/ark_run/ArkRunTerraceConversion.gd")
const StreamerScript = preload("res://core_v2/levels/ark_run/ArkRunIndustryStreamer.gd")
const Catalog = preload("res://core_v2/levels/ark_run/ArkRunIndustryChunk.gd")
const SpokeScript = preload("res://core_v2/components/SpinSpokeV2.gd")
const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const PredictorScript = preload("res://core_v2/camera/SpinLandingPredictor.gd")
const PilotScene = preload("res://core_v2/actors/Pilot_v2.tscn")
const GravityModes = preload("res://core_v2/systems/GravityModes.gd")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")
const DT := 1.0 / 60.0
const SEED := 32401
const SPIRAL := {"turns": 2.0, "total_height": 2000.0, "plate_step": 40.0, "r_min": 220.0, "r_max": 260.0, "phase": 0.0}

class StubPilot:
	extends KinematicBody
	var velocity := Vector3()
	var spin_real := true
	var _up := Vector3.UP
	func is_spin_real_active() -> bool: return spin_real
	func set_sim_up(up_vec: Vector3) -> void: _up = up_vec
	func get_sim_up() -> Vector3: return _up

var _prev_gravity_mode := -1
func before() -> void:
	var world = get_node_or_null("/root/GravityWorld")
	if world != null: _prev_gravity_mode = int(world.get_current_gravity_mode())
func after() -> void:
	var world = get_node_or_null("/root/GravityWorld")
	if world != null and _prev_gravity_mode >= 0: world.set_gravity_mode(_prev_gravity_mode)

func _new_ignition():
	var ign = auto_free(IgnitionScript.new())
	add_child(ign)
	ign.set_physics_process(false)
	return ign

func _fire(ign) -> void:
	ign.advance(DT, 620.0)  # arma en proa (>= bridge_arm_z)
	ign.advance(DT, 100.0)  # vuelta: aviso previo (<= warning_z)
	ign.advance(DT, 1.0)
	ign.advance(DT, -1.0)   # cruce exacto z<=0 de regreso

func test_ignition_triggers_only_on_return_z_cross_and_ramps() -> void:
	var ign = _new_ignition()
	assert_str(ign.get_state_name()).is_equal("IDLE")
	ign.advance(DT, 100.0)
	ign.advance(DT, -1.0)  # cruce sin haber pasado proa: no dispara
	assert_bool(ign.is_ignited()).is_false()
	assert_int(ign.get_state()).is_equal(IgnitionScript.State.IDLE)
	var early = _new_ignition()
	early.advance(DT, 620.0)
	assert_bool(early.is_armed()).is_true()
	assert_bool(early.is_ignited()).is_false()
	early.advance(DT, 100.0)
	assert_int(early.get_state()).is_equal(IgnitionScript.State.WARNING)
	early.advance(DT, 1.0)
	assert_bool(early.is_ignited()).is_false()  # z>0 todavía no cruza
	early.advance(DT, -1.0)
	assert_bool(early.is_ignited()).is_true()
	assert_int(early.get_state()).is_equal(IgnitionScript.State.RAMP)
	assert_float(early.get_time_since_ignite()).is_equal_approx(0.0, 1e-9)
	early.advance(DT, -1.0)  # repetir el cruce no re-dispara
	assert_float(early.get_time_since_ignite()).is_equal_approx(DT, 1e-9)
	early.advance(1.5 - DT, -1.0)  # 4.9 @ 1.5s
	assert_float(early.get_time_since_ignite()).is_equal_approx(1.5, 1e-9)
	assert_float(early.get_axial_accel()).is_equal_approx(4.9, 1e-4)
	early.advance(1.51, -1.0)      # supera 3s -> SUSTAINED, 9.8
	assert_int(early.get_state()).is_equal(IgnitionScript.State.SUSTAINED)
	assert_float(early.get_axial_accel()).is_equal_approx(9.8, 1e-4)
	early.advance(29.98, -1.0)     # hold casi 30 s
	assert_float(early.get_time_since_ignite()).is_equal_approx(32.99, 1e-6)
	assert_int(early.get_state()).is_equal(IgnitionScript.State.SUSTAINED)
	assert_float(early.get_axial_accel()).is_equal_approx(9.8, 1e-4)
	early.advance(0.02, -1.0)      # fin del hold -> COOLDOWN
	assert_int(early.get_state()).is_equal(IgnitionScript.State.COOLDOWN)
	assert_float(early.get_axial_accel()).is_equal_approx(0.0, 1e-9)

func test_axial_profile_and_predictor_match_free_flight() -> void:
	for pair in [[-1.0, 0.0], [0.0, 0.0], [1.5, 4.9], [3.0, 9.8], [20.0, 9.8], [33.0, 9.8], [33.1, 0.0]]:
		assert_float(IgnitionScript.sample_axial_accel(float(pair[0]))).is_equal_approx(float(pair[1]), 1e-4)
	var omega: float = SpinFrame.omega_for()
	var pos := Vector3(240.0, 0.0, 0.0)
	var vel := Vector3(0.0, 5.0, 1.0)
	var prediction: Dictionary = PredictorScript.predict_landing(pos, vel, omega, 1000.0, DT, 3, 9.8)
	assert_bool(bool(prediction["hit"])).is_false()
	var step1: Dictionary = SpinFrame.step_free_flight_axial(pos, vel, omega, DT, 9.8)
	var step2: Dictionary = SpinFrame.step_free_flight_axial(step1["position"], step1["velocity"], omega, DT, 9.8)
	assert_vector3(prediction["trajectory"][1]).is_equal_approx(step1["position"], Vector3(1e-6, 1e-6, 1e-6))
	assert_vector3(prediction["trajectory"][2]).is_equal_approx(step2["position"], Vector3(1e-6, 1e-6, 1e-6))

func test_terrace_conversion_converges_to_up_eff_in_three_seconds() -> void:
	var conv = auto_free(ConversionScript.new()); add_child(conv); conv.set_physics_process(false)
	conv.omega = SpinFrame.omega_for(); conv.fallback_a_axial = 9.8
	var origin := Vector3(240.0, 0.0, 0.0)
	var basis := Basis(Vector3.UP, -Vector3.RIGHT, Vector3(0.0, 0.0, 1.0))
	conv.create_plate(Transform(basis, origin), Vector3(40.0, 0.4, 40.0), "Plate")
	var target: Vector3 = SpinFrame.up_eff(origin, conv.omega, 9.8)
	conv.start_conversion()
	for _i in range(30):
		conv.advance(DT)
	assert_float(conv.get_plate_normal().dot(target)).is_less(0.999)  # aún no converge
	while conv.is_active():
		conv.advance(DT)
	assert_float(conv.get_elapsed()).is_equal_approx(3.0, 1e-9)
	assert_vector3(conv.get_plate_normal()).is_equal_approx(target, Vector3(1e-3, 1e-3, 1e-3))

func test_ignition_deterministic_failures_and_backup_ladder() -> void:
	var streamer = auto_free(StreamerScript.new()); streamer.sector_count = 3; streamer.ring_slots = 2; add_child(streamer)
	var ign = _new_ignition()
	ign.set_industry_streamer(streamer)
	var spokes := []
	for plate_index in [5, 10, 15, 20, 25, 30, 35, 40]:
		var spoke = auto_free(SpokeScript.new())
		spoke.name = "Spoke_%02d" % plate_index
		add_child(spoke)
		spoke.configure_from_plate(SpiralGeometry.plate_transform(SPIRAL, plate_index), 8.0)
		spokes.append(spoke)
		ign.add_elevator(spoke.get_elevator())
	_fire(ign)
	assert_str(String(streamer.get_route_state_summary()["mode"])).is_equal(Catalog.GRAVITY_AXIAL)
	var reference = auto_free(StreamerScript.new()); reference.sector_count = 3; reference.ring_slots = 2; add_child(reference)
	reference.apply_gravity_mode(Catalog.GRAVITY_AXIAL)
	assert_dict(streamer.get_route_state_summary()).is_equal(reference.get_route_state_summary())
	var decisions: Array = ign.get_elevator_decisions()
	assert_int(decisions.size()).is_equal(spokes.size())
	for i in range(decisions.size()):
		var decision: Dictionary = decisions[i]
		assert_bool(bool(decision["failed"])).is_equal(IgnitionScript.should_fail_index(SEED, i))
	var verified_failed := false
	var verified_operational := false
	for spoke in spokes:
		var elevator = spoke.get_elevator()
		var probe = auto_free(StubPilot.new())
		add_child(probe)
		probe.global_transform.origin = Vector3(elevator.get_outer_radius() - 4.0, 0.0, elevator.get_z_center())
		var moved: bool = bool(spoke.step_backup_ladder(probe, 1.0, 0.1)["moved"])
		if not elevator.is_operational():
			assert_bool(moved).is_true()
			verified_failed = true
		elif not verified_operational:
			assert_bool(moved).is_false()
			verified_operational = true
	assert_bool(verified_failed).is_true()
	assert_bool(verified_operational).is_true()
	var keys: Array = ign.get_collapse_keys()
	var has_elevator := false
	var conn_key := ""
	for k in keys:
		if String(k).begins_with("elevator:"): has_elevator = true
		elif String(k).begins_with("conn:") and conn_key == "": conn_key = str(k)
	assert_bool(has_elevator).is_true()
	assert_bool(conn_key != "").is_true()
	var state0: Dictionary = ign.get_collapse_state(conn_key)
	var target = state0["node"]
	assert_bool(target is RigidBody).is_false()  # colapso cinemático, sin RigidBody
	ign.advance(0.5, -1.0)
	var state1: Dictionary = ign.get_collapse_state(conn_key)
	assert_float(float(state1["u"]) - float(state0["u"])).is_equal_approx(0.5, 1e-6)
	assert_float(state0["base"].origin.distance_to(target.global_transform.origin)).is_greater(0.0)
	ign.advance(0.6, -1.0)
	var state2: Dictionary = ign.get_collapse_state(conn_key)
	assert_bool(bool(state2["done"])).is_true()
	assert_float(float(state2["u"])).is_equal_approx(1.0, 1e-9)
	var fixed_origin: Vector3 = target.global_transform.origin
	ign.advance(0.5, -1.0)
	assert_vector3(target.global_transform.origin).is_equal_approx(fixed_origin, Vector3(1e-6, 1e-6, 1e-6))

func test_collapse_profile_is_pure_and_deterministic() -> void:
	var base := Transform(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0))
	var a: Transform = ConversionScript.sample_collapse(base, 0.5, Vector3(0, 0, -1), deg2rad(10.0), 0.6)
	var b: Transform = ConversionScript.sample_collapse(base, 0.5, Vector3(0, 0, -1), deg2rad(10.0), 0.6)
	assert_vector3(a.origin).is_equal(b.origin)
	assert_float(a.origin.distance_to(base.origin)).is_equal_approx(0.3, 1e-6)
	assert_float(ConversionScript.collapse_progress(-1.0)).is_equal_approx(0.0, 1e-9)
	assert_float(ConversionScript.collapse_progress(0.5)).is_equal_approx(0.5, 1e-9)
	assert_float(ConversionScript.collapse_progress(2.0)).is_equal_approx(1.0, 1e-9)

func test_kinematic_plate_carries_pilot_in_spin_real() -> void:
	get_node("/root/GravityWorld").set_gravity_mode(GravityModes.Mode.SPIN_REAL)
	var conv = auto_free(ConversionScript.new()); add_child(conv); conv.set_physics_process(false)
	conv.omega = SpinFrame.omega_for(); conv.fallback_a_axial = 4.0
	var up := Vector3.LEFT
	var plate_basis := Basis(up.cross(Vector3(0, 0, 1)).normalized(), up, Vector3(0, 0, 1))
	var center := Vector3(240.0, 0.0, 0.0)
	var plate = conv.create_plate(Transform(plate_basis, center), Vector3(40.0, 0.4, 40.0), "CarryPlate")
	var pilot = PilotScene.instance()
	auto_free(pilot)
	add_child(pilot)
	pilot.set_physics_process(false); pilot.set_process(false)
	pilot.set_spin_real_enabled(true)
	pilot.global_transform = Transform(plate_basis, center + up * 2.0 + Vector3(0, 0, 8.0))
	pilot.velocity = Vector3.ZERO
	pilot.set_sim_up(up)
	var input := InputDataV2.new()
	for _i in range(90):
		pilot.step(DT, input)
		yield(get_tree(), "physics_frame")
	assert_bool(pilot.is_on_floor()).is_true()
	assert_bool(pilot._platform_collider == plate).is_true()
	var initial_local: Vector3 = plate.global_transform.affine_inverse().xform(pilot.global_transform.origin)
	conv.start_conversion()
	var min_local_up := 1e9
	var max_step := 0.0
	var prev_pos: Vector3 = pilot.global_transform.origin
	while conv.is_active():
		conv.advance(DT)
		pilot.step(DT, input)
		yield(get_tree(), "physics_frame")
		var local: Vector3 = plate.global_transform.affine_inverse().xform(pilot.global_transform.origin)
		min_local_up = min(min_local_up, local.y)
		max_step = max(max_step, pilot.global_transform.origin.distance_to(prev_pos))
		prev_pos = pilot.global_transform.origin
	var final_local: Vector3 = plate.global_transform.affine_inverse().xform(pilot.global_transform.origin)
	var expected_world: Vector3 = plate.global_transform.xform(initial_local)
	assert_bool(pilot.is_on_floor()).is_true()
	assert_float(min_local_up).is_greater(0.0)  # nunca atravesó la placa
	assert_float(abs(final_local.y - initial_local.y)).is_less(1.0)
	assert_float(pilot.global_transform.origin.distance_to(expected_world)).is_less(1.0)
	assert_float(max_step).is_less(2.0)  # sin teletransporte
	assert_float(plate_basis.y.normalized().dot(plate.global_transform.basis.y.normalized())).is_less(0.99)  # la placa rotó
