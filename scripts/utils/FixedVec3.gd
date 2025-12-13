# FixedVec3.gd - Clase para vectores 3D en punto fijo
# Depende del autoload FixedPoint para operaciones aritméticas.

class FixedVec3:
	var x: int
	var y: int
	var z: int

	func _init(_x: int, _y: int, _z: int):
		x = _x
		y = _y
		z = _z

	func to_vec3() -> Vector3:
		return Vector3(FixedPoint.from_fixed(x), FixedPoint.from_fixed(y), FixedPoint.from_fixed(z))

	static func from_vec3(v: Vector3) -> FixedVec3:
		return FixedVec3.new(FixedPoint.to_fixed(v.x), FixedPoint.to_fixed(v.y), FixedPoint.to_fixed(v.z))

	func add(v: FixedVec3) -> FixedVec3:
		return FixedVec3.new(FixedPoint.fixed_add(x, v.x), FixedPoint.fixed_add(y, v.y), FixedPoint.fixed_add(z, v.z))

	func sub(v: FixedVec3) -> FixedVec3:
		return FixedVec3.new(FixedPoint.fixed_sub(x, v.x), FixedPoint.fixed_sub(y, v.y), FixedPoint.fixed_sub(z, v.z))

	func mul(s: int) -> FixedVec3:
		return FixedVec3.new(FixedPoint.fixed_mul(x, s), FixedPoint.fixed_mul(y, s), FixedPoint.fixed_mul(z, s))

	func div(s: int) -> FixedVec3:
		return FixedVec3.new(FixedPoint.fixed_div(x, s), FixedPoint.fixed_div(y, s), FixedPoint.fixed_div(z, s))

	func length_squared() -> int:
		return FixedPoint.fixed_add(FixedPoint.fixed_add(FixedPoint.fixed_mul(x, x), FixedPoint.fixed_mul(y, y)), FixedPoint.fixed_mul(z, z))

	static func zero() -> FixedVec3:
		return FixedVec3.new(0, 0, 0)