extends Reference
# Sin class_name (mismo criterio que FlowMetrics / HoloPolicyController): se consume con preload().
#
# AutopilotInputV2 — autonavegador de Transit-Run. Fuente SINTETICA de input que
# InputProviderV2 aplica sobre el InputDataV2 del frame MIENTRAS el jugador mantiene
# nav_assist (TAB). Recorre la ruta principal (waypoints de FlowRouteValidator).
#
# Contrato:
# - Solo escribe intents (move_vec / sprint / jump). No toca velocidad, transform ni camara:
#   el relevo humano <-> maquina no puede producir saltos de momentum por construccion.
# - Cualquier intent humano de gameplay lo apaga en el MISMO tick; mirar (mouse_delta) no.
# - Corre dentro de get_input() en modo LIVE: su salida queda en el stream grabado y el
#   replay la reproduce sin ejecutar el autopilot.

const FlowMetricsScript := preload("res://core_v2/systems/flow/FlowMetrics.gd")

const HUMAN_DEADZONE := 0.1
const STEP_HEIGHT := 0.4          # igual a PlayerControllerV2.step_height: debajo de esto se camina
const EDGE_PROBE_AHEAD := 0.7
const EDGE_PROBE_DROP := 2.0      # sin suelo a esta profundidad => hueco => saltar
const ARRIVE_HEIGHT_TOL := 0.6
const REACH_MARGIN := 0.9
const STUCK_TICKS := 20
const PLATFORM_INSET := 0.8
const SHORT_PLATFORM := 4.0       # por debajo de este largo hay que frenar en el aire
const FULL_JUMP_RISE := 0.5
const FULL_JUMP_DIST := 4.0
const MIN_PACE := 0.3             # fraccion minima de v_run al regular la cadencia

var enabled := false
var arrive_radius := 1.0

# Opcional: marco curvo (ScaffoldChunkOrbit). Si se asigna, los waypoints estan en el espacio
# plano del registro y el piloto se convierte a ese espacio; solo la direccion de marcha y la
# sonda de borde vuelven al espacio fisico. null = waypoints en coordenadas de mundo.
var frame = null

var _body_ref: WeakRef = null
var _fm = null
var _waypoints := []              # [{position: Vector3, size: Vector3 (opcional)}]
var _index := 0
var _active := false
var _jump_held := false
var _stuck_ticks := 0
var _full_jump := true
var _air_pace := 1.0


func setup(body: KinematicBody) -> void:
	_body_ref = weakref(body)
	_fm = FlowMetricsScript.from_pilot_node(body)


# La gravedad del piloto cambio (secciones del entrecasco): releer sus metricas de alcance.
func refresh_metrics() -> void:
	var body: KinematicBody = _body_ref.get_ref() if _body_ref != null else null
	if body != null:
		_fm = FlowMetricsScript.from_pilot_node(body)


# Acepta Vector3 sueltos o los diccionarios de FlowRouteValidator ("main_waypoints", o nodos
# con "size"). Con size, el punto de mira es el punto mas cercano de la plataforma (ver _aim).
func set_route(points: Array) -> void:
	_waypoints = []
	for p in points:
		if typeof(p) == TYPE_VECTOR3:
			_waypoints.append({"position": p})
		elif typeof(p) == TYPE_DICTIONARY and p.has("position"):
			_waypoints.append(p)
	_index = 0


func is_active() -> bool:
	return _active


func is_finished() -> bool:
	return _index >= _waypoints.size()


# Siguiente waypoint (para el HUD / fantasma); Vector3.INF si no hay ruta pendiente.
func next_waypoint() -> Vector3:
	return _waypoints[_index]["position"] if not is_finished() else Vector3.INF


static func human_is_active(d: InputDataV2) -> bool:
	return d.move_vec.length() > HUMAN_DEADZONE or d.jump or d.sprint or d.crouch \
		or d.interact or d.interact_held or d.focus \
		or d.tool_fire_primary or d.tool_fire_secondary or d.cargol_ability


# `held`: el jugador mantiene la accion nav_assist (TAB). El autonavegador conduce solo
# mientras esta sostenida; soltarla devuelve el control en el mismo tick.
func apply(d: InputDataV2, held: bool) -> void:
	var body: KinematicBody = _body_ref.get_ref() if _body_ref != null else null
	if not enabled or not held or d == null or body == null or is_finished() or human_is_active(d):
		_active = false
		_jump_held = false
		return
	_active = true

	var world_pos: Vector3 = body.global_transform.origin
	var pos: Vector3 = frame.world_to_flat(world_pos) if frame != null else world_pos
	var on_floor: bool = body.is_on_floor()
	var target: Vector3 = _aim(_waypoints[_index], pos)
	var to_target := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	var dist: float = to_target.length()
	var dy: float = target.y - pos.y

	if on_floor and dist <= _arrive_dist(_waypoints[_index]) and abs(dy) <= ARRIVE_HEIGHT_TOL:
		_index += 1
		_stuck_ticks = 0
		if is_finished():
			_active = false
			return
		target = _aim(_waypoints[_index], pos)
		to_target = Vector3(target.x - pos.x, 0.0, target.z - pos.z)
		dist = to_target.length()
		dy = target.y - pos.y

	var lane: Vector3 = _lane_first(pos)
	if lane != Vector3.INF:
		target = lane
		to_target = Vector3(target.x - pos.x, 0.0, target.z - pos.z)
		dist = to_target.length()
		dy = 0.0
	var dir: Vector3 = to_target.normalized() if dist > 0.01 else Vector3.ZERO
	if frame != null:
		dir = frame.flat_dir_to_world(dir)
	var vel: Vector3 = body.get("velocity")
	var h_vel := Vector3(vel.x, 0.0, vel.z)
	var h_speed: float = h_vel.length()
	# En el aire hacia una plataforma corta: frenar activamente a la distancia de frenado del
	# control en aire, para caer sobre el punto de mira y no pasarse de largo.
	var a_air: float = _fm.acceleration * _fm.air_control_multiplier
	if not on_floor and _is_short(_waypoints[_index]) and h_speed > 0.5 \
			and dist <= h_speed * h_speed / (2.0 * a_air) + 0.15:
		d.move_vec = _to_move_vec(body, -h_vel.normalized())
	else:
		# Hacia una plataforma corta se regula la velocidad para que UN toque de salto caiga
		# sobre el punto de mira: cadencia continua en vez de correr a fondo y frenar en seco.
		# Solo de plataforma corta a plataforma corta (ahi hay salto seguro); el ritmo se fija
		# en el suelo y se conserva en el aire: recalcularlo en vuelo lo iria frenando.
		var pace: float = _air_pace
		if on_floor:
			pace = 1.0
			if lane == Vector3.INF and _index > 0 and _is_short(_waypoints[_index]) \
					and _is_short(_waypoints[_index - 1]):
				var air: float = _tap_air_time(dy) if _tap_reaches(dist, dy) else _fm.t_air(-1.0, dy)
				pace = clamp(dist / max(air, 0.1) / _fm.run_speed(), MIN_PACE, 1.0)
			_air_pace = pace
		d.move_vec = _to_move_vec(body, dir) * pace
		d.sprint = true

	if on_floor:
		_jump_held = false
		if _is_short(_waypoints[_index]):
			_full_jump = not _tap_reaches(dist, dy)
		else:
			_full_jump = dy > FULL_JUMP_RISE or dist > FULL_JUMP_DIST
		_stuck_ticks = _stuck_ticks + 1 if h_speed < 0.5 else 0
		var reach: float = max(h_speed, _fm.walk_speed()) * _fm.t_air(-1.0, dy) * REACH_MARGIN
		var climb: bool = dy > STEP_HEIGHT and dist <= reach
		if climb or _stuck_ticks > STUCK_TICKS or _gap_ahead(body, world_pos, dir):
			_jump_held = true
			_stuck_ticks = 0
	elif vel.y <= 0.0 or not _full_jump:
		_jump_held = false
	# Salto completo (sostenido mientras sube) solo si hace falta; si no, un toque.
	d.jump = _jump_held


# Tiempo en el aire de un toque de salto (corte a v_cut tras MIN_JUMP_TIME) que cae `dy` arriba.
func _tap_air_time(dy: float) -> float:
	var g: float = _fm.gravity
	var v_cut: float = _fm.jump_force * _fm.min_jump_intensity
	return _fm.min_jump_time + v_cut / g + sqrt(max(2.0 * (_fm.h_tap() - dy), 0.0) / g)


# Un toque alcanza si no hay que subir y la velocidad que exige queda holgada bajo v_run.
func _tap_reaches(dist: float, dy: float) -> bool:
	return dy <= FULL_JUMP_RISE and dist / max(_tap_air_time(dy), 0.1) <= 0.9 * _fm.run_speed()


# Carril primero: si la plataforma destino empieza mas adelante y la actual llega hasta ahi,
# se avanza recto por la actual y recien entonces se cruza de costado. Cortar en diagonal
# atraviesa lo que haya entre ambas (un mamparo, el canto de una rampa).
# ponytail: asume avance hacia +Z en el marco del registro, igual que _aim.
func _lane_first(pos: Vector3) -> Vector3:
	if _index == 0:
		return Vector3.INF
	var wp: Dictionary = _waypoints[_index]
	var prev: Dictionary = _waypoints[_index - 1]
	if not wp.has("size") or not prev.has("size") or wp.has("rise") or prev.has("rise"):
		return Vector3.INF
	if abs(wp["position"].x - prev["position"].x) < 0.1:
		return Vector3.INF
	var z_in: float = wp["position"].z - max(wp["size"].z * 0.5 - PLATFORM_INSET, 0.0)
	var prev_end: float = prev["position"].z + prev["size"].z * 0.5
	if pos.z < z_in - 0.05 and prev_end >= z_in + 0.2:
		return Vector3(pos.x, pos.y, z_in + 0.2)
	return Vector3.INF


# Con size se exige estar bien adentro de la plataforma (no en el borde); sin size, el radio.
func _arrive_dist(wp: Dictionary) -> float:
	return 0.35 if wp.has("size") and not wp.has("rise") else arrive_radius


func _is_short(wp: Dictionary) -> bool:
	return wp.has("size") and min(wp["size"].x, wp["size"].z) < SHORT_PLATFORM and not wp.has("rise") \
		and wp["size"].z < SHORT_PLATFORM


# ponytail: asume plataformas alineadas a los ejes (size = AABB). En el cilindro de
# ScaffoldOrbit los chunks giran sobre Z: pasar el punto en el marco local del chunk o
# waypoints sin size cuando se cablee alli.
func _aim(wp: Dictionary, pos: Vector3) -> Vector3:
	var c: Vector3 = wp["position"]
	if not wp.has("size"):
		return c
	var s: Vector3 = wp["size"]
	if wp.has("rise"):
		# Rampa (sube `rise` hacia +Z): se apunta a su extremo alto, no al punto mas cercano.
		return Vector3(c.x, c.y + float(wp["rise"]) * 0.5, c.z + s.z * 0.5 - PLATFORM_INSET)
	var hx: float = max(s.x * 0.5 - PLATFORM_INSET, 0.0)
	var hz: float = max(s.z * 0.5 - PLATFORM_INSET, 0.0)
	return Vector3(clamp(pos.x, c.x - hx, c.x + hx), c.y, clamp(pos.z, c.z - hz, c.z + hz))


# move_vec es relativo a la camara (PlayerControllerV2._get_move_direction): se proyecta la
# direccion de mundo sobre la misma base que usara el controlador. La camara no se toca.
func _to_move_vec(body: Node, dir: Vector3) -> Vector2:
	var basis := Basis.IDENTITY
	var cinematic: Node = body.get_node_or_null("/root/CinematicManager")
	if cinematic != null and cinematic.has_method("get_active_camera"):
		var cam = cinematic.get_active_camera()
		if cam != null and is_instance_valid(cam):
			basis = cam.global_transform.basis
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	return Vector2(dir.dot(right), -dir.dot(forward))


func _gap_ahead(body: KinematicBody, pos: Vector3, dir: Vector3) -> bool:
	if dir == Vector3.ZERO:
		return false
	var from: Vector3 = pos + dir * EDGE_PROBE_AHEAD + Vector3(0.0, 0.3, 0.0)
	var hit: Dictionary = body.get_world().direct_space_state.intersect_ray(
		from, from - Vector3(0.0, EDGE_PROBE_DROP + 0.3, 0.0), [body], body.collision_mask)
	return hit.empty()
