extends Node
# /scripts/replay/ReplayUtils.gd

# This script provides utility functions for the replay system,
# specifically for handling data serialization and deserialization.

# Helper function to serialize a Vector3 to a dictionary for JSON optimization.
static func vector3_to_dict(vector: Vector3) -> Dictionary:
	return {"x": vector.x, "y": vector.y, "z": vector.z}

# Helper function to deserialize a dictionary from JSON back to a Vector3.
static func dict_to_vector3(dict: Dictionary) -> Vector3:
	if dict and dict.has_all(["x", "y", "z"]):
		return Vector3(dict.x, dict.y, dict.z)
	# Return Vector3.ZERO if keys are missing or format is incorrect.
	return Vector3.ZERO

# Helper function to serialize a Transform to a dictionary.
static func transform_to_dict(transform: Transform) -> Dictionary:
	return {
		"basis": {
			"x": vector3_to_dict(transform.basis.x),
			"y": vector3_to_dict(transform.basis.y),
			"z": vector3_to_dict(transform.basis.z)
		},
		"origin": vector3_to_dict(transform.origin)
	}

# Helper function to deserialize a dictionary back to a Transform.
static func dict_to_transform(dict: Dictionary) -> Transform:
	if dict and dict.has("basis") and dict.has("origin"):
		var basis_x = dict_to_vector3(dict.basis.x)
		var basis_y = dict_to_vector3(dict.basis.y)
		var basis_z = dict_to_vector3(dict.basis.z)
		var origin = dict_to_vector3(dict.origin)
		return Transform(Basis(basis_x, basis_y, basis_z), origin)
	return Transform.IDENTITY

# Recursive function to convert Godot types to JSON-safe data
static func to_json_safe(data):
	if data is Vector3:
		return {"x": data.x, "y": data.y, "z": data.z}
	elif data is Transform:
		return {
			"basis": {
				"x": vector3_to_dict(data.basis.x),
				"y": vector3_to_dict(data.basis.y),
				"z": vector3_to_dict(data.basis.z)
			},
			"origin": vector3_to_dict(data.origin)
		}
	elif data is Dictionary:
		var result = {}
		for key in data:
			result[key] = to_json_safe(data[key])
		return result
	elif data is Array:
		var result = []
		for item in data:
			result.append(to_json_safe(item))
		return result
	else:
		return data

# Recursive function to convert JSON-safe data back to Godot types
static func from_json_safe(data):
	if data is Array:
		var result = []
		for item in data:
			result.append(from_json_safe(item))
		return result
		
	if not data is Dictionary:
		return data

	# It's a dictionary, check for known Godot types FIRST before recursing.
	# This avoids bugs where child dictionaries (like 'origin') are converted
	# before the parent ('transform') is identified.
	if data.has("basis") and data.has("origin"):
		# It's a Transform, we can use our robust dict_to_transform directly.
		# No need to recurse further.
		return dict_to_transform(data)
	
	if data.has_all(["x", "y", "z"]) and data.size() == 3:
		# It's a Vector3, use dict_to_vector3.
		return dict_to_vector3(data)

	# If it's not a special Godot type, then it's a generic dictionary.
	# Now we can safely recurse on its values.
	var result = {}
	for key in data:
		result[key] = from_json_safe(data[key])
	return result