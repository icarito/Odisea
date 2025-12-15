extends Node

# FVec3.gd - Utilidades para vectores 3D en punto fijo
# Usa diccionarios para evitar problemas de memoria

static func zero() -> Dictionary:
	return {"x": 0, "y": 0, "z": 0}

static func from_vec3(v: Vector3) -> Dictionary:
	return {
		"x": FixedPoint.to_fixed(v.x),
		"y": FixedPoint.to_fixed(v.y),
		"z": FixedPoint.to_fixed(v.z)
	}

static func to_vec3(d: Dictionary) -> Vector3:
	return Vector3(
		FixedPoint.from_fixed(d.x),
		FixedPoint.from_fixed(d.y),
		FixedPoint.from_fixed(d.z)
	)

static func add(a: Dictionary, b: Dictionary) -> Dictionary:
	return {
		"x": FixedPoint.fixed_add(a.x, b.x),
		"y": FixedPoint.fixed_add(a.y, b.y),
		"z": FixedPoint.fixed_add(a.z, b.z)
	}

static func sub(a: Dictionary, b: Dictionary) -> Dictionary:
	return {
		"x": FixedPoint.fixed_sub(a.x, b.x),
		"y": FixedPoint.fixed_sub(a.y, b.y),
		"z": FixedPoint.fixed_sub(a.z, b.z)
	}

static func mul(a: Dictionary, s: int) -> Dictionary:
	return {
		"x": FixedPoint.fixed_mul(a.x, s),
		"y": FixedPoint.fixed_mul(a.y, s),
		"z": FixedPoint.fixed_mul(a.z, s)
	}

static func div(a: Dictionary, s: int) -> Dictionary:
	return {
		"x": FixedPoint.fixed_div(a.x, s),
		"y": FixedPoint.fixed_div(a.y, s),
		"z": FixedPoint.fixed_div(a.z, s)
	}

static func mul_scalar(v: Dictionary, s: int) -> Dictionary:
	return {
		"x": FixedPoint.fixed_mul(v.x, s),
		"y": FixedPoint.fixed_mul(v.y, s),
		"z": FixedPoint.fixed_mul(v.z, s)
	}

static func lerp(a: Dictionary, b: Dictionary, t: int) -> Dictionary:
	return {
		"x": FixedPoint.fixed_lerp(a.x, b.x, t),
		"y": FixedPoint.fixed_lerp(a.y, b.y, t),
		"z": FixedPoint.fixed_lerp(a.z, b.z, t)
	}

static func length_squared(v: Dictionary) -> int:
	return FixedPoint.fixed_add(
		FixedPoint.fixed_add(
			FixedPoint.fixed_mul(v.x, v.x),
			FixedPoint.fixed_mul(v.y, v.y)
		),
		FixedPoint.fixed_mul(v.z, v.z)
	)