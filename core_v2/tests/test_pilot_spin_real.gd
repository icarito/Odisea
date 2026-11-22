extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# FD-323 Fase 2A — física SPIN_REAL + aterrizaje del traje.
# Cubre: activación opt-in, up por SpinFrame (fallback de eje), alineación de
# cápsula con tasa máxima, centrífugo+Coriolis en suelo, vuelo libre exacto
# (Jacobi), hooks de aceleración externa y Δv, clasificación/respuesta de
# aterrizaje, tumble con recuperación sin muerte y snapshots sin `_up`.

const SpinRealPhysicsV2 = preload("res://core_v2/player/SpinRealPhysicsV2.gd")
const PlayerControllerV2 = preload("res://core_v2/player/PlayerControllerV2.gd")
const ControllerManagerScript = preload("res://core_v2/player/ControllerManager.gd")
const GravityModes = preload("res://core_v2/systems/GravityModes.gd")
const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")
const PilotScene = preload("res://core_v2/actors/Pilot_v2.tscn")
const DT := 1.0 / 60.0

var _previous_gravity_mode := -1

class DummyController extends KinematicBody:
	var is_ragdoll := false
	var began := false
	var ended := false
	func begin_ragdoll() -> void:
		is_ragdoll = true
		began = true
	func end_ragdoll() -> void:
		is_ragdoll = false
		ended = true

func before() -> void:
	var anna = get_node_or_null("/root/ANNAV2")
	if anna and anna.has_method("set_replay_mode"):
		anna.set_replay_mode(true)
	var gravity_world = get_node_or_null("/root/GravityWorld")
	if gravity_world != null:
		_previous_gravity_mode = int(gravity_world.get_current_gravity_mode())

func after() -> void:
	var gravity_world = get_node_or_null("/root/GravityWorld")
	if gravity_world != null and _previous_gravity_mode >= 0:
		gravity_world.set_gravity_mode(_previous_gravity_mode)

func _make_spin() -> Node:
	return auto_free(SpinRealPhysicsV2.new())

func test_mode_value_and_export_defaults() -> void:
	assert_int(GravityModes.Mode.SPIN_REAL).is_equal(4)
	var spin = _make_spin()
	assert_float(spin.spin_omega).is_equal_approx(SpinFrame.omega_for(), 0.0001)
	assert_float(spin.coriolis_ground_factor).is_equal_approx(0.3, 0.0001)
	assert_float(spin.spin_capsule_align_rate_rad_s).is_equal_approx(6.0, 0.0001)
	assert_float(spin.spin_v_safe).is_equal_approx(12.0, 0.0001)
	assert_float(spin.spin_v_slide).is_equal_approx(26.0, 0.0001)
	assert_float(spin.spin_tumble_recovery_sec).is_equal_approx(1.8, 0.0001)
	assert_float(spin.spin_slide_decel).is_equal_approx(14.0, 0.0001)
	assert_float(spin.spin_thruster_dv_max).is_equal_approx(18.0, 0.0001)
	assert_float(spin.spin_thruster_dv_remaining).is_equal_approx(18.0, 0.0001)

func test_activation_override_and_gravity_world() -> void:
	var controller = auto_free(PlayerControllerV2.new())
	controller.set_spin_real_enabled(true)
	assert_bool(controller.is_spin_real_enabled()).is_true()
	assert_bool(controller.is_spin_real_active()).is_true()
	controller.set_spin_real_enabled(false)
	assert_bool(controller.is_spin_real_enabled()).is_false()

	var gravity_world = get_node_or_null("/root/GravityWorld")
	assert_object(gravity_world).is_not_null()
	gravity_world.set_gravity_mode(GravityModes.Mode.SPIN_REAL)
	assert_int(gravity_world.get_gravity_mode_at(Vector3(10.0, 0.0, 0.0))).is_equal(GravityModes.Mode.SPIN_REAL)
	# Modos 0..3 intactos: sólo cambia el valor opt-in 4.
	assert_int(gravity_world.get_gravity_mode_at(Vector3(10.0, 0.0, 0.0)) - 1).is_equal(3)

func test_controller_manager_maps_spin_real_to_pilot() -> void:
	var manager = auto_free(ControllerManagerScript.new())
	assert_int(manager.get_controller_mode_for_gravity_mode(GravityModes.Mode.SPIN_REAL)) \
		.is_equal(ControllerManagerScript.Mode.STANDARD_1G)
	assert_int(manager.get_controller_mode_for_gravity_mode(GravityModes.Mode.ZERO_G)) \
		.is_equal(ControllerManagerScript.Mode.ZERO_GRAVITY)
	assert_int(manager.get_controller_mode_for_gravity_mode(GravityModes.Mode.STANDARD_1G)) \
		.is_equal(ControllerManagerScript.Mode.STANDARD_1G)

func test_up_follows_radial_and_keeps_fallback_near_axis() -> void:
	var spin = _make_spin()
	assert_float(spin.update_up(Vector3(10.0, 0.0, 0.0)).distance_to(Vector3.LEFT)).is_less(0.0001)
	assert_float(spin.update_up(Vector3(3.0, 4.0, 0.0)).distance_to(Vector3(-0.6, -0.8, 0.0))).is_less(0.0001)
	# Cerca del eje se conserva el último up (no hay dirección radial definida).
	assert_float(spin.update_up(Vector3(0.0, 0.0, 25.0)).distance_to(Vector3(-0.6, -0.8, 0.0))).is_less(0.0001)

func test_capsule_alignment_is_rate_limited_and_handles_antiparallel() -> void:
	var spin = _make_spin()
	var aligned = spin.align_capsule_basis(Basis.IDENTITY, Vector3.RIGHT, DT)
	var angle = acos(clamp(aligned.y.normalized().dot(Vector3.RIGHT), -1.0, 1.0))
	assert_float(angle).is_equal_approx(PI * 0.5 - 0.1, 0.002)

	var anti = spin.align_capsule_basis(Basis.IDENTITY, Vector3.DOWN, DT)
	var anti_angle = acos(clamp(anti.y.normalized().dot(Vector3.DOWN), -1.0, 1.0))
	assert_float(anti_angle).is_equal_approx(PI - 0.1, 0.002)

func test_ground_acceleration_uses_centrifugal_and_reduced_coriolis() -> void:
	var spin = _make_spin()
	var position := Vector3(10.0, 0.0, 0.0)
	var velocity := Vector3(0.0, 1.0, 0.0)
	var expected: Vector3 = SpinFrame.a_centrif(position, spin.spin_omega) \
		+ SpinFrame.a_coriolis(velocity, spin.spin_omega) * spin.coriolis_ground_factor
	var accel: Vector3 = spin.ground_acceleration(position, velocity)
	assert_float(accel.distance_to(expected)).is_less(0.000001)
	# El centrífugo apunta hacia afuera (+radial), o sea contra "up" (hacia el piso).
	assert_float(accel.dot(spin.update_up(position))).is_less(0.0)

func test_free_flight_conserves_jacobi_and_coriolis_speed() -> void:
	var spin = _make_spin()
	var conditions := [
		[Vector3(240.0, 0.0, 0.0), Vector3(0.0, 10.0, 0.0)],
		[Vector3(100.0, 50.0, 10.0), Vector3(3.0, -4.0, 2.0)],
		[Vector3(10.0, 0.0, 0.0), Vector3(0.0, 0.0, 5.0)]
	]
	for condition in conditions:
		var position: Vector3 = condition[0]
		var velocity: Vector3 = condition[1]
		var jacobi0: float = SpinFrame.jacobi(position, velocity, spin.spin_omega)
		for i in range(1800):
			var state: Dictionary = spin.air_step(position, velocity, DT)
			position = state["position"]
			velocity = state["velocity"]
		var jacobi1: float = SpinFrame.jacobi(position, velocity, spin.spin_omega)
		var relative_error: float = abs(jacobi1 - jacobi0) / max(abs(jacobi0), 0.000001)
		assert_float(relative_error).is_less(0.001)

	var vector := Vector3(1.0, 2.0, 3.0)
	var rotated: Vector3 = SpinFrame.rotate_coriolis(vector, spin.spin_omega, 0.05)
	assert_float(abs(rotated.length() - vector.length())).is_less(0.000001)

func test_external_accel_and_thruster_budget() -> void:
	var spin = _make_spin()
	spin.add_spin_external_accel(Vector3(1.0, 0.0, 0.0))
	spin.add_spin_external_accel(Vector3(0.0, 2.0, 0.0))
	assert_float(spin._external_accel.distance_to(Vector3(1.0, 2.0, 0.0))).is_less(0.000001)

	var dv1: float = spin.apply_spin_thruster(Vector3.RIGHT, 0.1)
	assert_float(dv1).is_equal_approx(1.8, 0.0001)
	assert_float(spin.spin_thruster_dv_remaining).is_equal_approx(16.2, 0.0001)
	assert_float(spin._thruster_delta_v.distance_to(Vector3.RIGHT * 1.8)).is_less(0.0001)

	var dv2: float = spin.apply_spin_thruster(Vector3.RIGHT, 10.0)
	assert_float(dv2).is_equal_approx(16.2, 0.0001)
	assert_float(spin.spin_thruster_dv_remaining).is_equal_approx(0.0, 0.0001)
	assert_float(spin.apply_spin_thruster(Vector3.RIGHT, 0.1)).is_equal_approx(0.0, 0.0001)
	spin.recharge_thrusters()
	assert_float(spin.spin_thruster_dv_remaining).is_equal_approx(18.0, 0.0001)

func test_landing_classification_and_slide_response() -> void:
	var spin = _make_spin()
	assert_int(spin.classify_landing(5.0)).is_equal(SpinRealPhysicsV2.Landing.NORMAL)
	assert_int(spin.classify_landing(spin.spin_v_safe)).is_equal(SpinRealPhysicsV2.Landing.SLIDE)
	assert_int(spin.classify_landing(spin.spin_v_slide - 0.1)).is_equal(SpinRealPhysicsV2.Landing.SLIDE)
	assert_int(spin.classify_landing(spin.spin_v_slide)).is_equal(SpinRealPhysicsV2.Landing.TUMBLE)

	var slid: Vector3 = spin.slide_velocity(Vector3(10.0, -5.0, 0.0), Vector3.UP, 0.5)
	assert_float(slid.distance_to(Vector3(3.0, 0.0, 0.0))).is_less(0.0001)

	var dummy = auto_free(DummyController.new())
	assert_int(spin.handle_landing(dummy, 5.0)).is_equal(SpinRealPhysicsV2.Landing.NORMAL)
	assert_bool(dummy.began).is_false()

func test_tumble_enters_ragdoll_and_recovers_without_death() -> void:
	var spin = _make_spin()
	var dummy = auto_free(DummyController.new())
	assert_int(spin.handle_landing(dummy, spin.spin_v_slide + 4.0)).is_equal(SpinRealPhysicsV2.Landing.TUMBLE)
	assert_bool(dummy.is_ragdoll).is_true()
	assert_bool(dummy.began).is_true()
	assert_bool(spin.is_tumbling()).is_true()

	assert_bool(spin.tick_tumble_recovery(0.9, dummy)).is_false()
	assert_bool(dummy.is_ragdoll).is_true()
	assert_bool(spin.tick_tumble_recovery(0.9, dummy)).is_true()
	assert_bool(dummy.is_ragdoll).is_false()
	assert_bool(dummy.ended).is_true()
	assert_bool(spin.is_tumbling()).is_false()

func test_pilot_spin_real_up_capsule_and_snapshot() -> void:
	var gravity_world = get_node_or_null("/root/GravityWorld")
	gravity_world.set_gravity_mode(GravityModes.Mode.SPIN_REAL)
	var pilot = PilotScene.instance()
	auto_free(pilot)
	add_child(pilot)
	pilot.set_physics_process(false)
	pilot.set_process(false)
	assert_bool(pilot.is_spin_real_active()).is_true()

	var transform: Transform = pilot.global_transform
	transform.origin = Vector3(10.0, 0.0, 0.0)
	pilot.global_transform = transform
	pilot._up = Vector3.UP
	var snapshot: Dictionary = pilot.get_full_snapshot()
	assert_bool(snapshot.has("gravity_mode")).is_true()
	assert_bool(snapshot.has("_up")).is_false()

	pilot.step(DT, InputDataV2.new())
	assert_float(pilot.get_sim_up().dot(Vector3.LEFT)).is_greater(0.99)
	assert_float(pilot.global_transform.basis.y.normalized().dot(pilot.get_sim_up())).is_greater(0.05)

	pilot._up = Vector3.UP
	pilot.restore_snapshot(snapshot)
	assert_float(pilot.get_sim_up().dot(Vector3.LEFT)).is_greater(0.99)
