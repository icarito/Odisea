extends Spatial

# Andador de carga: IK analitica de 2 huesos por pierna + marcha procedural.
# Determinista: toda la simulacion vive en _physics_process, sin azar, y el
# estado completo viaja en el snapshot (contrato de replay 5.3).
#
# Jerarquia esperada (generada por tools/build_wct_rig.gd):
#   LegsJoined/Rig/{Body, HipL->KneeL->(ShinL, FootL), HipR->...}
# Las articulaciones rotan sobre el eje X: el mecanismo de cada pierna es
# planar en (Y,Z) con los desfases X de cada segmento constantes. La rodilla
# dobla hacia -Z del modelo (hacia atras), el pie queda nivelado.

const STANCE_PHASE := 0.5

export(bool) var walking := true  # si camina o sostiene la pose de reposo
export(float, 0.0, 4.0) var walk_speed := 0.7  # avance sobre el piso en m/s
export(float, 0.4, 4.0) var cycle_time := 1.5  # duracion del ciclo de paso en s (paso mas largo = andar pesado)
export(float, 0.0, 1.5) var step_height := 0.25  # altura del arco de swing en m
export(float, 0.0, 1.0) var crouch_m := 0.35  # agachado del cuerpo al caminar (m)
export(float, 0.0, 0.5) var bob_m := 0.06  # oscilacion vertical de la plataforma al caminar (m)
export(float, 0.0, 3.0) var knee_bend := 1.0  # cuanto dobla el perno con el alcance (0 = triangulo rigido)
export var forward_local := Vector3(0, 0, 1)  # avance en espacio local del rig

var _time := 0.0
var _rig: Spatial
var _legs := []
var _forward := Vector3(0, 0, 1)
var _units_per_m := 1.0

func _ready() -> void:
	add_to_group("replay_sync")
	_rig = find_node("Rig", true, false)
	_forward = forward_local.normalized()
	_units_per_m = 1.0 / max(0.000001, _rig.global_transform.basis.get_scale().y)
	for s in ["L", "R"]:
		var hip: Spatial = _rig.get_node("Hip" + s)
		var knee: Spatial = hip.get_node("Knee" + s)
		var shin: Spatial = knee.get_node("Shin" + s)
		var foot: Spatial = shin.get_node("Foot" + s)
		# los tres huesos, cada uno relativo a su padre:
		#   rest1 = perno - eje de cadera (el muslo)
		#   rest2 = gota - perno (la canilla)
		#   rest3 = tobillo - gota (la pata baja)
		var rest1_2d := Vector2(knee.translation.y, knee.translation.z)
		var rest2_2d := Vector2(shin.translation.y, shin.translation.z)
		var rest3_2d := Vector2(foot.translation.y, foot.translation.z)
		var rest_ankle_2d := Vector2(hip.translation.y, hip.translation.z) + rest1_2d + rest2_2d + rest3_2d
		var h2 := Vector2(hip.translation.y, hip.translation.z)
		_legs.append({
			"hip": hip, "knee": knee, "shin": shin, "foot": foot,
			"rest1_2d": rest1_2d,
			"rest2_2d": rest2_2d,
			"rest3_2d": rest3_2d,
			"l_shin": rest3_2d.length(),
			"h2": h2,
			"d_rest": (rest_ankle_2d - h2).length(),
			"rest_target_2d": rest_ankle_2d,
			"planted": foot.global_transform.origin,
			"swing_from": foot.global_transform.origin,
			"offset": 0.0 if s == "L" else 0.5,
			"phase_prev": 0.0 if s == "L" else 0.5,
		})

func _physics_process(delta: float) -> void:
	var fw := (global_transform.basis * forward_local).normalized()
	var phase_l := fmod(_time / cycle_time, 1.0)
	if walking:
		_time += delta
		global_transform.origin += fw * walk_speed * delta
		# agachado + bob: baja el cuerpo y oscila con cada paso
		var bob := -bob_m * _units_per_m * (0.5 - 0.5 * cos(4.0 * PI * phase_l))
		_rig.position.y = -crouch_m * _units_per_m + bob
	else:
		_rig.position.y = 0.0
	var stride := walk_speed * cycle_time
	for leg in _legs:
		_solve_leg(leg, _foot_target(leg, stride, fw))

func _foot_target(leg: Dictionary, stride: float, fw: Vector3) -> Vector2:
	if not walking:
		return leg.rest_target_2d
	var phase := fmod(_time / cycle_time + leg.offset, 1.0)
	_gait_transitions(leg, phase, stride, fw)
	if phase < STANCE_PHASE:
		var stance_local: Vector3 = _to_local(leg.planted)
		return Vector2(stance_local.y, stance_local.z)
	var sp: float = (phase - STANCE_PHASE) / STANCE_PHASE
	var sp_smooth: float = sp - sin(sp * TAU) / TAU
	var pos: Vector3 = leg.swing_from.linear_interpolate(leg.planted, sp_smooth)
	pos.y = leg.planted.y + step_height * sin(sp * PI)
	var swing_local: Vector3 = _to_local(pos)
	return Vector2(swing_local.y, swing_local.z)

# Maquina de estados del paso: al iniciar el swing se re-plantan los pies
# stride adelante (antes quedaban clavados en el punto del _ready para
# siempre y el cuerpo se alejaba estirando las patas tras el clamp).
func _gait_transitions(leg: Dictionary, phase: float, stride: float, fw: Vector3) -> void:
	var prev: float = leg.phase_prev
	if prev < STANCE_PHASE and phase >= STANCE_PHASE:
		leg.swing_from = leg.planted
		leg.planted = leg.planted + fw * stride
	elif prev > phase:
		leg.phase_prev = 0.0
	leg.phase_prev = phase

func _solve_leg(leg: Dictionary, target_2d: Vector2) -> void:
	var h2: Vector2 = leg.h2
	var k2off: Vector2 = leg.rest1_2d   # el perno, relativo al eje de cadera
	var k3off: Vector2 = leg.rest2_2d   # la gota, relativa al perno
	var aoff: Vector2 = leg.rest3_2d    # el tobillo, relativo a la gota
	var l_shin: float = leg.l_shin

	var d_vec := target_2d - h2
	var reach: float = d_vec.length()

	# 1. el perno (la primera rodilla, invertida) dobla con el alcance que se
	#    le pide a la pierna: al estirarse se despliega, al comprimirse se
	#    pliega. Sin esto los huesos 1 y 2 forman un triangulo rigido y la
	#    cadena degenera en dos huesos.
	var knee_a: float = clamp(-knee_bend * (reach - leg.d_rest) / l_shin, -1.2, 1.2)
	# el hueso virtual cadera -> gota, ya doblado por el perno
	var upper: Vector2 = k2off + _rot2d(k3off, knee_a)
	var l_upper: float = upper.length()

	# 2. el 2-huesos sobre (hueso virtual, canilla): coloca la gota
	var d: float = clamp(reach, abs(l_upper - l_shin) + 1.0, (l_upper + l_shin) * 0.999)
	var dir := d_vec.normalized()
	var cos_a: float = (l_upper * l_upper + d * d - l_shin * l_shin) / (2.0 * l_upper * d)
	var a: float = acos(clamp(cos_a, -1.0, 1.0))
	var k3_dir: Vector2 = _rot2d(dir, a)
	var k3_pos: Vector2 = h2 + k3_dir * l_upper

	# 3. las tres rotaciones + el tobillo que nivela el ski
	var hip: Spatial = leg.hip
	hip.rotation.x = _signed_angle(upper, k3_dir)
	leg.knee.rotation.x = knee_a
	var shin_dir: Vector2 = (target_2d - k3_pos).normalized()
	leg.shin.rotation.x = _signed_angle(aoff, shin_dir) - (hip.rotation.x + knee_a)
	leg.foot.rotation.x = -(hip.rotation.x + knee_a + leg.shin.rotation.x)

func _rot2d(v: Vector2, a: float) -> Vector2:
	return Vector2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a))

func _signed_angle(rest: Vector2, desired: Vector2) -> float:
	var cross: float = rest.x * desired.y - rest.y * desired.x
	var dot: float = rest.dot(desired)
	return atan2(cross, dot)

func _to_local(world: Vector3) -> Vector3:
	return _rig.global_transform.affine_inverse() * world

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
