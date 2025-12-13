# Fixed-point 3D vector class for deterministic physics
# Replaces Vector3 operations in critical simulation code

const FixedPoint = preload("res://autoload/FixedPoint.gd")

var x: int
var y: int
var z: int

func _init(x_val: int = 0, y_val: int = 0, z_val: int = 0):
	x = x_val
	y = y_val
	z = z_val

static func zero():
	return load("res://scripts/FixedVec3.gd").new(0, 0, 0)

static func from_vector3(v: Vector3):
	return load("res://scripts/FixedVec3.gd").new(
		FixedPoint.to_fixed(v.x),
		FixedPoint.to_fixed(v.y),
		FixedPoint.to_fixed(v.z)
	)

static func to_vector3(fv) -> Vector3:
	return Vector3(
		FixedPoint.from_fixed(fv.x),
		FixedPoint.from_fixed(fv.y),
		FixedPoint.from_fixed(fv.z)
	)

static func add(a, b):
	var FixedVec3Class = load("res://scripts/FixedVec3.gd")
	return FixedVec3Class.new(
		FixedPoint.fixed_add(a.x, b.x),
		FixedPoint.fixed_add(a.y, b.y),
		FixedPoint.fixed_add(a.z, b.z)
	)

static func mul_scalar(v, s: int):
	var FixedVec3Class = load("res://scripts/FixedVec3.gd")
	return FixedVec3Class.new(
		FixedPoint.fixed_mul(v.x, s),
		FixedPoint.fixed_mul(v.y, s),
		FixedPoint.fixed_mul(v.z, s)
	)

static func lerp(a, b, t: int):
	var FixedVec3Class = load("res://scripts/FixedVec3.gd")
	return FixedVec3Class.new(
		FixedPoint.fixed_lerp(a.x, b.x, t),
		FixedPoint.fixed_lerp(a.y, b.y, t),
		FixedPoint.fixed_lerp(a.z, b.z, t)
	)
