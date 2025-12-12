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