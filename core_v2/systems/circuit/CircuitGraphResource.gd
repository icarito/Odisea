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

func validate() -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	
	var node_ids = nodes.keys()
	var node_set = {}
	for id in node_ids:
		node_set[id] = true
	
	for id in node_ids:
		var n_data = nodes[id]
		var n_type = n_data.get("type", "PROP")
		
		if id == "" or id.find(":") != -1:
			errors.append("Invalid node ID: '%s'" % id)
		
		if n_type == "GATE":
			var gate_type = n_data.get("gate_type", "AND")
			if not gate_type in ["AND", "OR", "XOR", "NOT", "DELAY"]:
				errors.append("Unknown gate type '%s' for node '%s'" % [gate_type, id])
			if gate_type == "DELAY":
				var delay_time = n_data.get("delay_time", 1.0)
				if delay_time <= 0:
					errors.append("DELAY node '%s' has invalid delay_time: %s" % [id, delay_time])
		
		if n_type == "PROP":
			var scene_path = n_data.get("scene_path", NodePath())
			if scene_path.is_empty():
				warnings.append("PROP node '%s' has no scene_path" % id)
	
	for i in range(connections.size()):
		var conn = connections[i]
		var from_id = conn.get("from", "")
		var to_id = conn.get("to", "")
		
		if not node_set.has(from_id):
			errors.append("Connection %d references unknown source node: '%s'" % [i, from_id])
		if not node_set.has(to_id):
			errors.append("Connection %d references unknown target node: '%s'" % [i, to_id])
		
		var conn_type = conn.get("type", "WIRED")
		if not conn_type in ["WIRED", "WIRELESS"]:
			warnings.append("Connection %d has unknown type: '%s'" % [i, conn_type])
	
	var connected_nodes = {}
	for conn in connections:
		var from_id = conn.get("from", "")
		var to_id = conn.get("to", "")
		connected_nodes[from_id] = true
		connected_nodes[to_id] = true
	
	for id in node_ids:
		if not connected_nodes.has(id):
			warnings.append("Node '%s' has no connections" % id)
	
	return {
		"valid": errors.empty(),
		"errors": errors,
		"warnings": warnings,
		"node_count": node_ids.size(),
		"connection_count": connections.size()
	}

func get_node_by_type(type: String) -> Array:
	var result: Array = []
	for id in nodes:
		var n_data = nodes[id]
		if n_data.get("type", "PROP") == type:
			result.append({
				"id": id,
				"data": n_data
			})
	return result

func get_node_by_gate_type(gate_type: String) -> Array:
	var result: Array = []
	for id in nodes:
		var n_data = nodes[id]
		if n_data.get("type", "PROP") == "GATE" and n_data.get("gate_type", "AND") == gate_type:
			result.append({
				"id": id,
				"data": n_data
			})
	return result

func get_connection_path(from_id: String, to_id: String) -> Array:
	var path: Array = []
	var visited = {}
	var queue = [[from_id]]
	
	while not queue.empty():
		var current_path = queue.pop_front()
		var current_id = current_path[current_path.size() - 1]
		
		if current_id == to_id:
			return current_path
		
		if visited.has(current_id):
			continue
		visited[current_id] = true
		
		for conn in connections:
			if conn.get("from", "") == current_id:
				var next_id = conn.get("to", "")
				if not visited.has(next_id):
					var new_path = current_path.duplicate()
					new_path.append(next_id)
					queue.append(new_path)
	
	return path

func get_connected_nodes(node_id: String) -> Array:
	var result: Array = []
	
	for conn in connections:
		if conn.get("from", "") == node_id:
			result.append({
				"node_id": conn.get("to", ""),
				"direction": "output"
			})
		if conn.get("to", "") == node_id:
			result.append({
				"node_id": conn.get("from", ""),
				"direction": "input"
			})
	
	return result
