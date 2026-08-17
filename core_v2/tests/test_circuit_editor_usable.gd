extends GdUnitTestSuite

# test_circuit_editor_usable.gd
# Verifies the circuit editor plugin functionality, node picking, port validation, dirty tracking, and clean cable generation.

var _changed_emitted := false

func _on_res_changed() -> void:
	_changed_emitted = true

func test_editor_scene_picker_and_path_resolution() -> void:
	var root = Spatial.new()
	add_child(root)

	var manager = LogicCircuitManager.new()
	manager.name = "LogicCircuitManager"
	root.add_child(manager)

	var prop = Spatial.new()
	prop.name = "WallTerminal"
	root.add_child(prop)

	# Path relative to manager
	var rel_path = manager.get_path_to(prop)
	assert_str(str(rel_path)).is_equal("../WallTerminal")

	var res = CircuitGraphResource.new()
	manager.circuit_data = res

	res.add_node("Prop_1", {
		"type": "PROP",
		"position": Vector2(10, 10),
		"scene_path": rel_path
	})

	manager._build_runtime_logic()
	var runtime = manager._runtime_nodes.get("Prop_1", {})
	assert_object(runtime.get("ref", null)).is_equal(prop)

	root.queue_free()

func test_editor_port_validation() -> void:
	var scene = load("res://addons/odyssey_circuit_editor/CircuitBoard.tscn")
	assert_object(scene).is_not_null()

	var board = scene.instance()
	add_child(board)

	var prop_node = { "type": "PROP" }
	var gate_node = { "type": "GATE", "gate_type": "AND" }

	# PROP slot 0 is output and input
	assert_bool(board._node_has_output_slot(prop_node, 0)).is_true()
	assert_bool(board._node_has_input_slot(prop_node, 0)).is_true()

	# GATE AND slot 0 is output and input, slot 1 is input only
	assert_bool(board._node_has_output_slot(gate_node, 0)).is_true()
	assert_bool(board._node_has_output_slot(gate_node, 1)).is_false()
	assert_bool(board._node_has_input_slot(gate_node, 0)).is_true()
	assert_bool(board._node_has_input_slot(gate_node, 1)).is_true()

	board.queue_free()

func test_dirty_tracking_emits_changed() -> void:
	_changed_emitted = false
	var res = CircuitGraphResource.new()
	res.connect("changed", self, "_on_res_changed")
	res.add_node("Gate_1", {"type": "GATE", "gate_type": "AND"})
	assert_bool(res.nodes.has("Gate_1")).is_true()
	assert_bool(_changed_emitted).is_true()

func test_cable_generation_runs_single_pass() -> void:
	var root = Spatial.new()
	add_child(root)

	var manager = LogicCircuitManager.new()
	root.add_child(manager)

	var p1 = Spatial.new()
	p1.name = "P1"
	root.add_child(p1)

	var p2 = Spatial.new()
	p2.name = "P2"
	root.add_child(p2)

	var res = CircuitGraphResource.new()
	res.add_node("N1", {"type": "PROP", "scene_path": manager.get_path_to(p1)})
	res.add_node("N2", {"type": "PROP", "scene_path": manager.get_path_to(p2)})
	res.connect_nodes("N1", 0, "N2", 0)

	manager.circuit_data = res
	manager._build_runtime_logic()
	manager.generate_cables()

	# Verify cables generated count equals connections
	assert_int(manager._cables.size()).is_equal(1)

	root.queue_free()
