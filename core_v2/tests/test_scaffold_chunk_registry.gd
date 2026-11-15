extends GdUnitTestSuite

# Catalogo de chunks de andamio (Transit-Run): 50 semillas contra FlowRouteValidator.
# Datos puros, sin escena ni fisica: corre en milisegundos.

const Registry = preload("res://core_v2/systems/scaffold/ScaffoldChunkRegistry.gd")
const FlowMetricsScript = preload("res://core_v2/systems/flow/FlowMetrics.gd")
const Validator = preload("res://core_v2/systems/flow/FlowRouteValidator.gd")

const SEEDS := 50
const CHUNKS_PER_RUN := 24
const EPS := 1e-4

var _fm = null


func before() -> void:
	_fm = FlowMetricsScript.from_scene()


# Metricas REALES del piloto al tick dado (INV-4: se valida tambien a 30 Hz).
func _metrics(tick_hz: float) -> Dictionary:
	return {"g": _fm.gravity, "v_run": _fm.run_speed(), "v_jump": _fm.jump_force,
		"tick": 1.0 / tick_hz, "main_threshold": 0.80}


func test_every_chunk_alone_keeps_a_main_route_within_nominal_reach() -> void:
	var m := _metrics(60.0)
	for id in Registry.chunk_ids():
		var c: Dictionary = Registry.build_chunk(id, m)
		assert_bool(c.empty()).override_failure_message("chunk sin definir: %s" % id).is_false()
		var res: Dictionary = Validator.validate(
			{"entry": c["in"], "exit": c["out"], "nodes": c["nodes"], "edges": c["edges"]}, m)
		assert_bool(bool(res["valid_main_route"])).override_failure_message("%s sin ruta principal" % id).is_true()
		for side_node in c["side_outs"].values():
			assert_bool(res["main_path"].has(side_node)).is_false()


func test_tool_shortcuts_are_impossible_on_foot_or_flagged() -> void:
	var m := _metrics(60.0)
	var gloo: Dictionary = Registry.build_chunk("scaffold_gloo_rise", m)
	assert_float(float(gloo["dy"])).is_greater(Registry.h_max(m))
	for id in ["scaffold_gloo_rise", "scaffold_catenary_span", "scaffold_laser_choke", "diorama_mag_cart"]:
		var c: Dictionary = Registry.build_chunk(id, m)
		var res: Dictionary = Validator.validate(
			{"entry": c["in"], "exit": c["out"], "nodes": c["nodes"], "edges": c["edges"]}, m)
		assert_int(res["tool_edges"].size()).override_failure_message("%s sin arista de herramienta" % id).is_equal(1)


func test_fifty_seeds_zero_deadlocks_and_main_line_preserved() -> void:
	var seen := {}
	for tick in [60.0, 30.0]:
		var m := _metrics(tick)
		for s in range(SEEDS):
			var graph: Dictionary = Registry.generate(1000 + s, CHUNKS_PER_RUN, m)
			var res: Dictionary = Validator.validate(graph, m)
			assert_bool(bool(res["valid_main_route"])) \
				.override_failure_message("semilla %d @%dHz: %s" % [1000 + s, int(tick), str(res["report"])]).is_true()
			assert_str(str(res["main_path"][0])).is_equal(str(graph["entry"]))
			assert_str(str(res["main_path"][-1])).is_equal(str(graph["exit"]))
			for ev in res["main_path_edges"]:
				assert_float(float(ev["ratio_d"])).is_less_equal(Registry.D_NOM_RATIO + EPS)
				assert_float(float(ev["ratio_h"])).is_less_equal(Registry.H_NOM_RATIO + EPS)
			# Ningun socket lateral (S / R) es parte de la ruta principal.
			for p in graph["placements"]:
				seen[p["id"]] = true
				for side_node in p["side_outs"].values():
					assert_bool(res["main_path"].has("c%02d_%s" % [int(p["index"]), side_node])).is_false()
	# Las 50 semillas ejercitan el catalogo completo.
	for id in Registry.chunk_ids():
		assert_bool(seen.has(id)).override_failure_message("chunk nunca generado: %s" % id).is_true()


func test_same_seed_same_topology_and_waypoints() -> void:
	var m := _metrics(60.0)
	var distinct := {}
	for s in range(SEEDS):
		var a: Dictionary = Registry.generate(1000 + s, CHUNKS_PER_RUN, m)
		var b: Dictionary = Registry.generate(1000 + s, CHUNKS_PER_RUN, m)
		assert_str(var2str(a)).is_equal(var2str(b))
		assert_str(var2str(Validator.extract_main_waypoints(a, m))) \
			.is_equal(var2str(Validator.extract_main_waypoints(b, m)))
		distinct[str(Registry.sequence(1000 + s, CHUNKS_PER_RUN))] = true
	assert_int(distinct.size()).is_greater(SEEDS / 2)
