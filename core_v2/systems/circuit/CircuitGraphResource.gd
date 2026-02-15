extends Resource
class_name CircuitGraphResource

# CircuitGraphResource
# Stores the topology of the logic circuit.

# nodes: Dictionary { node_id (String) -> NodeData (Dictionary) }
# NodeData: {
#   "type": "PROP" or "GATE",
#   "position": Vector2, # Graph Editor position
#   "scene_path": NodePath, # For PROP types, relative to Manager
#   "gate_type": "AND", "OR", "XOR", "DELAY", # For GATE types
#   "delay_time": float # For DELAY gate
# }
export(Dictionary) var nodes = {}

# connections: Array of Dictionary
# {
#   "from": node_id (String),
#   "from_port": int,
#   "to": node_id (String),
#   "to_port": int,
#   "type": "WIRED" or "WIRELESS",
#   "points": Array of Vector3 # Baked cable points (optional)
# }
export(Array) var connections = []

func add_node(id: String, data: Dictionary) -> void:
	nodes[id] = data
	emit_changed()

func remove_node(id: String) -> void:
	if nodes.has(id):
		nodes.erase(id)
		# Remove associated connections
		var to_remove = []
		for i in range(connections.size()):
			if connections[i]["from"] == id or connections[i]["to"] == id:
				to_remove.append(i)

		# Remove in reverse order to keep indices valid
		to_remove.invert()
		for i in to_remove:
			connections.remove(i)
		emit_changed()

func connect_nodes(from_id: String, from_port: int, to_id: String, to_port: int, type: String = "WIRED") -> void:
	var conn = {
		"from": from_id,
		"from_port": from_port,
		"to": to_id,
		"to_port": to_port,
		"type": type,
		"points": []
	}
	connections.append(conn)
	emit_changed()

func disconnect_nodes(from_id: String, from_port: int, to_id: String, to_port: int) -> void:
	var to_remove = -1
	for i in range(connections.size()):
		var c = connections[i]
		if c["from"] == from_id and c["from_port"] == from_port and c["to"] == to_id and c["to_port"] == to_port:
			to_remove = i
			break

	if to_remove != -1:
		connections.remove(to_remove)
		emit_changed()

func get_node_data(id: String) -> Dictionary:
	return nodes.get(id, {})

func clear() -> void:
	nodes.clear()
	connections.clear()
	emit_changed()
