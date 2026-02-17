tool
extends VBoxContainer

var target_manager: LogicCircuitManager
var graph_edit: GraphEdit
var status_label: Label
var gate_popup: PopupMenu

# Store node positions to preserve on refresh
var _node_positions: Dictionary = {}

func _ready():
	graph_edit = $GraphEdit
	status_label = $Toolbar/StatusLabel
	
	# GraphEdit signals
	graph_edit.connect("connection_request", self, "_on_connection_request")
	graph_edit.connect("disconnection_request", self, "_on_disconnection_request")
	graph_edit.connect("node_selected", self, "_on_node_selected")
	
	# Toolbar buttons
	$Toolbar/AddPropBtn.connect("pressed", self, "_on_add_prop_pressed")
	$Toolbar/RefreshBtn.connect("pressed", self, "_on_refresh_pressed")
	$Toolbar/ClearBtn.connect("pressed", self, "_on_clear_pressed")
	
	# Gate dropdown menu
	gate_popup = $Toolbar/GateMenu.get_popup()
	gate_popup.connect("id_pressed", self, "_on_gate_selected")
	
	# Initial state
	if status_label:
		status_label.text = "Select a LogicCircuitManager to edit"

func set_target_manager(manager: LogicCircuitManager):
	target_manager = manager
	# Clear position cache when switching managers
	_node_positions.clear()
	if status_label:
		if target_manager and target_manager.circuit_data:
			var res_name = target_manager.circuit_data.resource_name
			status_label.text = "Circuit: " + str(res_name if res_name else "Unnamed")
		elif target_manager:
			status_label.text = "Assign a CircuitGraphResource"
		else:
			status_label.text = "No manager selected"
	_refresh_graph()

func _refresh_graph():
	# Save current positions from GraphEdit nodes before clearing
	for child in graph_edit.get_children():
		if child is GraphNode:
			_node_positions[child.name] = child.offset
	
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
		var n_data = data.nodes[id].duplicate()
		# Use saved position if available, otherwise use stored position
		if _node_positions.has(id):
			n_data["position"] = _node_positions[id]
		_create_graph_node(id, n_data)

	# Add Connections (use neutral color)
	for conn in data.connections:
		var from_id = conn.get("from", "")
		var to_id = conn.get("to", "")
		if from_id != "" and to_id != "" and data.nodes.has(from_id) and data.nodes.has(to_id):
			if graph_edit.has_node(from_id) and graph_edit.has_node(to_id):
				# Force port 0 for all connections
				graph_edit.connect_node(from_id, 0, to_id, 0)

func _create_graph_node(id: String, data: Dictionary):
	var node = GraphNode.new()
	node.name = id
	node.title = id
	node.offset = data.get("position", Vector2.ZERO)
	node.show_close = true
	node.connect("close_request", self, "_on_node_close_request", [id])
	node.connect("dragged", self, "_on_node_dragged", [id])
	node.rect_min_size = Vector2(80, 30)

	# Setup slots based on type
	var type = data.get("type", "PROP")
	var info_label = Label.new()
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Use neutral gray for all connections (type 0)
	var slot_color = Color(0.6, 0.6, 0.6)
	
	if type == "PROP":
		var scene_path = str(data.get("scene_path", ""))
		# Remove "../" prefix from display
		var display_name = scene_path
		if display_name.begins_with("../"):
			display_name = display_name.substr(3)
		node.title = display_name if display_name != "" else "Prop"
		info_label.text = display_name if display_name != "" else "(unassigned)"
		info_label.modulate = Color(0.7, 0.7, 0.7)
	elif type == "GATE":
		var gate_type = data.get("gate_type", "AND")
		node.title = gate_type
		if gate_type == "DELAY":
			info_label.text = str(data.get("delay_time", 1.0)) + "s"
		else:
			info_label.text = ""
	
	# Add the label first (creates row 0)
	node.add_child(info_label)
	
	# Add to graph first
	graph_edit.add_child(node)
	
	# Now set the slot for row 0 AFTER adding to tree
	# set_slot(row, enable_left, type_left, color_left, enable_right, type_right, color_right)
	node.set_slot(0, true, 0, slot_color, true, 0, slot_color)

func _on_connection_request(from, from_slot, to, to_slot):
	if target_manager and target_manager.circuit_data:
		# Only allow port 0 connections
		if from_slot != 0 or to_slot != 0:
			return
		var conn = {
			"from": from,
			"from_port": from_slot,
			"to": to,
			"to_port": to_slot,
			"type": "WIRED",
			"points": []
		}
		target_manager.circuit_data.connections.append(conn)
		graph_edit.connect_node(from, from_slot, to, to_slot)

func _on_disconnection_request(from, from_slot, to, to_slot):
	if target_manager and target_manager.circuit_data:
		var conns = target_manager.circuit_data.connections
		for i in range(conns.size()):
			if conns[i]["from"] == from and conns[i]["from_port"] == from_slot and conns[i]["to"] == to and conns[i]["to_port"] == to_slot:
				conns.remove(i)
				break
		graph_edit.disconnect_node(from, from_slot, to, to_slot)

func _on_node_dragged(from, to, id):
	# Save position to cache
	_node_positions[id] = to
	if target_manager and target_manager.circuit_data:
		# Access nodes dictionary directly
		if target_manager.circuit_data.nodes.has(id):
			target_manager.circuit_data.nodes[id]["position"] = to

func _on_node_selected(node):
	# Placeholder for node selection handling
	pass

func _on_node_close_request(id):
	if target_manager and target_manager.circuit_data:
		# Remove from nodes dictionary directly
		target_manager.circuit_data.nodes.erase(id)
		# Remove associated connections
		var conns = target_manager.circuit_data.connections
		for i in range(conns.size() - 1, -1, -1):
			if conns[i]["from"] == id or conns[i]["to"] == id:
				conns.remove(i)
		var node = graph_edit.get_node(id)
		if node:
			node.queue_free()

# Toolbar handlers
func _on_add_prop_pressed():
	if not target_manager:
		status_label.text = "Error: Select a LogicCircuitManager first"
		print("[CircuitBoard] No target_manager assigned")
		return
	if not target_manager.circuit_data:
		status_label.text = "Error: Assign a CircuitGraphResource to manager"
		print("[CircuitBoard] No circuit_data in manager")
		return
	
	# Generate unique ID
	var node_id = "Prop_%d" % (target_manager.circuit_data.nodes.size() + 1)
	var node_data = {
		"type": "PROP",
		"position": Vector2(100 + (target_manager.circuit_data.nodes.size() * 20), 100),
		"scene_path": ""
	}
	# Access nodes dictionary directly
	target_manager.circuit_data.nodes[node_id] = node_data
	_create_graph_node(node_id, node_data)
	status_label.text = "Added: " + node_id
	print("[CircuitBoard] Created node: ", node_id)

func _on_gate_selected(id: int):
	if not target_manager:
		status_label.text = "Error: Select a LogicCircuitManager first"
		print("[CircuitBoard] No target_manager assigned")
		return
	if not target_manager.circuit_data:
		status_label.text = "Error: Assign a CircuitGraphResource to manager"
		print("[CircuitBoard] No circuit_data in manager")
		return
	
	var gate_types = ["AND", "OR", "XOR", "NOT", "DELAY"]
	var gate_type = gate_types[id]
	var node_id = "%s_%d" % [gate_type, target_manager.circuit_data.nodes.size() + 1]
	var node_data = {
		"type": "GATE",
		"gate_type": gate_type,
		"position": Vector2(200 + (target_manager.circuit_data.nodes.size() * 20), 100),
		"delay_time": 1.0 if gate_type == "DELAY" else 0.0
	}
	# Access nodes dictionary directly
	target_manager.circuit_data.nodes[node_id] = node_data
	_create_graph_node(node_id, node_data)
	status_label.text = "Added: " + node_id
	print("[CircuitBoard] Created gate: ", node_id)

func _on_refresh_pressed():
	_refresh_graph()
	status_label.text = "Graph refreshed"

func _on_clear_pressed():
	if target_manager and target_manager.circuit_data:
		target_manager.circuit_data.clear()
		_refresh_graph()
		status_label.text = "Circuit cleared"
