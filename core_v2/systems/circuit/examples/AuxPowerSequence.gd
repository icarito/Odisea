extends Reference
class_name AuxPowerSequence

# AuxPowerSequence.gd - Programmatically builds a CircuitGraphResource for FD-259 aux power recalibration.
# Connects three panel props -> AND gate -> AuxPowerBus.

static func create_graph(
	panel1_path: NodePath = NodePath("Panel1"),
	panel2_path: NodePath = NodePath("Panel2"),
	panel3_path: NodePath = NodePath("Panel3"),
	bus_path: NodePath = NodePath("AuxPowerBus")
) -> CircuitGraphResource:
	var graph = CircuitGraphResource.new()

	graph.add_node("panel1", {
		"type": "PROP",
		"scene_path": panel1_path
	})
	graph.add_node("panel2", {
		"type": "PROP",
		"scene_path": panel2_path
	})
	graph.add_node("panel3", {
		"type": "PROP",
		"scene_path": panel3_path
	})
	graph.add_node("and_gate", {
		"type": "GATE",
		"gate_type": "AND"
	})
	graph.add_node("aux_bus", {
		"type": "PROP",
		"scene_path": bus_path
	})

	graph.connect_nodes("panel1", 0, "and_gate", 0)
	graph.connect_nodes("panel2", 0, "and_gate", 1)
	graph.connect_nodes("panel3", 0, "and_gate", 2)
	graph.connect_nodes("and_gate", 0, "aux_bus", 0)

	return graph
