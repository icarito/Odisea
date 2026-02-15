tool
extends Control

var target_manager: LogicCircuitManager
var graph_edit: GraphEdit

func _ready():
	graph_edit = $GraphEdit
	graph_edit.connect("connection_request", self, "_on_connection_request")
	graph_edit.connect("disconnection_request", self, "_on_disconnection_request")
	graph_edit.connect("node_selected", self, "_on_node_selected")

	# Add a context menu or buttons here in a real implementation
	# For now, just setup basic handlers

func set_target_manager(manager: LogicCircuitManager):
	target_manager = manager
	if not target_manager.circuit_data:
		# Create a new resource if none exists
		# In editor, we might need to save it to disk?
		# For now, just create new in memory or modify existing
		# Actually, user should assign a resource.
		# If none, we can show a warning or create a temporary one.
		pass

	_refresh_graph()

func _refresh_graph():
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
		graph_edit.connect_node(conn.from, conn.from_port, conn.to, conn.to_port)

func _create_graph_node(id: String, data: Dictionary):
	var node = GraphNode.new()
	node.name = id
	node.title = id
	node.offset = data.get("position", Vector2.ZERO)
	node.show_close = true
	node.connect("close_request", self, "_on_node_close_request", [id])
	node.connect("dragged", self, "_on_node_dragged", [id])

	# Setup slots based on type
	var type = data.get("type", "PROP")
	if type == "PROP":
		node.title = "PROP: " + str(data.get("scene_path", "Unassigned"))
		# Input 0: Activate
		node.set_slot(0, true, 0, Color.green, true, 0, Color.red)
		# Left side: Inputs. Right side: Outputs.
		# set_slot(idx, enable_left, type_left, color_left, enable_right, type_right, color_right)
	elif type == "GATE":
		node.title = "GATE: " + data.get("gate_type", "AND")
		node.set_slot(0, true, 0, Color.blue, true, 0, Color.red)
		# More complex slot logic needed for multi-input gates

	graph_edit.add_child(node)

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
		data["position"] = to # 'to' is the new offset Vector2
		# No explicit update needed if dictionary is reference, but explicit set is safer
		target_manager.circuit_data.add_node(id, data) # Triggers changed

func _on_node_close_request(id):
	if target_manager and target_manager.circuit_data:
		target_manager.circuit_data.remove_node(id)
		var node = graph_edit.get_node(id)
		if node:
			node.queue_free()
