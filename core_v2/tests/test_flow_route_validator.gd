extends GdUnitTestSuite

const FlowRouteValidatorScript = preload("res://core_v2/systems/flow/FlowRouteValidator.gd")


func _base_metrics(tick_val: float = 0.0) -> Dictionary:
	return {
		"g": 14.0,
		"v_run": 7.0,
		"v_jump": 10.0,
		"tick": tick_val,
		"main_threshold": 0.80,
		"optional_min": 0.90,
		"optional_max": 1.00,
	}


func test_ballistic_formulas_continuous_and_tick_correction() -> void:
	# Sin corrección por tick: H_max = 100 / 28 = 3.571428..., D(0) = 7 * 20 / 14 = 10.0
	var h_cont: float = FlowRouteValidatorScript.compute_h_max(10.0, 14.0, 0.0)
	var d_cont: float = FlowRouteValidatorScript.compute_d_max(7.0, 10.0, 14.0, 0.0, 0.0)
	assert_float(h_cont).is_equal_approx(100.0 / 28.0, 1e-5)
	assert_float(d_cont).is_equal_approx(10.0, 1e-5)

	# Con corrección semi-implícita por tick (+v * dt / 2)
	var dt := 1.0 / 60.0
	var h_tick: float = FlowRouteValidatorScript.compute_h_max(10.0, 14.0, dt)
	var d_tick: float = FlowRouteValidatorScript.compute_d_max(7.0, 10.0, 14.0, 0.0, dt)
	assert_float(h_tick).is_equal_approx(h_cont + 0.5 * 10.0 * dt, 1e-5)
	assert_float(d_tick).is_equal_approx(d_cont + 0.5 * 7.0 * dt, 1e-5)


func test_exact_main_threshold_pass_and_fail_horizontal() -> void:
	var m := _base_metrics(1.0 / 60.0)
	var d_max: float = FlowRouteValidatorScript.compute_d_max(m["v_run"], m["v_jump"], m["g"], 0.0, m["tick"])
	var exact_limit := 0.80 * d_max

	var nodes := [
		{"id": "A", "tags": ["SprintGap"]},
		{"id": "B", "tags": ["SprintGap"]},
	]

	var pass_graph := {
		"entry": "A",
		"exit": "B",
		"nodes": nodes,
		"edges": [{"from": "A", "to": "B", "gap_horizontal": exact_limit, "delta_h": 0.0}],
	}
	var pass_res: Dictionary = FlowRouteValidatorScript.validate(pass_graph, m)
	assert_bool(pass_res["valid_main_route"]).is_true()
	assert_str(pass_res["critical_edge"]["category"]).is_equal(FlowRouteValidatorScript.CAT_MAIN)

	# Justo por encima del 80% debe fallar como ruta principal y clasificarse como opcional
	var fail_graph := {
		"entry": "A",
		"exit": "B",
		"nodes": nodes,
		"edges": [{"from": "A", "to": "B", "gap_horizontal": exact_limit + 0.02, "delta_h": 0.0}],
	}
	var fail_res: Dictionary = FlowRouteValidatorScript.validate(fail_graph, m)
	assert_bool(fail_res["valid_main_route"]).is_false()
	assert_int(fail_res["optional_edges"].size()).is_equal(1)
	assert_str(fail_res["optional_edges"][0]["category"]).is_equal(FlowRouteValidatorScript.CAT_OPTIONAL_SKILL)


func test_exact_main_threshold_pass_and_fail_vertical() -> void:
	var m := _base_metrics(1.0 / 60.0)
	var h_max: float = FlowRouteValidatorScript.compute_h_max(m["v_jump"], m["g"], m["tick"])
	var exact_h := 0.80 * h_max

	var nodes := [
		{"id": "low", "tags": ["RhythmSteps"]},
		{"id": "high", "tags": ["RhythmSteps"]},
	]

	var pass_graph := {
		"entry": "low",
		"exit": "high",
		"nodes": nodes,
		"edges": [{"from": "low", "to": "high", "gap_horizontal": 1.0, "delta_h": exact_h}],
	}
	var pass_res: Dictionary = FlowRouteValidatorScript.validate(pass_graph, m)
	assert_bool(pass_res["valid_main_route"]).is_true()

	var fail_graph := {
		"entry": "low",
		"exit": "high",
		"nodes": nodes,
		"edges": [{"from": "low", "to": "high", "gap_horizontal": 1.0, "delta_h": exact_h + 0.05}],
	}
	var fail_res: Dictionary = FlowRouteValidatorScript.validate(fail_graph, m)
	assert_bool(fail_res["valid_main_route"]).is_false()


func test_positive_and_negative_delta_h() -> void:
	var m := _base_metrics(0.0)
	# Subida (+2.0m): t_aire = (10 + sqrt(100 - 56)) / 14 = (10 + 6.63325) / 14 = 1.18809 s -> D ≈ 8.3166m
	# 80% de 8.3166m ≈ 6.653m; un gap de 7.2m no pasa main al subir, pero sí al bajar (-2.0m).
	var d_up: float = FlowRouteValidatorScript.compute_d_max(7.0, 10.0, 14.0, 2.0, 0.0)
	var d_down: float = FlowRouteValidatorScript.compute_d_max(7.0, 10.0, 14.0, -2.0, 0.0)
	assert_float(d_down).is_greater(d_up)

	var nodes := [{"id": "P0"}, {"id": "P1"}]
	var gap := 7.2

	var up_res: Dictionary = FlowRouteValidatorScript.validate({
		"entry": "P0",
		"exit": "P1",
		"nodes": nodes,
		"edges": [{"from": "P0", "to": "P1", "gap_horizontal": gap, "delta_h": 2.0}],
	}, m)
	assert_bool(up_res["valid_main_route"]).is_false()

	var down_res: Dictionary = FlowRouteValidatorScript.validate({
		"entry": "P0",
		"exit": "P1",
		"nodes": nodes,
		"edges": [{"from": "P0", "to": "P1", "gap_horizontal": gap, "delta_h": -2.0}],
	}, m)
	assert_bool(down_res["valid_main_route"]).is_true()


func test_variable_gravity_centrifugal_ring() -> void:
	# En un anillo centrífugo g(r) cambia con el radio:
	# radio menor => g menor (ej. 9.0 m/s^2) => mayor D_max;
	# radio mayor => g mayor (ej. 18.0 m/s^2) => menor D_max.
	var nodes := [{"id": "A"}, {"id": "B"}]
	var graph := {
		"entry": "A",
		"exit": "B",
		"nodes": nodes,
		"edges": [{"from": "A", "to": "B", "gap_horizontal": 9.0, "delta_h": 0.0}],
	}

	var low_g_metrics := _base_metrics(1.0 / 60.0)
	low_g_metrics["g"] = 9.0
	var low_g_res: Dictionary = FlowRouteValidatorScript.validate(graph, low_g_metrics)
	assert_bool(low_g_res["valid_main_route"]).is_true()

	var high_g_metrics := _base_metrics(1.0 / 60.0)
	high_g_metrics["g"] = 18.0
	var high_g_res: Dictionary = FlowRouteValidatorScript.validate(graph, high_g_metrics)
	assert_bool(high_g_res["valid_main_route"]).is_false()
	assert_int(high_g_res["unreachable_edges"].size()).is_equal(1)


func test_tools_and_curated_sockets_never_qualify_for_main_route() -> void:
	var m := _base_metrics(1.0 / 60.0)
	var graph := {
		"entry": "start",
		"exit": "goal",
		"nodes": [
			{"id": "start"},
			{"id": "gloo_wall", "tags": ["GlooClimb"]},
			{"id": "rail_node", "tags": ["MagRail"]},
			{"id": "socket_room", "tags": ["CuratedSocket"]},
			{"id": "goal"},
		],
		"edges": [
			{"from": "start", "to": "gloo_wall", "gap_horizontal": 2.0, "delta_h": 0.0},
			{"from": "gloo_wall", "to": "goal", "gap_horizontal": 2.0, "delta_h": 0.0},
			{"from": "start", "to": "rail_node", "gap_horizontal": 2.0, "delta_h": 0.0, "tags": ["MagRail"]},
			{"from": "rail_node", "to": "goal", "gap_horizontal": 2.0, "delta_h": 0.0},
			{"from": "start", "to": "socket_room", "gap_horizontal": 2.0, "delta_h": 0.0, "tags": ["CuratedSocket"]},
			{"from": "socket_room", "to": "goal", "gap_horizontal": 2.0, "delta_h": 0.0},
			# Ruta opcional roll-jump (95% de D_max)
			{"from": "start", "to": "goal", "gap_horizontal": 9.5, "delta_h": 0.0},
		],
	}

	var res: Dictionary = FlowRouteValidatorScript.validate(graph, m)
	assert_bool(res["valid_main_route"]).is_false()
	assert_int(res["tool_edges"].size()).is_equal(2)
	assert_int(res["optional_edges"].size()).is_equal(2) # CuratedSocket + roll-jump 95%
	var found_roll_jump := false
	for ev in res["optional_edges"]:
		if bool(ev["in_roll_jump_band"]):
			found_roll_jump = true
	assert_bool(found_roll_jump).is_true()


func test_determinism_independent_of_input_order() -> void:
	var m := _base_metrics(1.0 / 60.0)
	var graph_a := {
		"entry": "S",
		"exit": "E",
		"nodes": [
			{"id": "S"},
			{"id": "M1"},
			{"id": "M2"},
			{"id": "E"},
		],
		"edges": [
			{"from": "S", "to": "M1", "gap_horizontal": 4.0, "delta_h": 0.0},
			{"from": "M1", "to": "E", "gap_horizontal": 6.5, "delta_h": 0.5},
			{"from": "S", "to": "M2", "gap_horizontal": 5.0, "delta_h": 0.0},
			{"from": "M2", "to": "E", "gap_horizontal": 5.5, "delta_h": 0.0},
		],
	}
	var graph_b := {
		"entry": "S",
		"exit": "E",
		"nodes": [
			{"id": "E"},
			{"id": "M2"},
			{"id": "M1"},
			{"id": "S"},
		],
		"edges": [
			{"from": "M2", "to": "E", "gap_horizontal": 5.5, "delta_h": 0.0},
			{"from": "S", "to": "M2", "gap_horizontal": 5.0, "delta_h": 0.0},
			{"from": "M1", "to": "E", "gap_horizontal": 6.5, "delta_h": 0.5},
			{"from": "S", "to": "M1", "gap_horizontal": 4.0, "delta_h": 0.0},
		],
	}

	var res_a: Dictionary = FlowRouteValidatorScript.validate(graph_a, m)
	var res_b: Dictionary = FlowRouteValidatorScript.validate(graph_b, m)

	assert_bool(res_a["valid_main_route"]).is_true()
	assert_array(res_a["main_path"]).is_equal(res_b["main_path"])
	assert_str(res_a["critical_edge"]["from"]).is_equal(res_b["critical_edge"]["from"])
	assert_str(res_a["critical_edge"]["to"]).is_equal(res_b["critical_edge"]["to"])
	assert_str(res_a["report"]).is_equal(res_b["report"])


func test_consumer_example_machine_bay_labyrinth_streamer() -> void:
	# Ejemplo de uso para MachineBayLabyrinthStreamer:
	# Chunks conectados por costuras (SprintGap / RhythmSteps) + un Side Socket opcional.
	var metrics: Dictionary = FlowRouteValidatorScript.default_metrics()
	var chunk_graph := {
		"entry": "bay_door_west",
		"exit": "chunk_0_1_east",
		"nodes": [
			{"id": "bay_door_west", "position": Vector3(22.0, 0.0, 26.0), "size": Vector3(3.0, 0.5, 3.0), "tags": ["SprintGap"]},
			{"id": "chunk_0_0_seam", "position": Vector3(31.0, 0.5, 26.0), "size": Vector3(3.0, 0.5, 3.0), "tags": ["RhythmSteps"]},
			{"id": "chunk_0_1_east", "position": Vector3(40.0, 0.0, 26.0), "size": Vector3(3.0, 0.5, 3.0), "tags": ["SprintGap"]},
			{"id": "side_socket_relay", "position": Vector3(31.0, 1.5, 34.0), "size": Vector3(3.0, 0.5, 3.0), "tags": ["CuratedSocket"]},
		],
		"edges": [
			{"from": "bay_door_west", "to": "chunk_0_0_seam"},
			{"from": "chunk_0_0_seam", "to": "chunk_0_1_east"},
			{"from": "chunk_0_0_seam", "to": "side_socket_relay", "tags": ["CuratedSocket"]},
		],
	}

	var res: Dictionary = FlowRouteValidatorScript.validate(chunk_graph, metrics)
	assert_bool(res["valid_main_route"]).is_true()
	assert_array(res["main_path"]).is_equal(["bay_door_west", "chunk_0_0_seam", "chunk_0_1_east"])
	assert_int(res["optional_edges"].size()).is_equal(1)
	assert_str(res["optional_edges"][0]["to"]).is_equal("side_socket_relay")


func test_consumer_example_bay_vertical_with_centrifugal_g_and_shortcut() -> void:
	# Ejemplo de uso para bay_vertical:
	# Ascenso en terrazas con gravedad local g(r) por tramo + atajo opcional MagRail.
	var metrics: Dictionary = FlowRouteValidatorScript.default_metrics()
	var vertical_graph := {
		"entry": "deck_0",
		"exit": "deck_3",
		"nodes": [
			{"id": "deck_0", "tags": ["RhythmSteps"]},
			{"id": "deck_1", "tags": ["RhythmSteps"]},
			{"id": "deck_2", "tags": ["SprintGap"]},
			{"id": "deck_3", "tags": ["SprintGap"]},
		],
		"edges": [
			{"from": "deck_0", "to": "deck_1", "gap_horizontal": 3.5, "delta_h": 2.2, "g": 13.0},
			{"from": "deck_1", "to": "deck_2", "gap_horizontal": 4.2, "delta_h": 2.0, "g": 11.5},
			{"from": "deck_2", "to": "deck_3", "gap_horizontal": 5.0, "delta_h": 1.8, "g": 10.0},
			# Atajo vertical con herramienta MagRail (no cuenta para ruta principal)
			{"from": "deck_0", "to": "deck_3", "gap_horizontal": 2.0, "delta_h": 6.0, "tags": ["MagRail"]},
		],
	}

	var res: Dictionary = FlowRouteValidatorScript.validate(vertical_graph, metrics)
	assert_bool(res["valid_main_route"]).is_true()
	assert_array(res["main_path"]).is_equal(["deck_0", "deck_1", "deck_2", "deck_3"])
	assert_int(res["tool_edges"].size()).is_equal(1)
	assert_bool(res["report"].find("PASS") != -1).is_true()
