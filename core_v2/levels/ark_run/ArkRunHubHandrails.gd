extends Spatial

# FD-324 F1 - pasamanos del nucleo co-rotante (ZERO_G).
#
# El nucleo gira con el marco SpinFrame: en el radio del hub (R_HUB = 8 m) la
# pared se mueve a ~1.6 m/s (omega * R_HUB). En ZERO_G Elias se agarra de un
# pasamanos y su velocidad converge a la del marco rotante con un tiron suave,
# acotado por tick: nunca se teletransporta ni se corta de golpe. Solo se escribe
# velocidad (intencion fisica); la posicion la mueve el controlador con su propia
# fisica, asi que el momentum se conserva hasta donde el limite lo permite.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")

const R_HUB := 8.0
const CORE_HANDRAIL_SPEED := 1.6
const DEFAULT_MAX_CONVERGE_ACCEL := 6.0
const CORE_Z_HALF := 12.0
const EPSILON := 1e-6

export(float) var hub_radius := R_HUB
export(float) var max_converge_accel := DEFAULT_MAX_CONVERGE_ACCEL
export(float) var omega := 0.0

var _grabbed := false
var _target = null

# --- API pura (determinista, testeable headless) ---

# Velocidad tangencial de la pared co-rotante a `radius`: |omega * r|.
static func wall_speed(omega_value: float, radius: float = R_HUB) -> float:
	return abs(omega_value * radius)

# Velocidad del punto del pasamanos en la proyeccion XY de `position`.
static func rail_velocity_at(position: Vector3, omega_value: float) -> Vector3:
	return Vector3(0.0, 0.0, omega_value).cross(SpinFrame.r_perp(position))

# Tiron suave: mueve `current` hacia `target` con aceleracion acotada. El cambio
# por tick nunca supera max_accel * dt; si el delta cabe en ese presupuesto, se
# alcanza el objetivo exacto (sin overshoot ni corte).
static func converge_velocity(
	current: Vector3, target: Vector3, dt: float, max_accel: float
) -> Vector3:
	if dt <= 0.0 or max_accel <= 0.0:
		return current
	var delta: Vector3 = target - current
	var max_delta: float = max_accel * dt
	if delta.length() <= max_delta:
		return target
	return current + delta.normalized() * max_delta

# Zona del nucleo: proyeccion radial dentro del hub y `z` cerca del origen.
static func is_in_core(
	position: Vector3, radius: float = R_HUB, z_half: float = CORE_Z_HALF
) -> bool:
	if abs(position.z) > z_half:
		return false
	return SpinFrame.r_perp(position).length() <= max(radius, 0.0)

# --- Nodo: agarre sobre un controlador ---

func _ready() -> void:
	if omega <= 0.0:
		omega = SpinFrame.omega_for()
	_grabbed = false

func attach_target(target_node) -> void:
	_target = target_node

func grab(target_node = null) -> void:
	if target_node != null:
		_target = target_node
	_grabbed = _target != null and is_instance_valid(_target)

func release() -> void:
	_grabbed = false

func is_grabbed() -> bool:
	return _grabbed

func get_omega() -> float:
	return omega if omega > 0.0 else SpinFrame.omega_for()

func convergence_step(position: Vector3, velocity: Vector3, dt: float) -> Vector3:
	return converge_velocity(
		velocity, rail_velocity_at(position, get_omega()), dt, max_converge_accel
	)

func _physics_process(dt: float) -> void:
	if not _grabbed or _target == null or not is_instance_valid(_target):
		return
	var position: Vector3 = _target.global_transform.origin
	var velocity: Vector3 = _target.velocity
	_target.velocity = convergence_step(position, velocity, dt)
