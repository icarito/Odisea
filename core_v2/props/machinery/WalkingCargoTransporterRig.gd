extends Spatial

# Andador de carga: IK analitica de 2 huesos por pierna + marcha procedural.
# Determinista: toda la simulacion vive en _physics_process, sin azar, y el
# estado completo viaja en el snapshot (contrato de replay 5.3).
#
# Jerarquia esperada (generada por tools/build_wct_rig.gd):
#   LegsJoined/Rig/{Body, HipL->KneeL->(ShinL, FootL), HipR->...}
# Las articulaciones rotan sobre el eje X: el mecanismo de cada pierna es
# planar en (Y,Z) con los desfases X de cada segmento constantes. La rodilla
# apunta hacia +Z del modelo (pierna digitigrada).

const STANCE_PHASE := 0.5

export(bool) var walking := true  # si camina o sostiene la pose de reposo
export(float, 0.0, 4.0) var walk_speed := 0.8  # avance sobre el piso en m/s
export(float, 0.4, 4.0) var cycle_time := 2.0  # duracion del ciclo de paso en s
export(float, 0.0, 1.5) var step_height := 0.3  # altura del arco de swing en m
export var forward_local := Vector3(0, 0, 1)  # avance en espacio local del rig

var _time := 0.0
var _rig: Spatial
var _legs := []
var _forward := Vector3(0, 0, 1)

func _ready() -> void:
	add_to_group("replay_sync")
	_rig = find_node("Rig", true, false)
	_forward = forward_local.normalized()
	for s in ["L", "R"]:
		var hip: Spatial = _rig.get_node("Hip" + s)
		var knee: Spatial = hip.get_node("Knee" + s)
		var foot: Spatial = knee.get_node("Foot" + s)
		var rest1_2d := Vector2(knee.translation.y, knee.translation.z)
		var rest2_2d := Vector2(foot.translation.y, foot.translation.z)
		var rest_ankle_2d := Vector2(hip.translation.y, hip.translation.z) + rest1_2d + rest2_2d
		_legs.append({
			"hip": hip, "knee": knee, "foot": foot,
			"l1": rest1_2d.length(),
			"l2": rest2_2d.length(),
			"rest1_2d": rest1_2d,
			"rest2_2d": rest2_2d,
			"h2": Vector2(hip.translation.y, hip.translation.z),
			"rest_target_2d": rest_ankle_2d,
			"planted": foot.global_transform.origin,
			"swing_from": foot.global_transform.origin,
			"offset": 0.0 if s == "L" else 0.5,
		})

func _physics_process(delta: float) -> void:
	var fw := (global_transform.basis * forward_local).normalized()
	if walking:
		_time += delta
		global_transform.origin += fw * walk_speed * delta
	var stride := walk_speed * cycle_time
	for leg in _legs:
		_solve_leg(leg, _foot_target(leg, stride, fw))

func _foot_target(leg: Dictionary, stride: float, fw: Vector3) -> Vector2:
	if not walking:
		return leg.rest_target_2d
	var phase := fmod(_time / cycle_time + leg.offset, 1.0)
	if phase < STANCE_PHASE:
		return Vector2(leg.planted.y, leg.planted.z)
	var sp: float = (phase - STANCE_PHASE) / STANCE_PHASE
	var swing_to: Vector3 = leg.swing_from + fw * stride
	var pos: Vector3 = leg.swing_from.linear_interpolate(swing_to, sp)
	pos.y = leg.planted.y + step_height * sin(sp * PI)
	return Vector2(pos.y, pos.z)

func _solve_leg(leg: Dictionary, target_2d: Vector2) -> void:
	var h2: Vector2 = leg.h2
	var d_vec := target_2d - h2
	var d: float = clamp(d_vec.length(), abs(leg.l1 - leg.l2) + 1.0, (leg.l1 + leg.l2) * 0.999)
	var dir := d_vec.normalized()
	var cos_a: float = (leg.l1 * leg.l1 + d * d - leg.l2 * leg.l2) / (2.0 * leg.l1 * d)
	var a: float = acos(clamp(cos_a, -1.0, 1.0))
	var knee2d: Vector2 = h2 + _rot2d(dir, -a) * leg.l1

	var hip: Spatial = leg.hip
	var knee: Spatial = leg.knee
	var foot: Spatial = leg.foot
	hip.rotation.x = -_signed_angle(leg.rest1_2d, knee2d - h2)
	var dir_shin := (target_2d - knee2d).normalized()
	knee.rotation.x = -_signed_angle(leg.rest2_2d, dir_shin) - hip.rotation.x
	foot.rotation.x = -(hip.rotation.x + knee.rotation.x)

func _rot2d(v: Vector2, a: float) -> Vector2:
	return Vector2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a))

func _signed_angle(rest: Vector2, desired: Vector2) -> float:
	var cross: float = rest.x * desired.y - rest.y * desired.x
	var dot: float = rest.dot(desired)
	return atan2(cross, dot)

# ---- snapshot (replay) ----

func get_snapshot() -> Dictionary:
	var planted := []
	var swings := []
	for leg in _legs:
		planted.append([leg.planted.x, leg.planted.y, leg.planted.z])
		swings.append([leg.swing_from.x, leg.swing_from.y, leg.swing_from.z])
	return {
		"time": _time,
		"origin": [global_transform.origin.x, global_transform.origin.y, global_transform.origin.z],
		"planted": planted,
		"swing_from": swings,
	}

func restore_snapshot(data: Dictionary) -> void:
	_time = float(data.time)
	global_transform.origin = Vector3(data.origin[0], data.origin[1], data.origin[2])
	for i in range(_legs.size()):
		var p: Array = data.planted[i]
		var s: Array = data.swing_from[i]
		_legs[i].planted = Vector3(p[0], p[1], p[2])
		_legs[i].swing_from = Vector3(s[0], s[1], s[2])
