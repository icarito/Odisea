extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# FD-323 Fase 3C — caída libre real desde la escotilla del hub en SpinLab.tscn.
# La simulación avanza con frames de física Box3D reales (240 Hz) y se compara
# contra la recta inercial analítica. También cubre spokes, hub ZERO_G y cuerda.

const LabScene = preload("res://core_v2/levels/spin_lab/SpinLab.tscn")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const GravityModes = preload("res://core_v2/systems/GravityModes.gd")
const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const InputDataV2 = preload("res://core_v2/input/InputDataV2.gd")
const EPS := 0.0001

var _previous_physics_fps := 60
var _session_physics := true

class PhysicsDriver extends Node:
	const InputData = preload("res://core_v2/input/InputDataV2.gd")
	var pilot = null
	var enabled := true
	var first := true
	var steps := 0
	var start_position := Vector3.ZERO
	var start_velocity := Vector3.ZERO
	func _physics_process(delta: float) -> void:
		if enabled and is_instance_valid(pilot):
			if pilot.is_physics_processing():
				pilot.set_physics_process(false)
			if first:
				pilot.global_transform.origin = start_position
				pilot.velocity = start_velocity
				first = false
			steps += 1
			pilot.step(1.0 / float(Engine.iterations_per_second), InputData.new())

func before() -> void:
	var anna = get_node_or_null("/root/ANNAV2")
	if anna and anna.has_method("set_replay_mode"):
		anna.set_replay_mode(true)
	_previous_physics_fps = Engine.iterations_per_second
	Engine.iterations_per_second = 1000
	var session = get_node_or_null("/root/SessionManager")
	if session != null:
		_session_physics = session.is_physics_processing()
		session.set_physics_process(false)

func after() -> void:
	Engine.iterations_per_second = _previous_physics_fps
	var session = get_node_or_null("/root/SessionManager")
	if session != null and _session_physics:
		session.set_physics_process(true)

func _instantiate_lab(disable_pilot_physics: bool = true):
	var lab = auto_free(LabScene.instance())
	add_child(lab)
	lab.set_physics_process(false)
	if disable_pilot_physics:
		lab.get_node("Pilot").set_physics_process(false)
	return lab

func _pilot_radius(pilot) -> float:
	var collision = pilot.get_node_or_null("CollisionShape")
	if collision != null and collision.shape is CapsuleShape:
		return (collision.shape as CapsuleShape).radius
	return 0.5

func test_hub_drop_matches_inertial_line_and_triggers_suit_landing() -> void:
	var lab = _instantiate_lab(false)
	var pilot = lab.get_node("Pilot")
	pilot.set_physics_process(false)
	pilot.input_locked = false
	pilot.is_replay_mode = false
	pilot.remove_from_group("player")
	var session = get_node_or_null("/root/SessionManager")
	if session != null:
		session.player = null
		session.is_recording = false
		session.is_replaying = false
		session._should_snapshot = false
	var driver = auto_free(PhysicsDriver.new())
	driver.process_priority = -100
	add_child(driver)
	driver.pilot = pilot
	var r0 := 10.0
	var v0 := 100.0
	lab.spawn_at_hub_drop(1, r0, v0)
	driver.start_position = pilot.global_transform.origin
	driver.start_velocity = pilot.velocity

	var p0: Vector3 = pilot.global_transform.origin
	var v_start: Vector3 = pilot.velocity
	var omega: float = lab.spin_omega
	var r_local: float = lab.r_local_for_position(p0)
	var r_target: float = r_local - 1.0 + _pilot_radius(pilot)
	var v_inertial: Vector3 = v_start + Vector3(0.0, 0.0, omega).cross(p0)
	var a: float = v_inertial.x * v_inertial.x + v_inertial.y * v_inertial.y
	var b: float = 2.0 * (p0.x * v_inertial.x + p0.y * v_inertial.y)
	var c: float = p0.x * p0.x + p0.y * p0.y - r_target * r_target
	var disc: float = b * b - 4.0 * a * c
	assert_float(disc).is_greater(0.0)
	var t_impact: float = (-b + sqrt(disc)) / (2.0 * a)

	var fps: float = float(Engine.iterations_per_second)
	var landed := false
	var landing_position := p0
	var landing_elapsed := 0.0
	for i in range(1, int(ceil(t_impact * fps)) + 120):
		yield (get_tree(), "physics_frame")
		var elapsed: float = float(i - 1) / fps
		var physics = pilot.get_spin_physics()
		var is_landing: bool = pilot.is_ragdoll or bool(physics._slide_active)
		if is_landing:
			landed = true
			landing_position = pilot.global_transform.origin
			landing_elapsed = elapsed
			break
		# En vuelo libre Box3D la trayectoria debe seguir la recta inercial.
		var expected: Vector3 = SpinFrame.from_inertial_position(
			p0 + v_inertial * elapsed, omega, elapsed
		)
		assert_float(pilot.global_transform.origin.distance_to(expected)).is_less(0.5)

	assert_bool(landed).is_true()
	var impact_expected: Vector3 = SpinFrame.from_inertial_position(
		p0 + v_inertial * landing_elapsed, omega, landing_elapsed
	)
	assert_float(landing_position.distance_to(impact_expected)).is_less(0.5)
	assert_float(abs(SpinFrame.r_perp(landing_position).length() - r_local)).is_less(5.0)
	if pilot.is_ragdoll:
		for _i in range(140):
			pilot.step(1.0 / 60.0, null)
		assert_bool(pilot.is_ragdoll).is_false()

func test_spokes_hub_zero_g_and_rope_from_registry_anchors() -> void:
	var lab = _instantiate_lab()
	var config: Dictionary = lab.get_spiral_config()
	var plate0: Transform = SpiralGeometry.plate_transform(config, 0)
	var plate2: Transform = SpiralGeometry.plate_transform(config, 2)
	var plate_indices := [0, 2]

	assert_int(lab.spokes.size()).is_equal(2)
	for i in range(lab.spokes.size()):
		var spoke = lab.spokes[i]
		var plate: Transform = SpiralGeometry.plate_transform(config, plate_indices[i])
		assert_bool(spoke.is_configured()).is_true()
		assert_float(spoke.get_plate_origin().distance_to(plate.origin)).is_less(EPS)
		assert_float(spoke.get_hub_origin().z).is_equal_approx(plate.origin.z, EPS)
		assert_object(spoke.get_ladder()).is_not_null()
		assert_bool(spoke.get_ladder().is_in_group("ladder")).is_true()

	assert_object(lab.hub).is_not_null()
	assert_int(lab.hub.get_gravity_mode()).is_equal(GravityModes.Mode.ZERO_G)
	var axis_point := Vector3(0.0, 0.0, plate0.origin.z)
	assert_bool(lab.hub.contains_global_point(axis_point)).is_true()
	var world = get_node_or_null("/root/GravityWorld")
	assert_object(world).is_not_null()
	assert_int(world.get_gravity_mode_at(axis_point)).is_equal(GravityModes.Mode.ZERO_G)
	assert_float(plate2.origin.z).is_greater(plate0.origin.z)

	# Cuerda con anclajes de DomeRegistry: agarre, tensión y suelta con momento.
	assert_int(lab._rope_anchors.size()).is_greater(0)
	lab.spawn_at_plate(0)
	var pilot = lab.get_node("Pilot")
	var origin: Vector3 = pilot.global_transform.origin
	var anchor_transform: Transform = lab._rope_anchors[0]
	var target: Vector3 = anchor_transform.origin
	assert_bool(lab.try_attach_rope(target - origin)).is_true()
	assert_bool(lab.rope.is_attached()).is_true()

	var anchor: Vector3 = lab.rope.get_anchor()
	var rope_length: float = lab.rope.get_rope_length()
	var direction: Vector3 = (origin - anchor).normalized()
	var tangential: Vector3 = direction.cross(Vector3.UP).normalized() * 3.0
	pilot.global_transform.origin = anchor + direction * (rope_length + 2.0)
	pilot.velocity = direction * 5.0 + tangential
	lab._apply_rope_constraint()
	var expected_position: Vector3 = anchor + direction * rope_length
	assert_float(pilot.global_transform.origin.distance_to(expected_position)).is_less(EPS)
	assert_float(abs(pilot.velocity.dot(direction))).is_less(EPS)
	assert_float(pilot.velocity.distance_to(tangential)).is_less(EPS)

	var velocity_before_release: Vector3 = pilot.velocity
	lab.detach_rope()
	assert_bool(lab.rope.is_attached()).is_false()
	assert_float(pilot.velocity.distance_to(velocity_before_release)).is_less(0.000001)
