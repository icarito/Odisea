extends Reference
class_name DomeSpiralFieldGeometry

# Helpers puros y deterministas del campo de espirales (FD-321, Fase 0 B).
# Marco canónico: eje del cilindro = Z, origen en el centro de la nave.

const AXIS_Z := Vector3(0.0, 0.0, 1.0)
const EPSILON := 0.000001

static func plate_count_for(spiral: Dictionary) -> int:
	var total_height: float = float(spiral.get("total_height", 8000.0))
	var step: float = max(float(spiral.get("plate_step", 40.0)), 0.001)
	return int(max(2, int(round(total_height / step))))

# z centrado en [-total_height/2, +total_height/2].
# Base ortonormal derecha: z = eje del cilindro, y = normal centrífuga hacia el
# eje (det == +1) y x = y × z.
static func plate_transform(spiral: Dictionary, i: int) -> Transform:
	var count: int = plate_count_for(spiral)
	var index: int = int(clamp(i, 0, count - 1))
	var u: float = float(index) / float(count - 1)
	var radius: float = lerp(
		float(spiral.get("r_min", 220.0)), float(spiral.get("r_max", 260.0)), u
	)
	var total_height: float = float(spiral.get("total_height", 8000.0))
	var step: float = float(spiral.get("plate_step", 40.0))
	var z: float = -0.5 * total_height + float(index) * step
	var turns: float = float(spiral.get("turns", 8.0))
	var phase: float = float(spiral.get("phase", 0.0))
	var theta: float = phase + deg2rad(float(index) * (360.0 * turns) / float(count))
	var origin := Vector3(cos(theta) * radius, sin(theta) * radius, z)
	var up: Vector3 = _radial_up(origin)
	var x_axis: Vector3 = up.cross(AXIS_Z).normalized()
	return Transform(Basis(x_axis, up, AXIS_Z), origin)

static func _radial_up(point: Vector3) -> Vector3:
	var planar := Vector3(point.x, point.y, 0.0)
	if planar.length_squared() < EPSILON:
		return Vector3(-1.0, 0.0, 0.0)
	return -planar.normalized()

# Hasta k placas ordenadas por distancia canónica ascendente.
# Desempate determinista: (spiral_index, plate_index) ascendente.
static func select_closest_plates(configs: Array, ref_pos: Vector3, k: int) -> Array:
	var limit: int = int(max(0, k))
	if limit == 0:
		return []
	var best: Array = []
	for spiral_index in range(configs.size()):
		var spiral: Dictionary = configs[spiral_index]
		for plate_index in range(plate_count_for(spiral)):
			var origin: Vector3 = plate_transform(spiral, plate_index).origin
			_insert_sorted_entry(best, {
				"spiral_index": spiral_index,
				"plate_index": plate_index,
				"distance": origin.distance_to(ref_pos)
			}, limit)
	return best

static func compose_anchors(
	configs: Array, spiral_index: int, plate_index: int, local_anchors: Array
) -> Array:
	if spiral_index < 0 or spiral_index >= configs.size():
		return []
	var base: Transform = plate_transform(configs[spiral_index], plate_index)
	var anchors: Array = []
	for anchor in local_anchors:
		if typeof(anchor) == TYPE_TRANSFORM:
			anchors.append(base * anchor)
	return anchors

static func spoke_anchor(
	configs: Array, spiral_index: int, plate_index: int, local_offset: Vector3
) -> Vector3:
	if spiral_index < 0 or spiral_index >= configs.size():
		return Vector3.ZERO
	return plate_transform(configs[spiral_index], plate_index).xform(local_offset)

static func _insert_sorted_entry(target: Array, entry: Dictionary, limit: int) -> void:
	var insert_at: int = target.size()
	for index in range(target.size()):
		if _entry_less(entry, target[index]):
			insert_at = index
			break
	if insert_at >= limit:
		return
	target.insert(insert_at, entry)
	if target.size() > limit:
		target.resize(limit)

static func _entry_less(a: Dictionary, b: Dictionary) -> bool:
	var distance_a: float = float(a["distance"])
	var distance_b: float = float(b["distance"])
	if abs(distance_a - distance_b) > EPSILON:
		return distance_a < distance_b
	var spiral_a: int = int(a["spiral_index"])
	var spiral_b: int = int(b["spiral_index"])
	if spiral_a != spiral_b:
		return spiral_a < spiral_b
	return int(a["plate_index"]) < int(b["plate_index"])
