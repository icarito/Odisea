extends Reference
# Sin class_name (mismo criterio que FlowMetrics / HoloPolicyController): se consume con preload().
#
# AutopilotInputV2 — modo asistido ("lazy") de Transit-Run. Fuente SINTETICA de input que
# InputProviderV2 aplica sobre el InputDataV2 del frame cuando el humano lleva idle_seconds
# sin tocar los controles. Recorre la ruta principal (waypoints de FlowRouteValidator).
#
# Contrato:
# - Solo escribe intents (move_vec / sprint / jump). No toca velocidad, transform ni camara:
#   el relevo humano <-> maquina no puede producir saltos de momentum por construccion.
# - Cualquier intent humano de gameplay lo apaga en el MISMO tick; mirar (mouse_delta) no.
# - Corre dentro de get_input() en modo LIVE: su salida queda en el stream grabado y el
#   replay la reproduce sin ejecutar el autopilot. El idle se cuenta en ticks, no en reloj.

const FlowMetricsScript := preload("res://core_v2/systems/flow/FlowMetrics.gd")

const HUMAN_DEADZONE := 0.1
const STEP_HEIGHT := 0.4          # igual a PlayerControllerV2.step_height: debajo de esto se camina
const EDGE_PROBE_AHEAD := 0.7
const EDGE_PROBE_DROP := 2.0      # sin suelo a esta profundidad => hueco => saltar
const AIR_BRAKE_RADIUS := 0.7
const ARRIVE_HEIGHT_TOL := 0.6
const REACH_MARGIN := 0.9
const STUCK_TICKS := 20
const PLATFORM_INSET := 0.8

var enabled := false
var idle_seconds := 0.5
var arrive_radius := 1.0

var _body_ref: WeakRef = null
var _fm = null
var _waypoints := []              # [{position: Vector3, size: Vector3 (opcional)}]
var _index := 0
var _idle_ticks := 0
var _active := false
var _jump_held := false
var _stuck_ticks := 0


func setup(body: KinematicBody) -> void:
	_body_ref = weakref(body)
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


func apply(d: InputDataV2) -> void:
	var body: KinematicBody = _body_ref.get_ref() if _body_ref != null else null
	if not enabled or d == null or body == null or is_finished() or human_is_active(d):
		_idle_ticks = 0
		_active = false
		_jump_held = false
		return
	_idle_ticks += 1
	if _idle_ticks < int(idle_seconds * float(Engine.iterations_per_second)):
		return
	_active = true

	var pos: Vector3 = body.global_transform.origin
	var on_floor: bool = body.is_on_floor()
	var target: Vector3 = _aim(_waypoints[_index], pos)
	var to_target := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	var dist: float = to_target.length()
	var dy: float = target.y - pos.y

	if on_floor and dist <= arrive_radius and abs(dy) <= ARRIVE_HEIGHT_TOL:
		_index += 1
		_stuck_ticks = 0
		if is_finished():
			_active = false
			return
		target = _aim(_waypoints[_index], pos)
		to_target = Vector3(target.x - pos.x, 0.0, target.z - pos.z)
		dist = to_target.length()
		dy = target.y - pos.y

	var dir: Vector3 = to_target.normalized() if dist > 0.01 else Vector3.ZERO
	# En el aire, ya encima del destino: soltar para no pasarse (el control en aire frena solo).
	if on_floor or dist > AIR_BRAKE_RADIUS:
		d.move_vec = _to_move_vec(body, dir)
		d.sprint = true

	var vel: Vector3 = body.get("velocity")
	var h_speed: float = Vector2(vel.x, vel.z).length()
	if on_floor:
		_jump_held = false
		_stuck_ticks = _stuck_ticks + 1 if h_speed < 0.5 else 0
		var reach: float = max(h_speed, _fm.walk_speed()) * _fm.t_air(-1.0, dy) * REACH_MARGIN
		var climb: bool = dy > STEP_HEIGHT and dist <= reach
		if climb or _stuck_ticks > STUCK_TICKS or _gap_ahead(body, pos, dir):
			_jump_held = true
			_stuck_ticks = 0
	elif vel.y <= 0.0:
		_jump_held = false
	# Sostenido mientras sube: salto completo (v0), que es el que asume t_air().
	d.jump = _jump_held


# ponytail: asume plataformas alineadas a los ejes (size = AABB). En el cilindro de
# ScaffoldOrbit los chunks giran sobre Z: pasar el punto en el marco local del chunk o
# waypoints sin size cuando se cablee alli.
func _aim(wp: Dictionary, pos: Vector3) -> Vector3:
	var c: Vector3 = wp["position"]
	if not wp.has("size"):
		return c
	var s: Vector3 = wp["size"]
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
