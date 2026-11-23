extends Node
class_name ArkRunCylindricalCamera

# FD-324 F6 — vistas cilindricas del Ark-Run. AGENTS §2.3: reusa el CameraRig y
# el SpringArm existentes del Pilot; nunca crea un Camera ni un rig nuevo.
# Modos: 3ra persona en suelo, 2.5D co-rotante en vuelo medio y panorama axial
# (axial_blend) durante el vuelo largo hub->Puente. Presentacion pura.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const SideController = preload("res://core_v2/camera/SpinRealCameraController.gd")
const EPSILON := 1e-6

export(float) var h_in := 18.0
export(float) var h_out := 12.0
export(float) var blend_speed := 2.5
export(float) var axial_speed := 1.6
export(float) var view_25d_axial_angle_deg := 22.0
export(float) var axial_tilt_deg := 64.0

var blend_25d := 0.0
var axial_blend := 0.0
var in_25d := false
var _prefix := Basis.IDENTITY
var _last_up := Vector3.UP
var _prefix_initialized := false

static func compute_altitude(pos: Vector3, r_local: float) -> float:
	return r_local - SpinFrame.r_perp(pos).length()

# Base del panorama axial: mira hacia proa (+Z) con el up simulado y una
# inclinacion 3/4 configurable. Continua respecto de up y del blend.
static func compute_axial_basis(sim_up: Vector3, tilt_deg: float = 64.0) -> Basis:
	var up: Vector3 = sim_up.normalized()
	if up.length_squared() < EPSILON:
		up = Vector3.UP
	var tilt: float = deg2rad(clamp(tilt_deg, 0.0, 85.0))
	var forward: Vector3 = (Vector3(0.0, 0.0, 1.0) * cos(tilt) - up * sin(tilt)).normalized()
	var back: Vector3 = -forward
	var x_axis: Vector3 = up.cross(back)
	if x_axis.length_squared() < EPSILON:
		x_axis = up.cross(Vector3.RIGHT)
	if x_axis.length_squared() < EPSILON:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var y_axis: Vector3 = back.cross(x_axis).normalized()
	return Basis(x_axis, y_axis, back).orthonormalized()

# Actualiza histeresis, blends y prefijo. flight_progress in [0,1] lo aporta el
# dueno de la escena (vuelo largo hub->Puente). Devuelve el estado de camara.
func step_camera(
	pos: Vector3, sim_up: Vector3, r_local: float, dt: float,
	flight_progress: float = 0.0
) -> Dictionary:
	var up: Vector3 = sim_up.normalized()
	if up.length_squared() < EPSILON:
		up = SpinFrame.up(pos, Vector3.UP)
	var altitude: float = compute_altitude(pos, r_local)
	if in_25d:
		if altitude < h_out:
			in_25d = false
	elif altitude > h_in:
		in_25d = true
	var target_25d: float = 1.0 if in_25d else 0.0
	blend_25d = move_toward(blend_25d, target_25d, max(blend_speed, 0.0) * max(dt, 0.0))
	var target_axial: float = clamp(flight_progress, 0.0, 1.0)
	axial_blend = move_toward(axial_blend, target_axial, max(axial_speed, 0.0) * max(dt, 0.0))

	if not _prefix_initialized:
		_prefix = SideController.compute_aligned_prefix(Basis(Vector3.UP, PI), Vector3.UP, up)
		_prefix_initialized = true
	else:
		_prefix = SideController.compute_aligned_prefix(_prefix, _last_up, up)
	_last_up = up

	var side_basis: Basis = SideController.compute_25d_basis(up, view_25d_axial_angle_deg)
	var side_blend: Basis = _prefix.slerp(side_basis, blend_25d).orthonormalized()
	var axial_basis: Basis = compute_axial_basis(up, axial_tilt_deg)
	var basis: Basis = side_blend.slerp(axial_basis, axial_blend).orthonormalized()
	return {
		"altitude": altitude, "blend_25d": blend_25d, "axial_blend": axial_blend,
		"in_25d": in_25d, "up": up, "prefix": _prefix,
		"basis_side": side_blend, "basis_axial": axial_basis, "basis": basis,
		"basis_extra": (side_blend.inverse() * basis).orthonormalized()
	}

# Aplica la transformacion adicional sobre el SpringArm del rig existente.
# No crea Camera ni rig: si no hay SpringArm, no toca nada.
func apply_to_rig(rig: Spatial, state: Dictionary) -> bool:
	if not is_instance_valid(rig):
		return false
	var spring_arm: Spatial = rig.find_node("SpringArm", true, false) as Spatial
	if spring_arm == null:
		return false
	spring_arm.transform.basis = (state["basis_extra"] as Basis)
	return true

func reset() -> void:
	blend_25d = 0.0
	axial_blend = 0.0
	in_25d = false
	_prefix = Basis.IDENTITY
	_last_up = Vector3.UP
	_prefix_initialized = false
