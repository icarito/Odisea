extends GdUnitTestSuite

# FD-323 Fase 3A — cuerda, spokes y hub axial.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const GravityModes = preload("res://core_v2/systems/GravityModes.gd")
const RopeScript = preload("res://core_v2/player/traversal/SpinRopeSwingV2.gd")
const RopeInputScript = preload("res://core_v2/player/traversal/SpinRopeInputV2.gd")
const SpokeScript = preload("res://core_v2/components/SpinSpokeV2.gd")
const HubScript = preload("res://core_v2/components/SpinAxialHubV2.gd")
const DomeField = preload("res://core_v2/components/DomeSpiralField.gd")
const DomeResource = preload("res://core_v2/components/DomeSpiralFieldResource.gd")

const EPS := 1e-4

func _plate_xform() -> Transform:
	return DomeField.plate_transform(DomeResource.default_spiral_config(), 42)

func test_anchor_selection_uses_aim_and_deterministic_tie_break() -> void:
	var aim := Vector3(0.0, 0.0, -1.0)
	var anchors: Array = [
		Vector3(0.0, 0.0, -30.0),
		Vector3(0.0, 0.0, -5.0),
		Transform(Basis(), Vector3(0.0, 0.0, -10.0)),
		Vector3(0.0, 0.0, 10.0)
	]
	var best: Dictionary = RopeScript.select_best_anchor(Vector3.ZERO, aim, anchors)
	assert_bool(best["hit"]).is_true()
	assert_int(int(best["anchor_index"])).is_equal(1)
	var best_pos: Vector3 = best["anchor_position"]
	assert_float(best_pos.distance_to(Vector3(0.0, 0.0, -5.0))).is_less(EPS)

	var tied: Array = [Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, -10.0)]
	var tied_best: Dictionary = RopeScript.select_best_anchor(Vector3.ZERO, aim, tied)
	assert_int(int(tied_best["anchor_index"])).is_equal(0)

	var mixed: Array = [
		Transform(Basis(), Vector3(0.0, 0.0, -10.0)),
		Vector3(0.0, 0.0, -10.0)
	]
	var mixed_best: Dictionary = RopeScript.select_best_anchor(Vector3.ZERO, aim, mixed)
	assert_int(int(mixed_best["anchor_index"])).is_equal(0)

	var out_of_range: Dictionary = RopeScript.select_best_anchor(
		Vector3.ZERO, aim, [Vector3(0.0, 0.0, -100.0)]
	)
	assert_bool(out_of_range["hit"]).is_false()

func test_rope_constraint_removes_only_outward_energy() -> void:
	var constrained: Dictionary = RopeScript.constrain_swing(
		Vector3(10.0, 0.0, 0.0), Vector3(3.0, 2.0, 0.0), Vector3.ZERO, 5.0
	)
	assert_bool(constrained["taut"]).is_true()
	var position: Vector3 = constrained["position"]
	var velocity: Vector3 = constrained["velocity"]
	assert_float(position.distance_to(Vector3(5.0, 0.0, 0.0))).is_less(EPS)
	assert_vector3(velocity).is_equal_approx(Vector3(0.0, 2.0, 0.0), Vector3(EPS, EPS, EPS))
	assert_float(velocity.length()).is_less_equal(sqrt(13.0) + EPS)
	var tension: Vector3 = constrained["tension_dir"]
	assert_float(tension.dot(Vector3(-1.0, 0.0, 0.0))).is_equal_approx(1.0, EPS)

	var slack: Dictionary = RopeScript.constrain_swing(
		Vector3(3.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0), Vector3.ZERO, 5.0
	)
	assert_bool(slack["taut"]).is_false()
	assert_vector3(slack["position"]).is_equal(Vector3(3.0, 0.0, 0.0))
	assert_vector3(slack["velocity"]).is_equal(Vector3(3.0, 0.0, 0.0))

	var inward: Dictionary = RopeScript.constrain_swing(
		Vector3(10.0, 0.0, 0.0), Vector3(-3.0, 0.0, 0.0), Vector3.ZERO, 5.0
	)
	assert_bool(inward["taut"]).is_true()
	assert_vector3(inward["velocity"]).is_equal(Vector3(-3.0, 0.0, 0.0))

func test_rope_attach_detach_and_visual_state() -> void:
	var rope = auto_free(RopeScript.new())
	add_child(rope)
	assert_bool(rope.is_attached()).is_false()

	var rope_length: float = rope.attach(Vector3.ZERO, Vector3(10.0, 0.0, 0.0))
	assert_float(rope_length).is_equal_approx(10.0, EPS)
	assert_bool(rope.is_attached()).is_true()
	var visual: MeshInstance = rope.get_node("RopeVisual") as MeshInstance
	assert_object(visual).is_not_null()
	assert_bool(visual.visible).is_true()

	rope.detach()
	assert_bool(rope.is_attached()).is_false()
	assert_bool(visual.visible).is_false()
	assert_float(rope.get_rope_length()).is_equal_approx(0.0, EPS)

	rope.attach(Vector3.ZERO, Vector3(0.1, 0.0, 0.0))
	assert_float(rope.get_rope_length()).is_equal_approx(rope.min_len, EPS)
	rope.attach(Vector3.ZERO, Vector3(200.0, 0.0, 0.0))
	assert_float(rope.get_rope_length()).is_equal_approx(rope.max_len, EPS)

func test_spoke_derives_from_plate_with_ladder_and_radial_physics() -> void:
	var plate: Transform = _plate_xform()
	var spoke = auto_free(SpokeScript.new())
	spoke.configure_from_plate(plate, 8.0)
	add_child(spoke)

	var plate_origin: Vector3 = spoke.get_plate_origin()
	var hub_origin: Vector3 = spoke.get_hub_origin()
	var radial: Vector3 = SpinFrame.r_perp(plate_origin)
	var radial_dir: Vector3 = radial.normalized()
	assert_float(spoke.get_radial_length()).is_equal_approx(radial.length() - 8.0, EPS)
	assert_float(SpinFrame.r_perp(hub_origin).length()).is_equal_approx(8.0, EPS)
	assert_float(hub_origin.z).is_equal_approx(plate_origin.z, EPS)
	assert_float(SpinFrame.r_perp(hub_origin).normalized().dot(radial_dir)) \
		.is_equal_approx(1.0, EPS)

	var ladder: StaticBody = spoke.get_ladder()
	assert_object(ladder).is_not_null()
	assert_bool(ladder.is_in_group("ladder")).is_true()
	assert_int(ladder.collision_layer & (1 << 2)).is_equal(1 << 2)
	assert_float(ladder.climb_half_height).is_equal_approx(
		spoke.get_radial_length() * 0.5, EPS
	)
	assert_float(ladder.global_transform.basis.y.dot(-radial_dir)).is_equal_approx(1.0, EPS)

	var omega: float = SpinFrame.omega_for()
	var g_surface: float = SpokeScript.radial_gravity_at(plate_origin, omega)
	var g_hub: float = SpokeScript.radial_gravity_at(hub_origin, omega)
	var g_mid: float = SpokeScript.radial_gravity_at((plate_origin + hub_origin) * 0.5, omega)
	assert_float(g_surface).is_equal_approx(omega * omega * radial.length(), EPS)
	assert_float(g_hub).is_equal_approx(omega * omega * 8.0, EPS)
	assert_float(g_mid).is_less(g_surface)
	assert_float(g_mid).is_greater(g_hub)

	var coriolis: Vector3 = SpokeScript.lateral_coriolis_accel(2.0, -radial_dir, omega)
	assert_float(coriolis.length()).is_equal_approx(2.0 * omega * 2.0, 0.01)
	assert_float(coriolis.dot(-radial_dir)).is_equal_approx(0.0, EPS)
	assert_float(coriolis.z).is_equal_approx(0.0, EPS)

func test_axial_hub_zero_g_and_hatch_launch() -> void:
	var hub = auto_free(HubScript.new())
	add_child(hub)
	assert_bool(hub.is_in_group("zero_gravity_zones")).is_true()
	assert_int(hub.get_gravity_mode()).is_equal(GravityModes.Mode.ZERO_G)
	assert_int(hub.get_gravity_priority()).is_greater(0)
	assert_float(hub.get_volume()).is_equal_approx(
		PI * hub.hub_radius * hub.hub_radius * (hub.z_max - hub.z_min), 1.0
	)

	assert_bool(hub.contains_global_point(Vector3(4.0, 0.0, 0.0))).is_true()
	assert_bool(hub.contains_global_point(Vector3(0.0, 0.0, hub.z_max))).is_true()
	assert_bool(hub.contains_global_point(Vector3(9.0, 0.0, 0.0))).is_false()
	assert_bool(hub.contains_global_point(Vector3(0.0, 0.0, hub.z_max + 1.0))).is_false()
	assert_bool(hub.contains_global_point(Vector3(0.0, 0.0, hub.z_min - 1.0))).is_false()

	var omega: float = SpinFrame.omega_for()
	assert_vector3(SpinFrame.a_coriolis(Vector3(0.0, 0.0, 12.0), omega)).is_equal(Vector3.ZERO)

	var hatch := Vector3(4.0, 0.0, 10.0)
	var launch: Dictionary = hub.compute_hatch_launch(hatch, Vector3(1.0, 0.0, 5.0), 12.0)
	var launch_pos: Vector3 = launch["position"]
	var launch_vel: Vector3 = launch["velocity"]
	assert_float(launch_pos.distance_to(hatch)).is_less(EPS)
	assert_vector3(launch_vel).is_equal_approx(Vector3(12.0, 0.0, 0.0), Vector3(EPS, EPS, EPS))

	var fallback: Dictionary = hub.compute_hatch_launch(hatch, Vector3.ZERO, -12.0)
	var fallback_vel: Vector3 = fallback["velocity"]
	assert_vector3(fallback_vel).is_equal_approx(Vector3(12.0, 0.0, 0.0), Vector3(EPS, EPS, EPS))

	var inward_dir: Dictionary = hub.compute_hatch_launch(hatch, Vector3(-1.0, 0.0, 0.0), 12.0)
	var inward_vel: Vector3 = inward_dir["velocity"]
	assert_vector3(inward_vel).is_equal_approx(Vector3(12.0, 0.0, 0.0), Vector3(EPS, EPS, EPS))

class DummyPilot extends KinematicBody:
	var velocity := Vector3.ZERO
	func get_sim_up() -> Vector3: return Vector3.UP
	func get_spin_physics(): return null

func test_reel_in_shortens_rope_and_preserves_catapult_velocity_on_release() -> void:
	var anchor := Vector3(0.0, 0.0, 20.0)
	var state: Dictionary = RopeScript.reel_in(
		Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, 4.0), anchor, 20.0, 0.5)
	assert_float(float(state["length"])).is_less(20.0)
	assert_float((state["velocity"] as Vector3).dot(Vector3(0.0, 0.0, 1.0))).is_greater(4.0)
	assert_float((state["position"] as Vector3).distance_to(anchor)) \
		.is_equal_approx(float(state["length"]), 1e-4)
	var rope_input = auto_free(RopeInputScript.new())
	add_child(rope_input)
	var pilot = auto_free(DummyPilot.new())
	add_child(pilot)
	pilot.global_transform.origin = Vector3(0.0, 0.0, 18.0)
	var attached: Dictionary = rope_input.step(pilot, [anchor], Vector3(0.0, 0.0, 1.0), true, 0.1)
	assert_bool(bool(attached["attached"])).is_true()
	var reeled: Dictionary = rope_input.step(pilot, [anchor], Vector3(0.0, 0.0, 1.0), true, 0.1, true)
	assert_bool(bool(reeled["reeling"])).is_true()
	var catapult: Vector3 = pilot.velocity
	var released: Dictionary = rope_input.step(pilot, [anchor], Vector3(0.0, 0.0, 1.0), false, 0.1)
	assert_bool(bool(released["released"])).is_true()
	assert_float(pilot.velocity.distance_to(catapult)).is_less(1e-6)
