extends GdUnitTestSuite

func test_circuit_graph_resource_loads_and_validates_unknown_gate() -> void:
	var script: Script = load("res://core_v2/systems/circuit/CircuitGraphResource.gd")
	assert_object(script).is_not_null()

	var graph: Resource = auto_free(Resource.new())
	graph.set_script(script)

	graph.call("add_node", "gate_a", {
		"type": "GATE",
		"gate_type": "BAD_GATE"
	})

	var result: Dictionary = graph.call("validate")
	assert_bool(bool(result.get("valid", true))).is_false()
	var errors: Array = result.get("errors", [])
	assert_bool(errors.size() > 0).is_true()
