extends Spatial
class_name SpinLandingPredictor

# FD-323 Fase 2B — predictor visual de aterrizaje en el cilindro SpinReal.
# Sólo presentación: lee pos/vel y dibuja un anillo + trayectoria muestreada.
# Nunca muta la simulación ni los argumentos que recibe. Usa mallas primitivas
# (TorusMesh + MultiMesh) para ser seguro en headless.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const DEFAULT_DT := 1.0 / 60.0
const DEFAULT_MAX_STEPS := 1800
const EPSILON := 1e-9

export(float) var ring_radius := 1.4
export(int) var ring_segments := 24
export(int) var trajectory_stride := 4
export(Color) var ring_color := Color(0.35, 0.9, 1.0, 0.85)

var _ring: MeshInstance = null
var _trail: MultiMeshInstance = null
var _material: SpatialMaterial = null

# Integra vuelo libre hasta cruzar r_surface. El cruce final se interpola
# linealmente. Devuelve {hit, point, velocity, impact_speed, flight_time,
# steps, trajectory}.
static func predict_landing(
	pos: Vector3, vel: Vector3, omega: float, r_surface: float,
	dt: float = DEFAULT_DT, max_steps: int = DEFAULT_MAX_STEPS
) -> Dictionary:
	var trajectory: Array = [pos]
	if dt <= 0.0 or max_steps <= 0 or r_surface <= 0.0:
		return {
			"hit": false, "point": pos, "velocity": vel, "impact_speed": 0.0,
			"flight_time": 0.0, "steps": 0, "trajectory": trajectory
		}

	var p: Vector3 = pos
	var v: Vector3 = vel
	var r_prev: float = SpinFrame.r_perp(p).length()
	if r_prev >= r_surface:
		return {
			"hit": true, "point": p, "velocity": v, "impact_speed": v.length(),
			"flight_time": 0.0, "steps": 0, "trajectory": trajectory
		}

	for step_index in range(1, max_steps + 1):
		var next: Dictionary = SpinFrame.step_free_flight(p, v, omega, dt)
		var p_next: Vector3 = next["position"]
		var v_next: Vector3 = next["velocity"]
		var r_next: float = SpinFrame.r_perp(p_next).length()
		trajectory.append(p_next)

		if r_next >= r_surface:
			var t_cross: float = 1.0
			var delta_r: float = r_next - r_prev
			if abs(delta_r) > EPSILON:
				t_cross = clamp((r_surface - r_prev) / delta_r, 0.0, 1.0)
			var point: Vector3 = p.linear_interpolate(p_next, t_cross)
			var impact_velocity: Vector3 = v.linear_interpolate(v_next, t_cross)
			trajectory[trajectory.size() - 1] = point
			return {
				"hit": true, "point": point, "velocity": impact_velocity,
				"impact_speed": impact_velocity.length(),
				"flight_time": (float(step_index - 1) + t_cross) * dt,
				"steps": step_index, "trajectory": trajectory
			}

		p = p_next
		v = v_next
		r_prev = r_next

	return {
		"hit": false, "point": p, "velocity": v, "impact_speed": v.length(),
		"flight_time": float(max_steps) * dt, "steps": max_steps,
		"trajectory": trajectory
	}

func _ready() -> void:
	_ensure_visuals()
	_set_preview_visible(false)

# Llamar cada frame con el estado del jugador. flying = vuelo libre real.
func update_preview(
	pos: Vector3, vel: Vector3, omega: float, r_surface: float, flying: bool,
	dt: float = DEFAULT_DT, max_steps: int = DEFAULT_MAX_STEPS
) -> Dictionary:
	var prediction: Dictionary = predict_landing(pos, vel, omega, r_surface, dt, max_steps)
	_ensure_visuals()
	var trajectory: Array = prediction["trajectory"]

	visible = flying
	_ring.visible = flying and bool(prediction["hit"])
	_trail.visible = flying and trajectory.size() > 1

	if _ring.visible:
		var point: Vector3 = prediction["point"]
		var local_up: Vector3 = (
			global_transform.basis.inverse().xform(SpinFrame.up(point, Vector3.UP))
		).normalized()
		_ring.transform = Transform(_basis_for_up(local_up), to_local(point))

	if _trail.visible:
		_trail.transform = Transform.IDENTITY
		_update_trajectory(trajectory)

	return prediction

func _ensure_visuals() -> void:
	if _material == null:
		_material = SpatialMaterial.new()
		_material.flags_unshaded = true
		_material.albedo_color = ring_color
		_material.emission_enabled = true
		_material.emission = ring_color
		_material.emission_energy = 1.2
	if _ring == null:
		_ring = MeshInstance.new()
		_ring.name = "LandingRing"
		var torus := TorusMesh.new()
		torus.inner_radius = max(ring_radius - 0.12, 0.05)
		torus.outer_radius = ring_radius + 0.12
		torus.rings = 12
		torus.ring_segments = int(max(8, ring_segments))
		torus.material = _material
		_ring.mesh = torus
		add_child(_ring)
	if _trail == null:
		_trail = MultiMeshInstance.new()
		_trail.name = "LandingTrajectory"
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var sphere := SphereMesh.new()
		sphere.radius = 0.09
		sphere.height = 0.18
		sphere.radial_segments = 6
		sphere.rings = 3
		sphere.material = _material
		multimesh.mesh = sphere
		_trail.multimesh = multimesh
		add_child(_trail)

func _set_preview_visible(value: bool) -> void:
	visible = value
	if _ring != null:
		_ring.visible = value
	if _trail != null:
		_trail.visible = value

func _update_trajectory(points: Array) -> void:
	var multimesh: MultiMesh = _trail.multimesh
	if multimesh == null or points.size() < 2:
		return
	var stride: int = int(max(1, trajectory_stride))
	var indices: Array = []
	for index in range(0, points.size(), stride):
		indices.append(index)
	var last_index: int = points.size() - 1
	if last_index % stride != 0:
		indices.append(last_index)

	multimesh.instance_count = indices.size()
	for slot_index in range(indices.size()):
		var world_point: Vector3 = points[int(indices[slot_index])]
		multimesh.set_instance_transform(
			slot_index, Transform(Basis.IDENTITY, to_local(world_point))
		)

static func _basis_for_up(up: Vector3) -> Basis:
	var y_axis: Vector3 = up.normalized()
	if y_axis.length_squared() < EPSILON:
		y_axis = Vector3.UP
	var x_axis: Vector3 = y_axis.cross(Vector3(0.0, 0.0, 1.0))
	if x_axis.length_squared() < EPSILON:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()
