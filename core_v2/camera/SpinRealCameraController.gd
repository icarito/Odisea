extends Node
class_name SpinRealCameraController

# FD-323 Fase 2B — cámara 2.5D co-rotante del cilindro SpinReal.
# Presentación pura: no toca la simulación ni crea un rig propio. Reusa el
# CameraRig/SpringArm del Pilot y sólo reorienta el rig.
#
# Convención: +Z es "back" y -Z es "forward". El prefijo base carga 180° en Y;
# el transporte paralelo mantiene ese prefijo alineado a _up sin flips.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const EPSILON := 1e-6

export(float) var h_in := 18.0
export(float) var h_out := 12.0
export(float) var blend_speed := 2.5
export(float) var view_25d_axial_angle_deg := 22.0

export(bool) var enable_25d_override := true
var camera_basis_prefix: Basis = Basis(Vector3.UP, PI)
var blend_25d := 0.0
var in_25d := false

var _prefix: Basis = Basis.IDENTITY
var _last_up := Vector3.UP
var _prefix_initialized := false

# h = r_local - |r_perp(pos)|: altura sobre la superficie del cilindro.
static func compute_altitude(pos: Vector3, r_local: float) -> float:
	return r_local - SpinFrame.r_perp(pos).length()

# Transporte paralelo: rota prev_prefix por el arco mínimo que lleva prev_up a
# target_up. Preserva el prefijo base y evita el flip de 180° en un giro 360°.
static func compute_aligned_prefix(prev_prefix: Basis, prev_up: Vector3, target_up: Vector3) -> Basis:
	var prefix: Basis = prev_prefix.orthonormalized()
	var from_up: Vector3 = prev_up.normalized()
	var to_up: Vector3 = target_up.normalized()
	if from_up.length_squared() < EPSILON or to_up.length_squared() < EPSILON:
		return prefix
	var dot: float = clamp(from_up.dot(to_up), -1.0, 1.0)
	if dot > 1.0 - EPSILON:
		return prefix
	var axis: Vector3 = from_up.cross(to_up)
	if axis.length_squared() < EPSILON:
		# Caso antipodal: eje perpendicular determinista tomado del prefijo.
		axis = prefix.x - from_up * prefix.x.dot(from_up)
		if axis.length_squared() < EPSILON:
			axis = prefix.z - from_up * prefix.z.dot(from_up)
		if axis.length_squared() < EPSILON:
			axis = from_up.cross(Vector3.RIGHT)
		if axis.length_squared() < EPSILON:
			return prefix
	axis = axis.normalized()
	return (Basis(axis, acos(dot)) * prefix).orthonormalized()

# Base de la vista 2.5D: co-rotante con el cilindro, mirando a lo largo de Z
# con una inclinación axial 3/4 (22° por defecto). No aplica -omega*t.
static func compute_25d_basis(sim_up: Vector3, axial_angle_deg: float = 22.0) -> Basis:
	var up: Vector3 = sim_up.normalized()
	if up.length_squared() < EPSILON:
		up = Vector3.UP
	var angle: float = deg2rad(clamp(axial_angle_deg, -85.0, 85.0))
	var forward: Vector3 = (-Vector3(0.0, 0.0, 1.0) * cos(angle) - up * sin(angle)).normalized()
	var back: Vector3 = -forward
	var x_axis: Vector3 = up.cross(back)
	if x_axis.length_squared() < EPSILON:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var y_axis: Vector3 = back.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, back).orthonormalized()

# Actualiza histéresis, blend y prefijo, y devuelve el estado de cámara.
func step_camera(pos: Vector3, sim_up: Vector3, r_local: float, dt: float) -> Dictionary:
	var up: Vector3 = sim_up.normalized()
	if up.length_squared() < EPSILON:
		up = SpinFrame.up(pos, Vector3.UP)
	var altitude: float = compute_altitude(pos, r_local)

	if in_25d:
		if altitude < h_out:
			in_25d = false
	elif altitude > h_in:
		in_25d = true

	var target: float = 1.0 if in_25d else 0.0
	blend_25d = move_toward(blend_25d, target, max(blend_speed, 0.0) * max(dt, 0.0))

	if not _prefix_initialized:
		_prefix = compute_aligned_prefix(camera_basis_prefix, Vector3.UP, up)
		_prefix_initialized = true
	else:
		_prefix = compute_aligned_prefix(_prefix, _last_up, up)
	_last_up = up

	var basis_25d: Basis = compute_25d_basis(up, view_25d_axial_angle_deg)
	var basis: Basis = _prefix.slerp(basis_25d, blend_25d).orthonormalized()
	return {
		"altitude": altitude,
		"blend_25d": blend_25d,
		"in_25d": in_25d,
		"up": up,
		"prefix": _prefix,
		"basis_3d": _prefix,
		"basis_25d": basis_25d,
		"basis": basis
	}

# Aplica el estado al CameraRig existente del pilot. No mueve el rig ni toca
# física: sólo orienta el rig y actualiza el prefijo que usa el controlador.
func apply_to_pilot(pilot: Node, r_local: float, dt: float) -> Dictionary:
	if not is_instance_valid(pilot):
		return {}
	var pos: Vector3 = Vector3.ZERO
	var pilot_basis := Basis.IDENTITY
	if pilot is Spatial:
		pos = (pilot as Spatial).global_transform.origin
		pilot_basis = (pilot as Spatial).global_transform.basis
	var state: Dictionary = step_camera(pos, SpinFrame.up(pos, Vector3.UP), r_local, dt)

	var rig: Spatial = pilot.get_node_or_null("CameraRig") as Spatial
	if rig != null and enable_25d_override:
		var blend: float = float(state["blend_25d"])
		if blend > 0.0:
			# CameraRig es hijo del Pilot (que ya alinea +Y a _up): el objetivo 2.5D
			# (mundo) se convierte a local antes del slerp para no rotar _up dos veces.
			var basis_25d: Basis = state["basis_25d"]
			var target_local: Basis = pilot_basis.inverse() * basis_25d
			rig.transform.basis = rig.transform.basis.slerp(target_local, blend).orthonormalized()
	# El Pilot ya lleva _up en su basis: en 3ra persona el prefijo local natural
	# es la identidad. Cargar aquí el prefijo de mundo duplicaría la rotación.
	if "camera_basis_prefix" in pilot:
		pilot.camera_basis_prefix = Basis.IDENTITY
	return state
