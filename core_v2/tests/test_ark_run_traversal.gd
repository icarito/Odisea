extends GdUnitTestSuite
# FD-324 F2: ascensor radial, respaldo SPIN_REAL, cuerda RT/teclado, domos y ruta.
const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const ElevatorScript = preload("res://core_v2/components/SpinRadialElevatorV2.gd")
const SpokeScript = preload("res://core_v2/components/SpinSpokeV2.gd")
const RopeInputScript = preload("res://core_v2/player/traversal/SpinRopeInputV2.gd")
const TerracePropsScript = preload("res://core_v2/levels/ark_run/ArkRunTerraceProps.gd")
const RouteScript = preload("res://core_v2/levels/ark_run/ArkRunCanonicalRoute.gd")
const AutoScript = preload("res://core_v2/input/AutopilotInputV2.gd")
const LiveLoopScript = preload("res://core_v2/levels/ark_run/ArkRunLiveLoop.gd")
const SPIRAL := {"turns": 2.0, "total_height": 2000.0, "plate_step": 40.0, "r_min": 220.0, "r_max": 260.0, "phase": 0.0}
const OUTER := 240.0
const INNER := 8.0
const SPEED := 6.0
const DWELL := 3.0
const EPS := 1e-6

class StubPilot:
	extends KinematicBody
	var velocity := Vector3()
	var spin_real := true
	var _up := Vector3.UP
	func is_spin_real_active() -> bool: return spin_real
	func set_sim_up(up_vec: Vector3) -> void: _up = up_vec
	func get_sim_up() -> Vector3: return _up

func _sample(t_sim: float) -> Dictionary:
	return ElevatorScript.sample_radial_pos(t_sim, OUTER, INNER, SPEED, DWELL)

func _expect(t_sim: float, expected_r: float, expected_v: float, phase: String, tol: float = 1e-6) -> void:
	var sample := _sample(t_sim)
	assert_float(float(sample["r"])).is_equal_approx(expected_r, tol)
	assert_float(float(sample["velocity_r"])).is_equal_approx(expected_v, 1e-6)
	assert_str(String(sample["phase"])).is_equal(phase)
func _count_nodes(root: Node) -> int:
	var total := 1
	for child in root.get_children():
		total += _count_nodes(child)
	return total

func test_radial_elevator_cycle_is_pure_speed_and_dwell() -> void:
	var travel: float = (OUTER - INNER) / SPEED
	var cycle: float = 2.0 * DWELL + 2.0 * travel
	var inner_start: float = DWELL + travel
	_expect(0.0, OUTER, 0.0, "outer_dwell", 1e-9)
	_expect(DWELL - 0.001, OUTER, 0.0, "outer_dwell")
	_expect(DWELL + 0.001, OUTER - 0.006, -SPEED, "inbound", 1e-5)
	_expect(DWELL + travel * 0.5, (OUTER + INNER) * 0.5, -SPEED, "inbound", 1e-5)
	_expect(inner_start + 1.5, INNER, 0.0, "inner_dwell", 1e-9)
	_expect(inner_start + DWELL - 0.001, INNER, 0.0, "inner_dwell")
	_expect(inner_start + DWELL + 0.001, INNER + 0.006, SPEED, "outbound", 1e-5)
	_expect(inner_start + DWELL + travel * 0.5, (OUTER + INNER) * 0.5, SPEED, "outbound", 1e-5)
	_expect(cycle, OUTER, 0.0, "outer_dwell", 1e-5)
	assert_float(float(ElevatorScript.sample_radial_pos(0.0, OUTER, INNER)["r"])).is_equal(float(_sample(0.0)["r"]))
	var negative := _sample(-0.5)
	var reference := _sample(cycle - 0.5)
	assert_float(float(negative["r"])).is_equal_approx(float(reference["r"]), 1e-9)
	assert_str(String(negative["phase"])).is_equal(String(reference["phase"]))

func test_radial_elevator_step_failure_freezes_and_exposes_g_and_coriolis() -> void:
	var plate: Transform = SpiralGeometry.plate_transform(SPIRAL, 10)
	var elevator = auto_free(ElevatorScript.new())
	add_child(elevator)
	assert_bool(elevator.configure_from_plate(plate, INNER)).is_true()
	var plate_radius: float = SpinFrame.r_perp(plate.origin).length()
	assert_float(elevator.get_outer_radius()).is_equal_approx(plate_radius, 1e-9)
	assert_float(elevator.get_inner_radius()).is_equal_approx(INNER, 1e-9)
	elevator.step_elevator(0.0)
	assert_float(SpinFrame.r_perp(elevator.global_transform.origin).length()).is_equal_approx(plate_radius, 1e-6)
	var travel: float = (plate_radius - INNER) / SPEED
	var mid_state: Dictionary = elevator.step_elevator(DWELL + travel * 0.5)
	assert_float(SpinFrame.r_perp(elevator.global_transform.origin).length()).is_equal_approx((plate_radius + INNER) * 0.5, 1e-4)
	assert_float(float(mid_state["velocity_r"])).is_equal_approx(-SPEED, 1e-6)
	elevator.step_elevator(0.0)
	elevator.set_operational(false)
	var frozen: Vector3 = elevator.global_transform.origin
	elevator.step_elevator(DWELL + travel)
	assert_vector3(elevator.global_transform.origin).is_equal(frozen)
	assert_bool(elevator.is_operational()).is_false()
	var omega: float = SpinFrame.omega_for()
	assert_float(ElevatorScript.radial_gravity(OUTER, omega)).is_equal_approx(omega * omega * OUTER, 1e-9)
	assert_float(ElevatorScript.radial_gravity(INNER, omega)).is_equal_approx(omega * omega * INNER, 1e-9)
	var radial_dir: Vector3 = elevator.get_radial_dir()
	var coriolis: Vector3 = ElevatorScript.lateral_coriolis(-SPEED, radial_dir, omega)
	assert_float(coriolis.length()).is_equal_approx(2.0 * omega * SPEED, 1e-6)
	assert_float(coriolis.dot(radial_dir)).is_equal_approx(0.0, 1e-6)
	assert_float(coriolis.z).is_equal_approx(0.0, 1e-6)

func test_spoke_backup_ladder_works_only_after_failure_in_spin_real() -> void:
	var plate: Transform = SpiralGeometry.plate_transform(SPIRAL, 12)
	var spoke = auto_free(SpokeScript.new())
	add_child(spoke)
	spoke.configure_from_plate(plate, INNER)
	assert_object(spoke.get_elevator()).is_not_null()
	assert_bool(spoke.is_elevator_operational()).is_true()
	var pilot = auto_free(StubPilot.new())
	add_child(pilot)
	var plate_radius: float = SpinFrame.r_perp(plate.origin).length()
	var radial_dir: Vector3 = SpinFrame.r_perp(plate.origin).normalized()
	pilot.global_transform.origin = radial_dir * (plate_radius - 4.0) + Vector3(0.0, 0.0, plate.origin.z)
	assert_bool(spoke.step_backup_ladder(pilot, 1.0, 0.1)["moved"]).is_false()
	spoke.set_elevator_operational(false)
	var before: Vector3 = pilot.global_transform.origin
	assert_bool(spoke.step_backup_ladder(pilot, 1.0, 0.1)["moved"]).is_true()
	assert_float(SpinFrame.r_perp(before).length() - SpinFrame.r_perp(pilot.global_transform.origin).length()).is_equal_approx(0.2, 1e-4)
	var expected_up: Vector3 = SpinFrame.up(before)
	assert_float(pilot.get_sim_up().dot(expected_up)).is_equal_approx(1.0, 1e-6)
	assert_float(pilot.velocity.dot(expected_up)).is_equal_approx(2.0, 1e-6)
	assert_bool(abs(pilot.get_sim_up().dot(Vector3.UP)) < 0.9).is_true()
	spoke.step_backup_ladder(pilot, 1.0, 1000.0)
	assert_float(SpinFrame.r_perp(pilot.global_transform.origin).length()).is_equal_approx(INNER, 1e-6)
	pilot.spin_real = false
	var off_before: Vector3 = pilot.global_transform.origin
	assert_bool(spoke.step_backup_ladder(pilot, -1.0, 0.1)["moved"]).is_false()
	assert_vector3(pilot.global_transform.origin).is_equal(off_before)

func test_rope_input_attaches_and_releases_preserving_momentum() -> void:
	var input = auto_free(RopeInputScript.new())
	add_child(input)
	var pilot = auto_free(StubPilot.new())
	add_child(pilot)
	var aim := Vector3(0.0, 0.0, -1.0)
	assert_bool(input.step(pilot, [Vector3(0.0, 0.0, -8.0)], aim, true, 1.0 / 60.0)["attached"]).is_true()
	assert_bool(input.is_attached()).is_true()
	assert_float(input.get_rope().get_rope_length()).is_equal_approx(8.0, 1e-6)
	assert_bool(input.step(pilot, [Vector3(0.0, 0.0, -8.0)], aim, true, 1.0 / 60.0)["attached"]).is_true()
	assert_float(input.get_rope().get_rope_length()).is_equal_approx(8.0, 1e-6)
	pilot.velocity = Vector3(3.0, 2.0, 0.0)
	assert_bool(input.step(pilot, [], aim, false, 1.0 / 60.0)["released"]).is_true()
	assert_bool(input.is_attached()).is_false()
	assert_vector3(pilot.velocity).is_equal(Vector3(3.0, 2.0, 0.0))
	pilot.global_transform.origin = Vector3.ZERO
	assert_bool(input.step(pilot, [Vector3(5.0, 0.0, 0.0)], Vector3.RIGHT, true, 0.1)["attached"]).is_true()
	assert_float(input.get_rope().get_rope_length()).is_equal_approx(5.0, 1e-6)
	pilot.global_transform.origin = Vector3(12.0, 0.0, 0.0)
	pilot.velocity = Vector3(2.0, 1.0, 0.0)
	assert_bool(input.step(pilot, [], Vector3.RIGHT, true, 0.1)["taut"]).is_true()
	assert_vector3(pilot.global_transform.origin).is_equal_approx(Vector3(10.0, 0.0, 0.0), Vector3(1e-5, 1e-5, 1e-5))
	assert_vector3(pilot.velocity).is_equal_approx(Vector3(0.0, 1.0, 0.0), Vector3(1e-5, 1e-5, 1e-5))
	assert_bool(RopeInputScript.should_trigger(0.8, false, 0.35)).is_true()
	assert_bool(RopeInputScript.should_trigger(0.2, false, 0.35)).is_false()
	assert_bool(RopeInputScript.should_trigger(0.0, true, 0.35)).is_true()

func test_terrace_props_are_variated_and_deterministic() -> void:
	var props_a = auto_free(TerracePropsScript.new())
	add_child(props_a)
	props_a.build_from_config(SPIRAL, 32401)
	var plates: int = SpiralGeometry.plate_count_for(SPIRAL)
	# Se excluyen las placas reservadas de la espiral 0 (0 = Motor, 48 = Puente).
	assert_int(props_a.get_dome_count()).is_equal(int(ceil(float(plates) * 0.5)) - 2)
	assert_int(props_a.get_scaffold_count()).is_greater(plates)
	assert_int(props_a.get_variant_counts().size()).is_greater(1)
	for entry in props_a.get_dome_entries():
		assert_float(SpinFrame.r_perp(entry["transform"].origin).length()).is_between(INNER, 300.0)
	var signature: String = props_a.get_layout_signature()
	var props_b = auto_free(TerracePropsScript.new())
	add_child(props_b)
	props_b.build_from_config(SPIRAL, 32401)
	assert_bool(props_b.get_layout_signature() == signature).is_true()
	var props_c = auto_free(TerracePropsScript.new())
	add_child(props_c)
	props_c.build_from_config(SPIRAL, 32402)
	assert_bool(props_c.get_layout_signature() != signature).is_true()
	var variant: Dictionary = TerracePropsScript.dome_variant(32401, 10, 1)
	assert_bool(str(variant) == str(TerracePropsScript.dome_variant(32401, 10, 1))).is_true()
	assert_bool(str(variant) != str(TerracePropsScript.dome_variant(32402, 10, 1))).is_true()
	print("[ark_run_traversal] terrace_props domes=%d scaffolds=%d nodes=%d verts=%d" % [
		props_a.get_dome_count(), props_a.get_scaffold_count(), _count_nodes(props_a), props_a.get_vertex_count()])

func test_canonical_route_is_bow_to_stern_and_queryable() -> void:
	var route = auto_free(RouteScript.new())
	route.configure(SPIRAL, Vector3(200.0, 2.0, 200.0))
	var waypoints: Array = route.get_waypoints()
	assert_int(waypoints.size()).is_equal(SpiralGeometry.plate_count_for(SPIRAL))
	assert_str(String(waypoints[0]["name"])).is_equal("Puente")
	assert_str(String(waypoints[waypoints.size() - 1]["name"])).is_equal("Motor")
	for index in range(waypoints.size()):
		assert_bool(RouteScript.is_autopilot_waypoint(waypoints[index])).is_true()
		if index > 0:
			assert_float(float(waypoints[index]["position"].z)).is_less(float(waypoints[index - 1]["position"].z))
	assert_bool(float(waypoints[0]["position"].z) >= 880.0).is_true()
	assert_bool(float(waypoints[waypoints.size() - 1]["position"].z) <= -940.0).is_true()
	var hub: Dictionary = route.get_named_waypoint("Núcleo")
	assert_bool(hub.empty()).is_false()
	assert_bool(abs(float(hub["position"].z)) < 40.0 and SpinFrame.r_perp(hub["position"]).length() <= INNER + 0.5).is_true()
	assert_int(route.route_to("Puente").size()).is_equal(1)
	assert_int(route.route_to("Motor").size()).is_equal(waypoints.size())
	var hub_route: Array = route.route_to("Núcleo")
	assert_int(hub_route.size()).is_greater(1)
	assert_int(hub_route.size()).is_less(waypoints.size())
	assert_str(String(hub_route[hub_route.size() - 1]["name"])).is_equal("Núcleo")
	for elevator_name in ["Ascensor_45", "Ascensor_35", "Ascensor_15", "Ascensor_5"]:
		assert_bool(route.has_destination(String(elevator_name))).is_true()
		assert_int(route.route_to(String(elevator_name)).size()).is_greater(1)
	assert_bool(route.has_destination("NoExiste")).is_false()
	assert_int(route.route_to("NoExiste").size()).is_equal(0)
	var autopilot = auto_free(AutoScript.new())
	autopilot.set_route(waypoints)
	assert_bool(autopilot.is_finished()).is_false()
	assert_vector3(autopilot.next_waypoint()).is_equal(waypoints[0]["position"])

func test_footstep_distance_projects_onto_sim_up_plane() -> void:
	var up := Vector3(-1.0, 0.0, 0.0)
	assert_float(FootstepDetector.planar_distance(Vector3(0.0, 1.0, 0.0), up)).is_equal_approx(1.0, 1e-6)
	assert_float(FootstepDetector.planar_distance(Vector3(0.0, 0.0, 2.0), up)).is_equal_approx(2.0, 1e-6)
	assert_float(FootstepDetector.planar_distance(Vector3(3.0, 0.0, 0.0), up)).is_equal_approx(0.0, 1e-6)

func test_domes_do_not_overlap_and_have_baked_collision() -> void:
	var configs: Array = []
	for k in range(6):
		var cfg: Dictionary = SPIRAL.duplicate(true)
		cfg["phase"] = TAU * float(k) / 6.0
		configs.append(cfg)
	var props = auto_free(TerracePropsScript.new())
	add_child(props)
	props.build_from_configs(configs, 32401)
	var entries: Array = props.get_dome_entries()
	assert_int(entries.size()).is_equal(148)
	for i in range(entries.size()):
		var a: Dictionary = entries[i]
		var pa: Vector3 = a["transform"].origin
		var ra: float = float(a["variant"]["radius"])
		for j in range(i + 1, entries.size()):
			var b: Dictionary = entries[j]
			var pb: Vector3 = b["transform"].origin
			var rb: float = float(b["variant"]["radius"])
			assert_float(pa.distance_to(pb)).is_greater_equal(ra + rb - 1e-4)
	var body = props.get_node_or_null("DomeCollision")
	assert_object(body).is_not_null()
	assert_bool(body is StaticBody).is_true()
	assert_int(body.get_child_count()).is_equal(entries.size())

# El objetivo de eyección (Puente, placa 48) y la meta (Motor, placa 0) de la
# espiral 0 deben quedar 100% libres de domos: ninguna entrada los ocupa y ningún
# footprint de domo cubre esos puntos. El vestido (pista/portico/reactor) existe.
func test_bridge_and_engine_plates_are_dome_free() -> void:
	var configs: Array = []
	for k in range(6):
		var cfg: Dictionary = SPIRAL.duplicate(true)
		cfg["phase"] = TAU * float(k) / 6.0
		configs.append(cfg)
	var props = auto_free(TerracePropsScript.new())
	add_child(props)
	props.build_from_configs(configs, 32401)
	var bridge: Vector3 = SpiralGeometry.plate_transform(configs[0], 48).origin
	var engine: Vector3 = SpiralGeometry.plate_transform(configs[0], 0).origin
	for entry in props.get_dome_entries():
		var spiral_index: int = int(entry["spiral_index"])
		var plate_index: int = int(entry["plate_index"])
		if spiral_index == 0:
			assert_bool(plate_index == 48 or plate_index == 0).is_false()
		var origin: Vector3 = entry["transform"].origin
		var radius: float = float(entry["variant"]["radius"])
		assert_float(origin.distance_to(bridge)).is_greater(radius)
		assert_float(origin.distance_to(engine)).is_greater(radius)
	var dressing = props.get_node_or_null("ZoneDressing")
	assert_object(dressing).is_not_null()
	assert_object(dressing.get_node_or_null("BridgePad_Gold")).is_not_null()
	assert_object(dressing.get_node_or_null("BridgePad_Cyan")).is_not_null()
	assert_object(dressing.get_node_or_null("EngineReactor")).is_not_null()

# La cuerda apunta +20 grados sobre la mirada, inclinando hacia +sim_up incluso
# con una base espejada o un "arriba" invertido (piso centrifugo).
func test_rope_aim_is_pitched_twenty_degrees_toward_sim_up() -> void:
	var forward := Vector3(0.0, 0.0, -1.0)
	var aim: Vector3 = LiveLoopScript.elevate_aim_dir(forward, Vector3.RIGHT, Vector3.UP)
	assert_float(aim.length()).is_equal_approx(1.0, 1e-6)
	assert_float(aim.dot(Vector3.UP)).is_greater(0.0)
	assert_float(rad2deg(acos(clamp(aim.dot(forward), -1.0, 1.0)))).is_equal_approx(20.0, 0.01)
	var mirrored: Vector3 = LiveLoopScript.elevate_aim_dir(forward, Vector3.LEFT, Vector3.UP)
	assert_float(mirrored.dot(Vector3.UP)).is_greater(0.0)
	assert_float(rad2deg(acos(clamp(mirrored.dot(forward), -1.0, 1.0)))).is_equal_approx(20.0, 0.01)
	var inverted: Vector3 = LiveLoopScript.elevate_aim_dir(forward, Vector3.RIGHT, Vector3.DOWN)
	assert_float(inverted.dot(Vector3.DOWN)).is_greater(0.0)
	assert_float(rad2deg(acos(clamp(inverted.dot(forward), -1.0, 1.0)))).is_equal_approx(20.0, 0.01)
