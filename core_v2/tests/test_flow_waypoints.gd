extends GdUnitTestSuite

const FlowRouteValidatorScript = preload("res://core_v2/systems/flow/FlowRouteValidator.gd")
const BayVerticalContentScript = preload("res://core_v2/levels/bay_vertical/BayVerticalContent.gd")


func test_extract_main_waypoints_orders_entry_to_exit_and_excludes_side_sockets() -> void:
	var metrics: Dictionary = FlowRouteValidatorScript.default_metrics()
	var graph := {
		"entry": "corridor_start",
		"exit": "corridor_exit",
		"nodes": [
			{"id": "corridor_start", "position": Vector3(0.0, 0.0, 0.0), "size": Vector3(4.0, 0.5, 4.0), "tags": ["SprintGap"]},
			{"id": "bifurcation_hub", "position": Vector3(0.0, 0.0, 8.0), "size": Vector3(4.0, 0.5, 4.0), "tags": ["SprintGap"]},
			{"id": "side_socket_station", "position": Vector3(6.0, 1.0, 12.0), "size": Vector3(3.0, 0.5, 3.0), "tags": ["CuratedSocket"]},
			{"id": "main_mid", "position": Vector3(0.0, 0.5, 16.0), "size": Vector3(4.0, 0.5, 4.0), "tags": ["RhythmSteps"]},
			{"id": "corridor_exit", "position": Vector3(0.0, 0.5, 24.0), "size": Vector3(4.0, 0.5, 4.0), "tags": ["SprintGap"]},
		],
		"edges": [
			{"from": "corridor_start", "to": "bifurcation_hub"},
			{"from": "bifurcation_hub", "to": "side_socket_station", "tags": ["CuratedSocket"]},
			{"from": "bifurcation_hub", "to": "main_mid"},
			{"from": "main_mid", "to": "corridor_exit"},
			{"from": "side_socket_station", "to": "corridor_exit", "tags": ["MagRail"]},
		],
	}

	var waypoints: Array = FlowRouteValidatorScript.extract_main_waypoints(graph, metrics)
	assert_int(waypoints.size()).is_equal(4)
	assert_str(waypoints[0]["id"]).is_equal("corridor_start")
	assert_bool(waypoints[0]["is_entry"]).is_true()
	assert_bool(waypoints[0]["is_exit"]).is_false()
	assert_int(waypoints[0]["index"]).is_equal(0)

	assert_str(waypoints[1]["id"]).is_equal("bifurcation_hub")
	assert_str(waypoints[2]["id"]).is_equal("main_mid")
	assert_vector3(waypoints[2]["position"]).is_equal(Vector3(0.0, 0.5, 16.0))

	assert_str(waypoints[3]["id"]).is_equal("corridor_exit")
	assert_bool(waypoints[3]["is_entry"]).is_false()
	assert_bool(waypoints[3]["is_exit"]).is_true()
	assert_int(waypoints[3]["index"]).is_equal(3)

	var side_sockets: Array = FlowRouteValidatorScript.extract_side_socket_waypoints(graph, metrics)
	assert_int(side_sockets.size()).is_equal(1)
	assert_str(side_sockets[0]["id"]).is_equal("side_socket_station")
	assert_str(side_sockets[0]["from"]).is_equal("bifurcation_hub")
	assert_vector3(side_sockets[0]["position"]).is_equal(Vector3(6.0, 1.0, 12.0))


func test_extract_main_waypoints_is_deterministic_independent_of_input_order() -> void:
	var metrics: Dictionary = FlowRouteValidatorScript.default_metrics()
	var nodes_a := [
		{"id": "a_start", "position": Vector3(0.0, 0.0, 0.0), "size": 3.0},
		{"id": "b_branch", "position": Vector3(0.0, 0.0, 6.0), "size": 3.0},
		{"id": "c_socket", "position": Vector3(-5.0, 0.0, 9.0), "size": 3.0, "tags": ["CuratedSocket"]},
		{"id": "d_end", "position": Vector3(0.0, 0.0, 12.0), "size": 3.0},
	]
	var edges_a := [
		{"from": "a_start", "to": "b_branch"},
		{"from": "b_branch", "to": "c_socket", "tags": ["CuratedSocket"]},
		{"from": "b_branch", "to": "d_end"},
	]
	var nodes_b := [nodes_a[3], nodes_a[2], nodes_a[1], nodes_a[0]]
	var edges_b := [edges_a[2], edges_a[1], edges_a[0]]

	var wp_a: Array = FlowRouteValidatorScript.extract_main_waypoints(
		{"entry": "a_start", "exit": "d_end", "nodes": nodes_a, "edges": edges_a},
		metrics
	)
	var wp_b: Array = FlowRouteValidatorScript.extract_main_waypoints(
		{"entry": "a_start", "exit": "d_end", "nodes": nodes_b, "edges": edges_b},
		metrics
	)

	assert_int(wp_a.size()).is_equal(3)
	assert_int(wp_b.size()).is_equal(3)
	for i in range(wp_a.size()):
		assert_str(wp_a[i]["id"]).is_equal(wp_b[i]["id"])
		assert_vector3(wp_a[i]["position"]).is_equal(wp_b[i]["position"])


func test_extract_main_waypoints_returns_empty_when_main_route_invalid() -> void:
	var metrics: Dictionary = FlowRouteValidatorScript.default_metrics()
	var graph := {
		"entry": "start",
		"exit": "end",
		"nodes": [
			{"id": "start", "position": Vector3(0.0, 0.0, 0.0), "size": 2.0},
			{"id": "end", "position": Vector3(0.0, 0.0, 40.0), "size": 2.0},
		],
		"edges": [
			{"from": "start", "to": "end"},
		],
	}
	var wp: Array = FlowRouteValidatorScript.extract_main_waypoints(graph, metrics)
	assert_array(wp).is_empty()


func test_bay_vertical_content_exposes_ordered_main_waypoints() -> void:
	var bay = auto_free(BayVerticalContentScript.new())
	bay.generation_seed = 4242
	bay._flow = auto_free(preload("res://core_v2/levels/bay_vertical/BayTransitFlow.gd").new())
	bay._flow.configure_ring(sqrt(14.0 / 48.0), bay._base_radius())
	bay._compute_route()

	var res: Dictionary = bay.validate_main_route()
	assert_bool(res.get("valid_main_route", false)).is_true()
	var waypoints: Array = res.get("main_waypoints", [])
	assert_int(waypoints.size()).is_greater(2)
	assert_bool(waypoints[0]["is_entry"]).is_true()
	assert_bool(waypoints[waypoints.size() - 1]["is_exit"]).is_true()
	for i in range(waypoints.size()):
		assert_int(waypoints[i]["index"]).is_equal(i)
		assert_bool(waypoints[i]["has_position"]).is_true()
