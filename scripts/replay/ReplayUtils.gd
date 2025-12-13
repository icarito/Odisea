extends Node
# /scripts/replay/ReplayUtils.gd

# This script provides utility functions for the replay system,
# specifically for handling data serialization and deserialization.

const FIXED_POINT_SCALE = 65536.0

# Functions for single float conversion
static func float_to_fixed(value: float) -> int:
	return int(round(value * FIXED_POINT_SCALE))

static func fixed_to_float(value: int) -> float:
	return float(value) / FIXED_POINT_SCALE

# --- Vector3 conversion to/from fixed-point ---
static func vector3_to_fixed_dict(vector: Vector3) -> Dictionary:
	return {
		"x": float_to_fixed(vector.x),
		"y": float_to_fixed(vector.y),
		"z": float_to_fixed(vector.z)
	}

static func fixed_dict_to_vector3(dict: Dictionary) -> Vector3:
	if dict and dict.has_all(["x", "y", "z"]) and dict.x != null and dict.y != null and dict.z != null:
		return Vector3(
			fixed_to_float(dict.x),
			fixed_to_float(dict.y),
			fixed_to_float(dict.z)
		)
	return Vector3.ZERO

# --- Basis conversion to/from fixed-point ---
static func basis_to_fixed_dict(basis: Basis) -> Dictionary:
	return {
		"x": vector3_to_fixed_dict(basis.x),
		"y": vector3_to_fixed_dict(basis.y),
		"z": vector3_to_fixed_dict(basis.z)
	}

static func fixed_dict_to_basis(dict: Dictionary) -> Basis:
	if dict and dict.has_all(["x", "y", "z"]) and dict.x != null and dict.y != null and dict.z != null:
		var basis_x = fixed_dict_to_vector3(dict.x)
		var basis_y = fixed_dict_to_vector3(dict.y)
		var basis_z = fixed_dict_to_vector3(dict.z)
		return Basis(basis_x, basis_y, basis_z)
	return Basis.IDENTITY

# Helper function to serialize a Vector3 to a dictionary for JSON optimization.
static func vector3_to_dict(vector: Vector3) -> Dictionary:
	return {"x": vector.x, "y": vector.y, "z": vector.z}

# Helper function to deserialize a dictionary from JSON back to a Vector3.
static func dict_to_vector3(dict: Dictionary) -> Vector3:
	if dict and dict.has_all(["x", "y", "z"]) and dict.x != null and dict.y != null and dict.z != null:
		if typeof(dict.x) in [TYPE_REAL, TYPE_INT] and typeof(dict.y) in [TYPE_REAL, TYPE_INT] and typeof(dict.z) in [TYPE_REAL, TYPE_INT]:
			return Vector3(dict.x, dict.y, dict.z)
	# Return Vector3.ZERO if keys are missing or format is incorrect.
	return Vector3.ZERO

# Helper function to deserialize a dictionary from JSON back to a Vector2.
static func dict_to_vector2(dict: Dictionary) -> Vector2:
	if dict and dict.has_all(["x", "y"]) and dict.x != null and dict.y != null:
		if typeof(dict.x) in [TYPE_REAL, TYPE_INT] and typeof(dict.y) in [TYPE_REAL, TYPE_INT]:
			return Vector2(dict.x, dict.y)
	# Return Vector2.ZERO if keys are missing or format is incorrect.
	return Vector2.ZERO

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
	if dict and dict.has("basis") and dict.has("origin") and dict.basis != null and dict.origin != null:
		var basis_x = dict_to_vector3(dict.basis.x)
		var basis_y = dict_to_vector3(dict.basis.y)
		var basis_z = dict_to_vector3(dict.basis.z)
		var origin = dict_to_vector3(dict.origin)
		return Transform(Basis(basis_x, basis_y, basis_z), origin)
	return Transform.IDENTITY

# Helper function to serialize a Basis to a dictionary.
static func basis_to_dict(basis: Basis) -> Dictionary:
	return {
		"x": vector3_to_dict(basis.x),
		"y": vector3_to_dict(basis.y),
		"z": vector3_to_dict(basis.z)
	}

# Recursive function to convert Godot types to JSON-safe data
static func to_json_safe(data):
	if data is Vector3:
		return {"x": data.x, "y": data.y, "z": data.z}
	elif data is Vector2:
		return {"x": data.x, "y": data.y}
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