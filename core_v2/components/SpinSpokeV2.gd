extends Spatial
class_name SpinSpokeV2

# FD-323 Fase 3A — spoke radial co-rotante entre una placa del domo y el hub.
# La escalera reutiliza LadderV2 (grupo "ladder", capa bit 2) y su visual de
# cubos es seguro en headless. El eje local Y apunta hacia el eje Z.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const LADDER_SCRIPT = preload("res://core_v2/components/LadderV2.gd")
const EPSILON := 1e-6

var hub_radius := 8.0
var _configured := false
var _plate_origin := Vector3.ZERO
var _hub_origin := Vector3.ZERO
var _radial_length := 0.0
var _ladder: StaticBody = null

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
	_radial_length = plate_radius - hub_radius
	_configured = true
	_ensure_ladder()

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
