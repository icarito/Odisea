extends Node

func get_node_state(node: Node) -> Dictionary:
	if node.has_method("get_replay_state"):
		return node.get_replay_state()
	else:
		var state = {}
		if node is Spatial:
			state["global_transform"] = to_json_safe(node.global_transform)
		# Add more properties as needed for different node types
		return state

func to_json_safe(value):
	if value is Transform:
		return {
			"basis": {
				"x": to_json_safe(value.basis.x),
				"y": to_json_safe(value.basis.y),
				"z": to_json_safe(value.basis.z)
			},
			"origin": to_json_safe(value.origin)
		}
	elif value is Basis:
		return {
			"x": to_json_safe(value.x),
			"y": to_json_safe(value.y),
			"z": to_json_safe(value.z)
		}
	elif value is Vector3: # Check for NaN/INF in each component
		return {"x": value.x if not is_nan(value.x) and not is_inf(value.x) else 0.0, "y": value.y if not is_nan(value.y) and not is_inf(value.y) else 0.0, "z": value.z if not is_nan(value.z) and not is_inf(value.z) else 0.0}
	elif value is Vector2: # Check for NaN/INF in each component
		return {"x": value.x if not is_nan(value.x) and not is_inf(value.x) else 0.0, "y": value.y if not is_nan(value.y) and not is_inf(value.y) else 0.0}
	elif value is float: # Check for NaN/INF
		return value if not is_nan(value) and not is_inf(value) else 0.0
	elif value is int or value is bool or value is String:
		return value
	elif typeof(value) == TYPE_DICTIONARY:
		# Recursively make a dictionary JSON-safe
		var safe_dict = {}
		for k in value:
			safe_dict[k] = to_json_safe(value[k])
		return safe_dict
	else:
		# Fallback for other types
		return str(value)

func from_json_safe(value):
	if typeof(value) == TYPE_DICTIONARY:
		# Order is important: check for more complex types first.
		if value.has("basis") and value.has("origin"):
			# Transform
			var basis = from_json_safe(value.basis)
			var origin = from_json_safe(value.origin)
			return Transform(basis, origin)
		elif value.has("x") and value.has("y") and value.has("z") and value.x is Dictionary:
			# Basis - its components are dictionaries representing Vector3
			return Basis(
				from_json_safe(value.x),
				from_json_safe(value.y),
				from_json_safe(value.z)
			)
		elif value.has("x") and value.has("y") and value.has("z"):
			# Vector3 - Recursively convert components before constructing
			return Vector3(value.x, value.y, value.z)
		elif value.has("x") and value.has("y") and not value.has("z"):
			# Vector2 - Recursively convert components before constructing
			return Vector2(value.x, value.y)
		else:
			# For other dicts, recursively convert values
			var new_dict = {}
			for k in value:
				new_dict[k] = from_json_safe(value[k])
			return new_dict
	return value
