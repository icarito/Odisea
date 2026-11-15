extends GdUnitTestSuite

# Extremo a extremo: un tramo armado con las ESCENAS horneadas, recorrido por el piloto real
# con AutopilotInputV2 sobre los waypoints de FlowRouteValidator. Sin herramientas: es la
# ruta principal. Geometria estatica => receta de tests-de-travesia.md.

const PILOT_SCENE = preload("res://core_v2/actors/Pilot_v2.tscn")
const Registry = preload("res://core_v2/systems/scaffold/ScaffoldChunkRegistry.gd")
const AutopilotScript = preload("res://core_v2/input/AutopilotInputV2.gd")
const FlowMetricsScript = preload("res://core_v2/systems/flow/FlowMetrics.gd")
const Validator = preload("res://core_v2/systems/flow/FlowRouteValidator.gd")
const OrbitScript = preload("res://core_v2/systems/scaffold/ScaffoldChunkOrbit.gd")
const VirtualMouseScript = preload("res://core_v2/ui/VirtualMouse.gd")
const DIR := "res://core_v2/props/scaffold/chunks/"
const ORIGIN := Vector3(-6000.0, 6000.0, 6000.0)
const TICKS_PER_FRAME := 8

var _root: Spatial = null


func after_test() -> void:
	for a in ["move_forward", "move_backward", "move_left", "move_right", "jump", "run", "nav_assist"]:
		Input.action_release(a)
	if is_instance_valid(_root):
		_root.queue_free()
	yield(get_tree(), "idle_frame")


func _find_seed(m: Dictionary, count: int) -> int:
	# SCAFFOLD_RUN_SEED=<n> fuerza una semilla (exploracion manual de otras rutas).
	if OS.get_environment("SCAFFOLD_RUN_SEED") != "":
		return int(OS.get_environment("SCAFFOLD_RUN_SEED"))
	# Primera semilla cuyo tramo ejercita hueco, cadencia, rampa y desvios.
	for s in range(1000, 1400):
		var ids: Array = Registry.sequence(s, count)
		var ok := true
		for need in ["scaffold_gap_leap", "scaffold_triple_cadence", "scaffold_gloo_rise", "scaffold_laser_choke", "scaffold_catenary_span"]:
			ok = ok and ids.has(need)
		if ok:
			return s
	return -1


func test_autopilot_runs_a_generated_stretch_of_baked_chunks() -> void:
	yield(_run_stretch(0.0), "completed")


# Mismo tramo proyectado sobre el interior de un cilindro (ScaffoldChunkOrbit): el mundo se
# recoloca bajo el piloto y la ruta sigue en coordenadas planas.
func test_autopilot_runs_the_same_stretch_on_the_cylinder() -> void:
	yield(_run_stretch(190.0), "completed")


func _run_stretch(orbit_radius: float):
	var fm = FlowMetricsScript.from_scene()
	var m := {"g": fm.gravity, "v_run": fm.run_speed(), "v_jump": fm.jump_force, "tick": 1.0 / 60.0}
	var count := 12
	var seed_val: int = _find_seed(m, count)
	assert_int(seed_val).is_greater(0)
	var graph: Dictionary = Registry.generate(seed_val, count, m)
	VirtualMouseScript.set_pointer_released(false)
	_root = Spatial.new()
	_root.translation = ORIGIN
	get_tree().root.add_child(_root)
	var orbit = null
	if OS.get_environment("SCAFFOLD_RUN_RADIUS") != "":
		orbit_radius = float(OS.get_environment("SCAFFOLD_RUN_RADIUS")) if orbit_radius > 0.0 else 0.0
	if orbit_radius > 0.0:
		orbit = OrbitScript.new()
		orbit.base_radius = orbit_radius
		orbit.set_physics_process(false)
		_root.add_child(orbit)
	for p in graph["placements"]:
		var chunk: Spatial = load(str(p["scene"])).instance()
		if orbit != null:
			orbit.add_chunk(chunk, p["origin"])
		else:
			chunk.translation = p["origin"]
			_root.add_child(chunk)
	var pilot: KinematicBody = PILOT_SCENE.instance()
	pilot.translation = Vector3(0.0, 0.05, 1.0)
	_root.add_child(pilot)
	if orbit != null:
		orbit.set_player(pilot)
		orbit.reposition()
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	pilot.set_physics_process(false)
	pilot.input_provider.set_live_mode()
	pilot.input_provider.hardware_input_enabled = true

	var by_id := {}
	for n in graph["nodes"]:
		by_id[n["id"]] = n
	var route := []
	for wp in Validator.extract_main_waypoints(graph, m):
		var node: Dictionary = by_id[wp["id"]].duplicate()
		if orbit == null:
			node["position"] = node["position"] + ORIGIN
		route.append(node)
	assert_int(route.size()).is_greater(count)
	var auto = AutopilotScript.new()
	auto.setup(pilot)
	auto.set_route(route)
	auto.frame = orbit
	auto.enabled = true
	pilot.input_provider.autopilot = auto

	Input.action_press("nav_assist")  # el autonavegador conduce solo con TAB sostenido
	var ticks := 0
	var limit: int = count * 12 * 60  # 12 s por chunk: el piloto corre 12 m en ~2 s
	while ticks < limit and not auto.is_finished():
		pilot._physics_process(0.0)
		if orbit != null:
			orbit.reposition()
		ticks += 1
		if OS.get_environment("CHUNK_RUN_TRACE") != "" and ticks % 10 == 0:
			prints("[trace]", ticks, pilot.global_transform.origin - ORIGIN, pilot.is_on_floor(), auto.next_waypoint(), pilot.input_provider.last_input.jump)
		if ticks % TICKS_PER_FRAME == 0:
			yield(get_tree(), "physics_frame")
		if pilot.global_transform.origin.y < ORIGIN.y - 30.0:
			break
	var local: Vector3 = pilot.global_transform.origin - ORIGIN
	prints("[chunk_run] radius=", orbit_radius, "seed=", seed_val, Registry.sequence(seed_val, count), "ticks=", ticks,
		"pos=", local, "next=", auto.next_waypoint())
	assert_bool(auto.is_finished()).override_failure_message(
		"el piloto no completo el tramo (radio %s): pos=%s siguiente=%s" % [orbit_radius, local, auto.next_waypoint()]).is_true()
	assert_float(local.z).is_greater(float(count - 1) * Registry.CHUNK_LENGTH - 0.5)
