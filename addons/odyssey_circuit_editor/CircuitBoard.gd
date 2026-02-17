tool
extends Control

var target_manager: LogicCircuitManager
var graph_edit: GraphEdit
var _gate_popup: PopupMenu

func _ready():
	graph_edit = $VBoxContainer/GraphEdit
	graph_edit.connect("connection_request", self, "_on_connection_request")
	graph_edit.connect("disconnection_request", self, "_on_disconnection_request")
	graph_edit.connect("node_selected", self, "_on_node_selected")
	
	# Setup toolbar buttons
	var add_prop_btn = $VBoxContainer/ToolBar/AddPropBtn
	add_prop_btn.connect("pressed", self, "_on_add_prop_pressed")
	
	var add_gate_btn = $VBoxContainer/ToolBar/AddGateBtn
	_setup_gate_menu(add_gate_btn)
	
	var refresh_btn = $VBoxContainer/ToolBar/RefreshBtn
	refresh_btn.connect("pressed", self, "_refresh_graph")
	
	var clear_btn = $VBoxContainer/ToolBar/ClearBtn
	clear_btn.connect("pressed", self, "_on_clear_pressed")

func _setup_gate_menu(btn: MenuButton):
	var popup = btn.get_popup()
	popup.add_item("AND", 0)
	popup.add_item("OR", 1)
	popup.add_item("XOR", 2)
	popup.add_item("NOT", 3)
	popup.add_item("DELAY", 4)
	popup.connect("id_pressed", self, "_on_gate_selected")
	_gate_popup = popup

func set_target_manager(manager: LogicCircuitManager):
	target_manager = manager
	if not target_manager.circuit_data:
		pass  # User should assign a resource
	_refresh_graph()

func _refresh_graph():
	if not graph_edit:
		return
	
	graph_edit.clear_connections()
	for child in graph_edit.get_children():
		if child is GraphNode:
			graph_edit.remove_child(child)
			child.queue_free()

	if not target_manager or not target_manager.circuit_data:
		return

	var data = target_manager.circuit_data

	# Add Nodes
	for id in data.nodes:
		var n_data = data.nodes[id]
		_create_graph_node(id, n_data)

	# Add Connections
	for conn in data.connections:
		if data.nodes.has(conn.from) and data.nodes.has(conn.to):
			if graph_edit.has_node(conn.from) and graph_edit.has_node(conn.to):
				graph_edit.connect_node(conn.from, conn.from_port, conn.to, conn.to_port)

func _create_graph_node(id: String, data: Dictionary):
	var node = GraphNode.new()
	node.name = id
	node.title = id
	node.offset = data.get("position", Vector2.ZERO)
	node.show_close = true
	node.connect("close_request", self, "_on_node_close_request", [id])
	node.connect("dragged", self, "_on_node_dragged", [id])

	var type = data.get("type", "PROP")
	if type == "PROP":
		node.title = "PROP: " + str(data.get("scene_path", "Unassigned"))
		node.set_slot(0, true, 0, Color.green, true, 0, Color.red)
	elif type == "GATE":
		node.title = "GATE: " + data.get("gate_type", "AND")
		node.set_slot(0, true, 0, Color.blue, true, 0, Color.red)

	graph_edit.add_child(node)

func _on_add_prop_pressed():
	if not target_manager or not target_manager.circuit_data:
		return
	
	# Generate unique ID
	var id = "Prop_%d" % [Time.get_ticks_msec()]
	var data = {
		"type": "PROP",
		"scene_path": "",
		"position": Vector2(100, 100)
	}
	target_manager.circuit_data.add_node(id, data)
	_create_graph_node(id, data)

func _on_gate_selected(id: int):
	if not target_manager or not target_manager.circuit_data:
		return
	
	var gate_types = ["AND", "OR", "XOR", "NOT", "DELAY"]
	var gate_type = gate_types[id]
	var node_id = "Gate_%s_%d" % [gate_type, Time.get_ticks_msec()]
	var data = {
		"type": "GATE",
		"gate_type": gate_type,
		"position": Vector2(200, 100)
	}
	target_manager.circuit_data.add_node(node_id, data)
	_create_graph_node(node_id, data)

func _on_clear_pressed():
	if not target_manager or not target_manager.circuit_data:
		return
	
	target_manager.circuit_data.nodes.clear()
	target_manager.circuit_data.connections.clear()
	_refresh_graph()

func _on_connection_request(from, from_slot, to, to_slot):
	if target_manager and target_manager.circuit_data:
		target_manager.circuit_data.connect_nodes(from, from_slot, to, to_slot)
		graph_edit.connect_node(from, from_slot, to, to_slot)

func _on_disconnection_request(from, from_slot, to, to_slot):
	if target_manager and target_manager.circuit_data:
		target_manager.circuit_data.disconnect_nodes(from, from_slot, to, to_slot)
		graph_edit.disconnect_node(from, from_slot, to, to_slot)

func _on_node_dragged(from, to, id):
	if target_manager and target_manager.circuit_data:
		var data = target_manager.circuit_data.get_node_data(id)
		data["position"] = to
		target_manager.circuit_data.add_node(id, data)

func _on_node_close_request(id):
	if target_manager and target_manager.circuit_data:
		target_manager.circuit_data.remove_node(id)
		var node = graph_edit.get_node(id)
		if node:
			node.queue_free()
