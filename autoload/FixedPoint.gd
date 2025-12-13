extends Node

# Utilidades de punto fijo para Godot 3.x

# Provee tipos y funciones para reemplazar operaciones de float en lógica crítica de simulación.
# NOTA: Solo para uso interno en movimiento, colisión y replay determinista.

const FIXED_SHIFT = 16
const FIXED_ONE = 1 << FIXED_SHIFT
const FIXED_MASK = FIXED_ONE - 1

static func to_fixed(f: float) -> int:
	return int(round(f * FIXED_ONE))

static func from_fixed(fi: int) -> float:
	return float(fi) / FIXED_ONE

static func fixed_add(a: int, b: int) -> int:
	return a + b

static func fixed_sub(a: int, b: int) -> int:
	return a - b

static func fixed_mul(a: int, b: int) -> int:
	return int(round(float(a) * float(b) / FIXED_ONE))

static func fixed_div(a: int, b: int) -> int:
	if b == 0:
		return 0
	return int(round(float(a) / float(b) * FIXED_ONE))

static func fixed_clamp(x: int, minv: int, maxv: int) -> int:
	var _min = min(x, maxv)
	if _min < minv:
		return minv
	return _min

static func fixed_lerp(a: int, b: int, t: int) -> int:
	return a + fixed_mul(b - a, t)

