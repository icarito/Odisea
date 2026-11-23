extends Spatial

# FD-324 F1 - explosion de eyeccion del nucleo al Puente.
#
# Evento determinista en funcion del tiempo de simulacion `t_sim`. La matematica
# de lanzamiento es pura: en el marco rotante de SpinFrame el vuelo libre es una
# recta en el marco inercial, asi que la velocidad inicial se resuelve en forma
# cerrada. Con esa `v0` la trayectoria cae en el Puente (+Z) en una ventana de
# 15-25 s. La explosion pasa al piloto a SPIN_REAL, le inyecta `v0` (vuelo libre
# largo) y el predictor queda habilitado solo fuera del hub, nunca en el idle
# ZERO_G del nucleo. El impacto en el Puente se resuelve como slide grande sin
# muerte: si la velocidad de entrada cae en la banda de tumble, se acota a la
# banda de slide antes de delegar en SpinRealPhysicsV2.handle_landing.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const SpinRealPhysicsV2 = preload("res://core_v2/player/SpinRealPhysicsV2.gd")

const MIN_FLIGHT_TIME := 15.0
const MAX_FLIGHT_TIME := 25.0
const DEFAULT_FLIGHT_TIME := 20.0
const R_HUB := 8.0
const FREE_FLIGHT_MIN_SPEED := 2.0
const DEFAULT_SPIN_V_SLIDE := 26.0
const EPSILON := 1e-6

export(float) var omega := 0.0
export(float) var flight_time := DEFAULT_FLIGHT_TIME
export(Vector3) var bridge_target := Vector3(220.0, 0.0, 920.0)
export(float) var hub_radius := R_HUB

var t_sim := 0.0
var launched := false
var pilot = null
var predictor = null
var launch_state: Dictionary = {}

# --- Matematica pura ---

# Resuelve, por transformacion inercial exacta de SpinFrame, la velocidad inicial
# en el marco rotante para que la recta inercial caiga en `bridge_target` en
# `flight_time` segundos (acotado a [15, 25]).
#   P_I(T) = R(omega*T) * bridge_target = start + V_I * T
#   v0 = V_I - omega x start
static func solve_bridge_launch(
	start_pos: Vector3, bridge_target: Vector3, omega: float,
	flight_time: float = DEFAULT_FLIGHT_TIME
) -> Dictionary:
	var flight: float = clamp(flight_time, MIN_FLIGHT_TIME, MAX_FLIGHT_TIME)
	var distance: float = start_pos.distance_to(bridge_target)
	if flight <= 0.0:
		return {
			"velocity": Vector3.ZERO, "inertial_velocity": Vector3.ZERO,
			"flight_time": flight, "distance": distance,
			"speed": 0.0, "inertial_speed": 0.0, "omega": omega
		}
	var target_inertial: Vector3 = SpinFrame.to_inertial_position(bridge_target, omega, flight)
	var inertial_velocity: Vector3 = (target_inertial - start_pos) / flight
	var omega_axis := Vector3(0.0, 0.0, omega)
	var velocity: Vector3 = inertial_velocity - omega_axis.cross(start_pos)
	return {
		"velocity": velocity,
		"inertial_velocity": inertial_velocity,
		"flight_time": flight,
		"distance": distance,
		"speed": velocity.length(),
		"inertial_speed": inertial_velocity.length(),
		"omega": omega
	}

# El predictor es presentacion pura: solo se muestra en vuelo libre real, ya
# fuera del hub. En el idle ZERO_G del nucleo (sin lanzar) o con el piloto
# apoyado en una superficie queda apagado.
static func should_show_predictor(
	position: Vector3, velocity: Vector3, hub_radius_value: float,
	launched_flag: bool, grounded_flag: bool
) -> bool:
	if not launched_flag or grounded_flag:
		return false
	if velocity.length() < FREE_FLIGHT_MIN_SPEED:
		return false
	# Dentro de la columna axial (r <= hub_radius) sigue siendo el hub.
	return SpinFrame.r_perp(position).length() > max(hub_radius_value, 0.0)

# Velocidad normal de entrada (componente contra `up`), sin tocar la fisica.
static func landing_entry_speed(velocity: Vector3, up: Vector3) -> float:
	var up_dir: Vector3 = up.normalized() if up.length_squared() > EPSILON else Vector3.UP
	return max(0.0, -velocity.dot(up_dir))

# Aterrizaje grande sin muerte: si la entrada cae en la banda de tumble, se acota
# a la banda de slide antes de delegar el handler en SpinRealPhysicsV2.
static func resolve_bridge_landing(
	physics, controller, velocity: Vector3, up: Vector3
) -> Dictionary:
	var entry: float = landing_entry_speed(velocity, up)
	var slide_max: float = DEFAULT_SPIN_V_SLIDE
	if physics != null and physics is Object:
		var raw = physics.get("spin_v_slide")
		if typeof(raw) == TYPE_REAL:
			slide_max = float(raw)
	var applied: float = entry
	if entry >= slide_max:
		applied = max(0.0, slide_max - 0.001)
	var kind: int = 0
	if physics != null and physics.has_method("handle_landing"):
		kind = int(physics.handle_landing(controller, applied))
	return {"entry_speed": entry, "applied_speed": applied, "landing": kind}

# --- Nodo ---

func _ready() -> void:
	if omega <= 0.0:
		omega = SpinFrame.omega_for()

func arm(pilot_node, predictor_node = null) -> void:
	pilot = pilot_node
	predictor = predictor_node

func get_omega() -> float:
	return omega if omega > 0.0 else SpinFrame.omega_for()

func detonate(target_pilot = null) -> Dictionary:
	if target_pilot != null:
		pilot = target_pilot
	if pilot == null or not is_instance_valid(pilot):
		return {}
	var start: Vector3 = pilot.global_transform.origin
	var result: Dictionary = solve_bridge_launch(start, bridge_target, get_omega(), flight_time)
	launch_state = result
	launched = true
	t_sim = 0.0
	# Pasa a SPIN_REAL (opt-in del piloto) e inyecta la velocidad de eyeccion.
	if pilot.has_method("set_spin_real_enabled"):
		pilot.set_spin_real_enabled(true)
	if "velocity" in pilot:
		pilot.set("velocity", result["velocity"])
	if pilot.has_method("set_sim_up"):
		var fallback: Vector3 = Vector3.UP
		if pilot.has_method("get_sim_up"):
			fallback = pilot.get_sim_up()
		pilot.set_sim_up(SpinFrame.up(start, fallback))
	return result

# Alias de gameplay (F7): el loop jugable dispara la explosión automáticamente.
func trigger_explosion(target_pilot = null) -> Dictionary:
	return detonate(target_pilot)

func get_flight_elapsed() -> float:
	return t_sim

# Reinicio instantaneo: rearma el disparo sin recargar la escena.
func reset() -> void:
	launched = false
	t_sim = 0.0
	launch_state = {}
	if predictor != null and is_instance_valid(predictor):
		predictor.visible = false

# Gate de presentacion con el estado vivo del nodo: mismo criterio estatico que
# `_physics_process`, para que el slice no reconstruya grounded/launched.
func should_show_predictor_at(pilot_position: Vector3) -> bool:
	var velocity := Vector3.ZERO
	var physics = null
	if pilot != null and is_instance_valid(pilot):
		if "velocity" in pilot:
			velocity = pilot.velocity
		if pilot.has_method("get_spin_physics"):
			physics = pilot.get_spin_physics()
	var grounded: bool = bool(physics.get("_was_grounded")) if physics != null else false
	return should_show_predictor(pilot_position, velocity, hub_radius, launched, grounded)

func is_free_flight_active() -> bool:
	if not launched or pilot == null or not is_instance_valid(pilot):
		return false
	var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
	var grounded: bool = bool(physics.get("_was_grounded")) if physics != null else false
	var velocity := Vector3.ZERO
	if "velocity" in pilot:
		velocity = pilot.velocity
	return should_show_predictor(
		pilot.global_transform.origin, velocity, hub_radius, launched, grounded
	)

func _physics_process(dt: float) -> void:
	if launched and dt > 0.0:
		t_sim += dt
	if predictor == null or not is_instance_valid(predictor):
		return
	if pilot == null or not is_instance_valid(pilot):
		return
	var physics = pilot.get_spin_physics() if pilot.has_method("get_spin_physics") else null
	var grounded: bool = bool(physics.get("_was_grounded")) if physics != null else false
	var velocity := Vector3.ZERO
	if "velocity" in pilot:
		velocity = pilot.velocity
	# Aun antes de detonar: en el idle ZERO_G dentro del nucleo queda apagado.
	predictor.visible = should_show_predictor(
		pilot.global_transform.origin, velocity, hub_radius, launched, grounded
	)
