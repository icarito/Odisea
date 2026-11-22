extends Spatial
class_name SpinSpokeV2

# FD-323 Fase 3A — spoke radial co-rotante entre una placa del domo y el hub.
# FD-324 F2 — el mecanismo principal es el ascensor radial determinista
# (SpinRadialElevatorV2, 6 m/s + 3 s por extremo, posición = f(t_sim)). La
# escalera LadderV2 queda como superficie de respaldo y la subida radial real se
# hace con step_backup_ladder() SOLO en SPIN_REAL y SOLO si el ascensor falló,
# avanzando a lo largo de `radial_up` (nunca del Vector3.UP fijo de LadderV2).
# El eje local Y apunta hacia el eje Z.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const LADDER_SCRIPT = preload("res://core_v2/components/LadderV2.gd")
const ELEVATOR_SCRIPT = preload("res://core_v2/components/SpinRadialElevatorV2.gd")
const EPSILON := 1e-6
const BACKUP_CLIMB_SPEED := 2.0

var hub_radius := 8.0
var _configured := false
var _plate_origin := Vector3.ZERO
var _hub_origin := Vector3.ZERO
var _radial_dir := Vector3.RIGHT
var _plate_radius := 0.0
var _radial_length := 0.0
var _ladder: StaticBody = null
var _elevator: KinematicBody = null

# g radial en el marco rotante: omega^2 * |r_perp|. Baja linealmente a 0 en el eje.
static func radial_gravity_at(pos: Vector3, omega: float) -> float:
	return omega * omega * SpinFrame.r_perp(pos).length()

# Coriolis lateral al subir por el spoke: ~0.8 m/s^2 con 2 m/s y omega de diseño.
static func lateral_coriolis_accel(
	climb_speed: float, radial_up: Vector3, omega: float
) -> Vector3:
	return SpinFrame.a_coriolis(radial_up * climb_speed, omega)

# Construye el spoke desde la placa: mismo z/theta, desde R hasta hub_radius.
func configure_from_plate(plate_xform: Transform, p_hub_radius: float = 8.0) -> void:
	hub_radius = max(p_hub_radius, 0.0)
	var plate_origin: Vector3 = plate_xform.origin
	var radial: Vector3 = SpinFrame.r_perp(plate_origin)
	var plate_radius: float = radial.length()

	_configured = false
	if plate_radius <= hub_radius + EPSILON:
		_remove_ladder()
		_remove_elevator()
		return

	var radial_dir: Vector3 = radial / plate_radius
	var inward: Vector3 = -radial_dir
	var hub_origin: Vector3 = radial_dir * hub_radius + Vector3(0.0, 0.0, plate_origin.z)
	var x_axis := Vector3(0.0, 0.0, 1.0)
	var z_axis: Vector3 = x_axis.cross(inward).normalized()
	if z_axis.length_squared() < EPSILON:
		z_axis = Vector3.RIGHT

	transform = Transform(
		Basis(x_axis, inward, z_axis), (plate_origin + hub_origin) * 0.5
	)
	_plate_origin = plate_origin
	_hub_origin = hub_origin
	_radial_dir = radial_dir
	_plate_radius = plate_radius
	_radial_length = plate_radius - hub_radius
	_configured = true
	_ensure_ladder()
	_ensure_elevator(plate_xform)

func is_configured() -> bool:
	return _configured

func get_plate_origin() -> Vector3:
	return _plate_origin

func get_hub_origin() -> Vector3:
	return _hub_origin

func get_radial_length() -> float:
	return _radial_length

func get_ladder() -> StaticBody:
	return _ladder

func get_elevator() -> KinematicBody:
	return _elevator

func is_elevator_operational() -> bool:
	return _elevator != null and is_instance_valid(_elevator) and _elevator.is_operational()

func set_elevator_operational(ok: bool) -> void:
	if _elevator != null and is_instance_valid(_elevator):
		_elevator.set_operational(ok)

# Ascensor por defecto: posición pura de `t_sim`; el Pilot lo sigue por tracking.
func step_elevator(t_sim: float) -> Dictionary:
	if _elevator == null or not is_instance_valid(_elevator):
		return {"r": 0.0, "velocity_r": 0.0, "phase": "", "operational": false, "moved": false}
	return _elevator.step_elevator(t_sim)

# "Arriba" radial del spoke: hacia el eje (opuesto a la gravedad centrífuga).
func radial_up() -> Vector3:
	return -_radial_dir

# Respaldo en SPIN_REAL: subida explícita a lo largo de `radial_up` (no del
# Vector3.UP fijo de LadderV2). Solo actúa si el ascensor falló y el Pilot está
# en SPIN_REAL. `climb_input` en [-1, 1]; positivo sube hacia el hub.
func step_backup_ladder(pilot, climb_input: float, dt: float) -> Dictionary:
	var up: Vector3 = radial_up()
	var result := {
		"moved": false, "distance": 0.0, "position": Vector3.ZERO,
		"up": up, "radius": 0.0, "blocked": true
	}
	if pilot == null or not is_instance_valid(pilot) or dt <= 0.0:
		return result
	if _elevator == null or not is_instance_valid(_elevator) or _elevator.is_operational():
		return result
	if not pilot.has_method("is_spin_real_active") or not bool(pilot.is_spin_real_active()):
		return result

	var position: Vector3 = pilot.global_transform.origin
	var radial: Vector3 = SpinFrame.r_perp(position)
	var distance: float = radial.length()
	var radial_unit: Vector3 = radial / distance if distance > EPSILON else _radial_dir
	var amount: float = clamp(climb_input, -1.0, 1.0) * BACKUP_CLIMB_SPEED * dt
	var low: float = min(hub_radius, _plate_radius)
	var high: float = max(hub_radius, _plate_radius)
	var target_radius: float = clamp(distance - amount, low, high)
	var target := radial_unit * target_radius + Vector3(0.0, 0.0, position.z)
	pilot.global_transform.origin = target
	var actual: float = distance - target_radius
	if "velocity" in pilot:
		pilot.velocity = up * (actual / dt)
	if pilot.has_method("set_sim_up"):
		pilot.set_sim_up(up)
	result["moved"] = abs(actual) > EPSILON
	result["distance"] = actual
	result["position"] = target
	result["radius"] = target_radius
	result["blocked"] = abs(actual) <= EPSILON
	return result

func _ensure_ladder() -> void:
	if _ladder == null or not is_instance_valid(_ladder):
		_ladder = LADDER_SCRIPT.new()
		_ladder.name = "SpokeLadder"
		add_child(_ladder)
	_ladder.climb_half_height = max(_radial_length * 0.5, 0.5)
	_ladder.rung_spacing = 0.42
	_ladder.attach_depth = 0.35

func _remove_ladder() -> void:
	if _ladder != null and is_instance_valid(_ladder):
		remove_child(_ladder)
		_ladder.free()
	_ladder = null

func _ensure_elevator(plate_xform: Transform) -> void:
	if _elevator == null or not is_instance_valid(_elevator):
		_elevator = ELEVATOR_SCRIPT.new()
		_elevator.name = "RadialElevator"
		add_child(_elevator)
	_elevator.configure_from_plate(plate_xform, hub_radius)
	if not _elevator.is_inside_tree():
		# Hijo de un spoke aún fuera del árbol: `transform` es local, así que se
		# compensa la transformación del spoke para que, al entrar al árbol, el
		# ascensor quede exactamente en la placa.
		_elevator.transform = transform.affine_inverse() * _elevator.transform

func _remove_elevator() -> void:
	if _elevator != null and is_instance_valid(_elevator):
		remove_child(_elevator)
		_elevator.free()
	_elevator = null
