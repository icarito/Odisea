extends Spatial
class_name SpinRopeSwingV2

# FD-323 Fase 3A — cuerda de swing con selección asistida por mirada.
# Determinista y sólo presentación: no muta la simulación. La visual usa un
# CylinderMesh y se muestra únicamente mientras la cuerda está enganchada.

const EPSILON := 1e-6
const REEL_SPEED := 36.0
const REEL_ACCEL := 55.0
const REEL_MIN_LENGTH := 4.0

export(float) var min_len := 1.0
export(float) var max_len := 60.0
export(float) var rope_radius := 0.04
export(Color) var rope_color := Color(0.75, 0.85, 0.95, 0.9)

var _attached := false
var _anchor := Vector3.ZERO
var rope_length := 0.0
var _visual: MeshInstance = null
var _material: SpatialMaterial = null

# Elige el mejor anclaje dentro de rango y cono. Score = alineación 75% +
# cercanía 25%. Empate determinista: gana el índice más bajo.
static func select_best_anchor(
	origin: Vector3, aim_dir: Vector3, anchors: Array,
	max_range: float = 55.0, cone_deg: float = 38.0
) -> Dictionary:
	var best_index: int = -1
	var best_score: float = -INF
	var best_distance: float = 0.0
	var best_alignment: float = 0.0
	var best_position := Vector3.ZERO

	var aim: Vector3 = aim_dir.normalized()
	if max_range <= 0.0 or aim.length_squared() < EPSILON:
		return {
			"hit": false, "anchor_index": -1, "anchor_position": best_position,
			"distance": 0.0, "alignment": 0.0, "score": best_score
		}

	var min_alignment: float = cos(deg2rad(clamp(cone_deg, 0.0, 180.0)))
	for index in range(anchors.size()):
		var candidate = _anchor_position(anchors[index])
		if typeof(candidate) != TYPE_VECTOR3:
			continue
		var anchor_pos: Vector3 = candidate
		var delta: Vector3 = anchor_pos - origin
		var distance: float = delta.length()
		if distance < EPSILON or distance > max_range:
			continue
		var direction: Vector3 = delta / distance
		var alignment: float = direction.dot(aim)
		if alignment < min_alignment:
			continue
		var score: float = alignment * 0.75 + (1.0 - distance / max_range) * 0.25
		if best_index < 0 or score > best_score:
			best_index = index
			best_score = score
			best_distance = distance
			best_alignment = alignment
			best_position = anchor_pos

	return {
		"hit": best_index >= 0,
		"anchor_index": best_index,
		"anchor_position": best_position,
		"distance": best_distance,
		"alignment": best_alignment,
		"score": best_score
	}

# Fija el anclaje y la longitud de cuerda (clamp entre min_len y max_len).
func attach(anchor_pos: Vector3, player_pos: Vector3) -> float:
	_attached = true
	_anchor = anchor_pos
	var lower: float = max(min_len, 0.01)
	var upper: float = max(max_len, lower)
	rope_length = clamp(anchor_pos.distance_to(player_pos), lower, upper)
	_ensure_visual()
	_update_visual(player_pos)
	return rope_length

func set_rope_length(value: float) -> float:
	var lower: float = max(min_len, 0.01)
	var upper: float = max(max_len, lower)
	rope_length = clamp(value, lower, upper)
	return rope_length

# Retracción determinista de alta velocidad: acorta la cuerda y acelera hacia el
# anclaje. Al soltar RT en plena retracción se conserva la velocidad (catapulta).
static func reel_in(
	pos: Vector3, vel: Vector3, anchor: Vector3, rope_length: float, dt: float,
	reel_speed: float = REEL_SPEED, reel_accel: float = REEL_ACCEL,
	min_length: float = REEL_MIN_LENGTH
) -> Dictionary:
	var delta: Vector3 = anchor - pos
	var distance: float = delta.length()
	var new_length: float = max(max(min_length, 0.0), rope_length - reel_speed * max(dt, 0.0))
	if distance <= EPSILON:
		return {"position": pos, "velocity": vel, "length": new_length, "reeling": true, "taut": true}
	var direction: Vector3 = delta / distance
	var inward: float = max(vel.dot(direction), 0.0)
	var target_speed: float = min(inward + reel_accel * max(dt, 0.0), reel_speed)
	var new_velocity: Vector3 = vel + direction * (target_speed - inward)
	var new_position: Vector3 = anchor - direction * new_length
	return {
		"position": new_position, "velocity": new_velocity,
		"length": new_length, "reeling": true, "taut": distance >= new_length,
	}

func detach() -> void:
	_attached = false
	_anchor = Vector3.ZERO
	rope_length = 0.0
	if is_instance_valid(_visual):
		_visual.visible = false

func is_attached() -> bool:
	return _attached

func get_rope_length() -> float:
	return rope_length

func get_anchor() -> Vector3:
	return _anchor

# Restricción de esfera: si la cuerda está tensa y la velocidad es saliente,
# elimina la componente radial (sin inyectar energía) y proyecta la posición.
static func constrain_swing(
	pos: Vector3, vel: Vector3, anchor: Vector3, rope_length: float
) -> Dictionary:
	var radial: Vector3 = pos - anchor
	var distance: float = radial.length()
	if rope_length <= 0.0 or distance < EPSILON:
		return {
			"position": pos, "velocity": vel, "taut": false,
			"tension_dir": Vector3.ZERO
		}

	var radial_out: Vector3 = radial / distance
	var taut: bool = distance >= rope_length
	var tension_dir: Vector3 = -radial_out if taut else Vector3.ZERO
	if not taut:
		return {
			"position": pos, "velocity": vel, "taut": false,
			"tension_dir": tension_dir
		}

	var outward_speed: float = vel.dot(radial_out)
	if outward_speed <= 0.0:
		return {
			"position": pos, "velocity": vel, "taut": true,
			"tension_dir": tension_dir
		}

	var tangential: Vector3 = vel - radial_out * outward_speed
	return {
		"position": anchor + radial_out * rope_length,
		"velocity": tangential,
		"taut": true,
		"tension_dir": tension_dir
	}

func _ready() -> void:
	_ensure_visual()
	if is_instance_valid(_visual):
		_visual.visible = _attached

func _ensure_visual() -> void:
	if _material == null:
		_material = SpatialMaterial.new()
		_material.flags_unshaded = true
		_material.albedo_color = rope_color
	if _visual == null:
		_visual = MeshInstance.new()
		_visual.name = "RopeVisual"
		var mesh := CylinderMesh.new()
		mesh.height = 1.0
		mesh.top_radius = rope_radius
		mesh.bottom_radius = rope_radius
		mesh.radial_segments = 6
		mesh.rings = 1
		mesh.material = _material
		_visual.mesh = mesh
		_visual.visible = false
		add_child(_visual)

func _update_visual(player_pos: Vector3) -> void:
	if not is_instance_valid(_visual):
		return
	var delta: Vector3 = _anchor - player_pos
	var length: float = delta.length()
	if not _attached or length < EPSILON:
		_visual.visible = false
		return
	var y_axis: Vector3 = delta / length
	var x_axis: Vector3 = y_axis.cross(Vector3(0.0, 0.0, 1.0))
	if x_axis.length_squared() < EPSILON:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	_visual.transform = Transform(
		Basis(x_axis, y_axis * length, z_axis), player_pos + delta * 0.5
	)
	_visual.visible = true

static func _anchor_position(anchor):
	if typeof(anchor) == TYPE_VECTOR3:
		return anchor
	if typeof(anchor) == TYPE_TRANSFORM:
		return anchor.origin
	return null
