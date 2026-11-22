extends Spatial

# FD-324 F5 — conversión de terrazas (decisión #5: 3.0 s, sincronizada 1:1 con la
# rampa de empuje de 3 s) + helper puro de colapso cinemático determinista
# (decisión #9, sin RigidBody).
#
# Placas KINEMÁTICAS que rotan en `_physics_process` con tasa angular limitada
# hacia `normal = SpinFrame.up_eff(origin, omega, a_axial)` (= -g_eff.normalized()).
# La `a_axial` sale de `ArkRunEngineIgnition.get_axial_accel()`; sin driver se usa
# `fallback_a_axial`. Sin randf()/randomize(): mismo delta fijo => mismo estado.
#
# AGENTS §5.2: el arrastre del Pilot lo hace el transform-delta tracking de
# plataformas del controller (`SpinRealPhysicsV2._step_grounded` lo invoca en
# SPIN_REAL). Una KinematicBody registrada aquí arrastra al jugador.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const EPSILON := 1e-6
const COLLAPSE_DURATION := 1.0

export(float) var omega := 0.0
export(float) var duration_sec := 3.0
export(float) var max_angular_speed_rad_s := 0.35
export(float) var fallback_a_axial := 0.0
export(Vector3) var proxy_size := Vector3(40.0, 0.4, 40.0)
export(float) var proxy_lift := 1.2

var _plates: Array = []
var _active := false
var _elapsed := 0.0
var _ignition = null

# --- Helper puro de colapso (decisión #9): u = clamp(t / duration, 0, 1) ---
static func collapse_progress(t: float, duration: float = COLLAPSE_DURATION) -> float:
	return clamp(t / duration, 0.0, 1.0) if duration > 0.0 else 1.0

# Desplaza/inclina una pieza cinemática sin motor físico; u=1 la deja fija.
static func sample_collapse(
	base: Transform, u: float, direction: Vector3, angle_rad: float, drop: float
) -> Transform:
	var k: float = clamp(u, 0.0, 1.0)
	var dir: Vector3 = direction.normalized() if direction.length_squared() > EPSILON else Vector3(0.0, 0.0, -1.0)
	var axis: Vector3 = base.basis.y.normalized().cross(dir)
	if axis.length_squared() < EPSILON:
		axis = base.basis.y.normalized().cross(Vector3.RIGHT)
	if axis.length_squared() < EPSILON:
		axis = Vector3.RIGHT
	var basis: Basis = (Basis(axis.normalized(), angle_rad * k) * base.basis).orthonormalized()
	return Transform(basis, base.origin + dir * (drop * k))

# --- Wiring ---
func set_ignition(driver) -> void: _ignition = driver
func add_plate(body) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not _plates.has(body):
		_plates.append(body)
	return true

# Crea una placa kinemática (KinematicBody => trackable por §5.2) y la registra.
func create_plate(plate_transform: Transform, size: Vector3 = Vector3.ZERO, plate_name: String = "") -> KinematicBody:
	var s: Vector3 = size if size != Vector3.ZERO else proxy_size
	var body := KinematicBody.new()
	body.name = plate_name if plate_name != "" else "KinematicPlate"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape.new()
	shape.name = "PlateShape"
	var box := BoxShape.new()
	box.extents = s * 0.5
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance.new()
	visual.name = "PlateVisual"
	var cube := CubeMesh.new()
	cube.size = s
	var material := SpatialMaterial.new()
	material.albedo_color = Color(0.55, 0.72, 0.86, 1.0)
	material.flags_unshaded = true
	cube.material = material
	visual.mesh = cube
	body.add_child(visual)
	add_child(body)
	_apply_transform(body, plate_transform)
	add_plate(body)
	return body

# Crea proxies kinemáticos para las `count` placas de espiral más cercanas a
# `ref_position` (p. ej. la terraza bajo Elías), levantados sobre la placa base.
func add_spiral_plates(slice, ref_position: Vector3, count: int = 4) -> Array:
	var created: Array = []
	if slice == null or not slice.has_method("get_spiral_config"):
		return created
	var config: Dictionary = slice.get_spiral_config()
	for entry in SpiralGeometry.select_closest_plates([config], ref_position, count):
		var base: Transform = SpiralGeometry.plate_transform(config, int(entry["plate_index"]))
		var lifted := Transform(base.basis, base.origin + base.basis.y.normalized() * proxy_lift)
		created.append(create_plate(lifted, proxy_size, "KinematicPlate_%02d" % int(entry["plate_index"])))
	return created

# --- Conversión ---
func start_conversion() -> void:
	_active = true
	_elapsed = 0.0

func is_active() -> bool: return _active
func is_complete() -> bool: return not _active and _elapsed >= duration_sec
func get_elapsed() -> float: return _elapsed
func get_plate_count() -> int: return _plates.size()

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not _active:
		return
	_elapsed += max(delta, 0.0)
	var a_axial: float = _current_axial()
	for body in _plates:
		if body == null or not is_instance_valid(body):
			continue
		var current: Transform = _world_transform(body)
		var up_now: Vector3 = current.basis.y.normalized()
		if up_now.length_squared() < EPSILON:
			continue
		var target: Vector3 = SpinFrame.up_eff(current.origin, _omega_value(), a_axial, up_now)
		_rotate_toward(body, current, up_now, target, max(delta, 0.0))
	if _elapsed >= duration_sec:
		_elapsed = duration_sec
		_active = false

func _rotate_toward(body, current: Transform, up_now: Vector3, target: Vector3, dt: float) -> void:
	if target.length_squared() < EPSILON:
		return
	var target_up: Vector3 = target.normalized()
	var angle: float = acos(clamp(up_now.dot(target_up), -1.0, 1.0))
	if angle <= EPSILON:
		return
	var applied: float = min(angle, max(0.0, max_angular_speed_rad_s) * dt)
	if applied <= 0.0:
		return
	var axis: Vector3 = up_now.cross(target_up)
	if axis.length_squared() < EPSILON:
		axis = _fallback_axis(up_now)
	var basis: Basis = Basis(axis.normalized(), applied) * current.basis
	_apply_transform(body, Transform(basis.orthonormalized(), current.origin))

func _fallback_axis(up_now: Vector3) -> Vector3:
	var axis: Vector3 = up_now.cross(Vector3(0.0, 0.0, 1.0))
	if axis.length_squared() < EPSILON:
		axis = up_now.cross(Vector3.RIGHT)
	if axis.length_squared() < EPSILON:
		axis = Vector3.RIGHT
	return axis.normalized()

func _current_axial() -> float:
	if _ignition != null and is_instance_valid(_ignition) \
			and _ignition.has_method("get_axial_accel"):
		return float(_ignition.get_axial_accel())
	return fallback_a_axial

func _omega_value() -> float:
	if omega > 0.0:
		return omega
	return SpinFrame.omega_for()

func _world_transform(body) -> Transform:
	return body.global_transform if body.is_inside_tree() else body.transform

func _apply_transform(body, xform: Transform) -> void:
	if body.is_inside_tree():
		body.global_transform = xform
	else:
		body.transform = xform

# --- Getters para tests / presentación (deterministas) ---
func get_plate_normal(index: int = 0) -> Vector3:
	if index < 0 or index >= _plates.size():
		return Vector3.ZERO
	var body = _plates[index]
	return _world_transform(body).basis.y.normalized() if is_instance_valid(body) else Vector3.ZERO

func get_plate_origin(index: int = 0) -> Vector3:
	if index < 0 or index >= _plates.size():
		return Vector3.ZERO
	var body = _plates[index]
	return _world_transform(body).origin if is_instance_valid(body) else Vector3.ZERO

func get_target_normal(index: int = 0) -> Vector3:
	if index < 0 or index >= _plates.size():
		return Vector3.ZERO
	return SpinFrame.up_eff(get_plate_origin(index), _omega_value(), _current_axial())
