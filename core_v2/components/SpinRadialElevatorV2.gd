extends KinematicBody
class_name SpinRadialElevatorV2

# FD-324 F2 — ascensor radial determinista entre una terraza del domo y el hub.
# La posición radial es función PURA de `t_sim`: 6 m/s y 3 s de parada en cada
# extremo. `step_elevator(t)` mueve el cuerpo a la muestra y el tracking por
# delta de transform de Pilot (AGENTS §5.2) lo arrastra. `set_operational(false)`
# lo congela en su última posición (falla determinista de F5).

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const EPSILON := 1e-6
const OUTER_DWELL := "outer_dwell"
const INBOUND := "inbound"
const INNER_DWELL := "inner_dwell"
const OUTBOUND := "outbound"

export(float) var speed := 6.0
export(float) var dwell := 3.0
export(float) var r_inner := 8.0
export(float) var platform_tangent_width := 3.2
export(float) var platform_axial_depth := 2.4
export(float) var platform_thickness := 0.35
export(Color) var platform_color := Color(0.55, 0.72, 0.86, 1.0)

var r_outer := 0.0
var radial_dir := Vector3.RIGHT
var z_center := 0.0
var operational := true

var _configured := false
var _r_current := 0.0
var _phase_current := OUTER_DWELL
var _visual: MeshInstance = null
var _shape: CollisionShape = null

# Fases: parada exterior, bajada al eje, parada interior y subida a la terraza.
# `velocity_r` es d(r)/dt (negativo al acercarse al eje).
static func sample_radial_pos(
	t_sim: float, p_r_outer: float, p_r_inner: float,
	p_speed: float = 6.0, p_dwell: float = 3.0
) -> Dictionary:
	var travel: float = abs(p_r_inner - p_r_outer)
	var usable_speed: float = max(p_speed, 0.0)
	var stop_seconds: float = max(p_dwell, 0.0)
	if travel <= EPSILON or usable_speed <= EPSILON:
		return _sample(p_r_outer, 0.0, OUTER_DWELL, 2.0 * stop_seconds, 0.0)
	var travel_seconds: float = travel / usable_speed
	var cycle: float = 2.0 * stop_seconds + 2.0 * travel_seconds
	var local_t: float = fposmod(t_sim, cycle)
	var delta: float = p_r_inner - p_r_outer
	var signed_speed: float = usable_speed if delta >= 0.0 else -usable_speed
	if local_t < stop_seconds:
		return _sample(p_r_outer, 0.0, OUTER_DWELL, cycle, travel_seconds)
	local_t -= stop_seconds
	if local_t < travel_seconds:
		var u: float = clamp(local_t / travel_seconds, 0.0, 1.0)
		return _sample(p_r_outer + delta * u, signed_speed, INBOUND, cycle, travel_seconds)
	local_t -= travel_seconds
	if local_t < stop_seconds:
		return _sample(p_r_inner, 0.0, INNER_DWELL, cycle, travel_seconds)
	var back: float = clamp((local_t - stop_seconds) / travel_seconds, 0.0, 1.0)
	return _sample(p_r_inner - delta * back, -signed_speed, OUTBOUND, cycle, travel_seconds)

static func _sample(
	r: float, velocity_r: float, phase: String, cycle: float, travel_seconds: float
) -> Dictionary:
	return {
		"r": r, "velocity_r": velocity_r, "phase": phase,
		"cycle": cycle, "travel_seconds": travel_seconds
	}

# Gravedad radial lineal: g(r) = omega^2 * r (0 en el eje).
static func radial_gravity(r: float, omega: float) -> float:
	return omega * omega * abs(r)

# Coriolis lateral al viajar radialmente a `radial_speed` en `dir`.
static func lateral_coriolis(radial_speed: float, dir: Vector3, omega: float) -> Vector3:
	return SpinFrame.a_coriolis(dir.normalized() * radial_speed, omega)

# Construye el ascensor desde una placa: mismo z y dirección radial que la
# terraza, recorrido entre el radio de la placa y el radio del hub.
func configure_from_plate(
	plate_xform: Transform, p_hub_radius: float = 8.0,
	p_speed: float = 6.0, p_dwell: float = 3.0
) -> bool:
	var radial: Vector3 = SpinFrame.r_perp(plate_xform.origin)
	var plate_radius: float = radial.length()
	r_inner = max(p_hub_radius, 0.0)
	_configured = false
	if plate_radius <= r_inner + EPSILON:
		visible = false
		return false
	radial_dir = radial / plate_radius
	r_outer = plate_radius
	z_center = plate_xform.origin.z
	speed = max(p_speed, EPSILON)
	dwell = max(p_dwell, 0.0)
	operational = true
	_r_current = r_outer
	_phase_current = OUTER_DWELL
	_ensure_body()
	_apply_radius(_r_current)
	_configured = true
	visible = true
	return true

func set_operational(ok: bool) -> void:
	operational = ok

# Mueve el cuerpo a la muestra pura de `t_sim`; sin estado temporal propio.
func step_elevator(t_sim: float) -> Dictionary:
	if not _configured or not operational:
		return _state(false)
	var sample: Dictionary = sample_radial_pos(t_sim, r_outer, r_inner, speed, dwell)
	_r_current = float(sample["r"])
	_phase_current = String(sample["phase"])
	_apply_radius(_r_current)
	var state: Dictionary = _state(true)
	state["velocity_r"] = float(sample["velocity_r"])
	return state

func _state(moved: bool) -> Dictionary:
	var origin: Vector3 = transform.origin
	if is_inside_tree():
		origin = global_transform.origin
	return {
		"r": _r_current, "velocity_r": 0.0, "phase": _phase_current,
		"operational": operational, "moved": moved, "position": origin
	}

func is_configured() -> bool: return _configured
func is_operational() -> bool: return operational
func get_surface_radius() -> float: return _r_current
func get_phase() -> String: return _phase_current
func get_radial_dir() -> Vector3: return radial_dir
func get_outer_radius() -> float: return r_outer
func get_inner_radius() -> float: return r_inner
func get_z_center() -> float: return z_center
func get_radial_gravity(omega: float) -> float: return radial_gravity(_r_current, omega)

func get_lateral_coriolis(radial_speed: float, omega: float) -> Vector3:
	return lateral_coriolis(radial_speed, radial_dir, omega)

func _platform_basis() -> Basis:
	var up: Vector3 = -radial_dir
	var z_axis := Vector3(0.0, 0.0, 1.0)
	var x_axis: Vector3 = up.cross(z_axis).normalized()
	if x_axis.length_squared() < EPSILON:
		x_axis = Vector3.RIGHT
	return Basis(x_axis, up, z_axis).orthonormalized()

func _apply_radius(r: float) -> void:
	var origin: Vector3 = radial_dir * r + Vector3(0.0, 0.0, z_center)
	var target := Transform(_platform_basis(), origin)
	if is_inside_tree():
		global_transform = target
	else:
		transform = target

func _ensure_body() -> void:
	collision_layer = 1
	collision_mask = 0
	if _shape == null or not is_instance_valid(_shape):
		_shape = CollisionShape.new()
		_shape.name = "ElevatorShape"
		var box := BoxShape.new()
		box.extents = Vector3(
			platform_tangent_width * 0.5, platform_thickness * 0.5,
			platform_axial_depth * 0.5
		)
		_shape.shape = box
		add_child(_shape)
	if _visual == null or not is_instance_valid(_visual):
		_visual = MeshInstance.new()
		_visual.name = "ElevatorVisual"
		var mesh := CubeMesh.new()
		mesh.size = Vector3(platform_tangent_width, platform_thickness, platform_axial_depth)
		var material := SpatialMaterial.new()
		material.albedo_color = platform_color
		material.roughness = 0.55
		mesh.material = material
		_visual.mesh = mesh
		add_child(_visual)
	add_to_group("ark_elevator")
