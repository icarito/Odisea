extends Spatial
class_name ArkRunGravityShadow

# FD-324 F6 — sombra falsa del Ark-Run proyectada a lo largo de la gravedad
# efectiva con un raycast real. El disco aterriza sobre la superficie que hay
# debajo del jugador (hit.position + hit.normal * 0.06) y se orienta a la normal
# del impacto, asi que se apoya en terrazas y domos en vez de quedar flotando.
# Presentacion pura: no toca fisica ni el transform del jugador. En tests sin
# World (o sin impacto) conserva el fallback analitico previo.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const TronMaterials = preload("res://core_v2/levels/ark_run/ArkRunTronMaterials.gd")
const EPSILON := 1e-6
const RAY_BACKOFF := 0.2
const RAY_LENGTH := 60.0
const SURFACE_OFFSET := 0.06
const MAX_SHADOW_SCALE := 3.0
const MIN_SHADOW_OPACITY := 0.22

export(float) var shadow_radius := 1.4
export(float) var shadow_distance := 0.05
export(Color) var shadow_color := Color(0.02, 0.03, 0.05, 0.55)
export(bool) var build_visual := true
export(int) var collision_mask := 0x7FFFFFFF

var shadow_normal := Vector3.DOWN
var _disk: MeshInstance = null
var _material: ShaderMaterial = null
var _legacy_hidden: Dictionary = {}

func _ready() -> void:
	if build_visual:
		_ensure_visual()

# Proyecta el disco desde `pos` a lo largo de g_eff. Si el raycast toca una
# superficie, apoya el disco en `hit.position + hit.normal * 0.06` orientado a la
# normal; si no hay World (tests unitarios puros) usa el fallback analitico.
func update_shadow(pos: Vector3, omega: float, a_axial: float = 0.0, pilot = null) -> Dictionary:
	var g_eff: Vector3 = SpinFrame.g_eff(pos, omega, a_axial)
	var direction: Vector3 = Vector3.DOWN
	if g_eff.length() >= EPSILON:
		direction = g_eff.normalized()
	shadow_normal = direction
	_set_legacy_shadow_hidden(pilot, true)
	var hit: Dictionary = _cast_ground(pos, direction, pilot)
	var normal: Vector3 = direction
	var origin: Vector3 = pos + direction * shadow_distance
	var height: float = shadow_distance
	if not hit.empty():
		normal = (hit["normal"] as Vector3)
		if normal.length_squared() < EPSILON:
			normal = direction
		normal = normal.normalized()
		origin = (hit["position"] as Vector3) + normal * SURFACE_OFFSET
		height = max(0.0, origin.distance_to(pos))
	shadow_normal = normal
	_ensure_visual()
	_apply_disk(origin, normal, height)
	return {
		"normal": normal, "origin": origin, "g_eff": g_eff,
		"hit": not hit.empty(), "height": height,
	}

func _cast_ground(pos: Vector3, direction: Vector3, pilot) -> Dictionary:
	var world = get_world() if is_inside_tree() else null
	if world == null or world.direct_space_state == null:
		return {}
	var exclude: Array = []
	if pilot != null and is_instance_valid(pilot):
		exclude.append(pilot)
	return world.direct_space_state.intersect_ray(
		pos - direction * RAY_BACKOFF,
		pos + direction * RAY_LENGTH,
		exclude, collision_mask)

func _apply_disk(origin: Vector3, normal: Vector3, height: float) -> void:
	if _disk == null:
		return
	_disk.global_transform = Transform(basis_for_normal(normal), origin)
	var scale_factor: float = clamp(1.0 + height / 20.0, 1.0, MAX_SHADOW_SCALE)
	_disk.scale = Vector3(scale_factor, 1.0, scale_factor)
	if _material != null:
		var opacity: float = clamp(1.0 - height / 40.0, MIN_SHADOW_OPACITY, 1.0)
		_material.set_shader_param("opacity", opacity)

# Oculta el FakeShadow legacy de Pilot mientras la sombra real esta activa y lo
# restaura al salir de SPIN_REAL (el loop llama con `false`).
func _set_legacy_shadow_hidden(pilot, hidden: bool) -> void:
	if pilot == null or not is_instance_valid(pilot):
		return
	var fake = pilot.get_node_or_null("Visual/Pivot/FakeShadow")
	if fake == null:
		return
	var was_hidden: bool = bool(_legacy_hidden.get(pilot, false))
	if hidden:
		if was_hidden:
			return
		fake.visible = false
		for child in fake.get_children():
			if child is Spatial:
				child.visible = false
		_legacy_hidden[pilot] = true
	elif was_hidden:
		fake.visible = true
		for child in fake.get_children():
			if child is Spatial:
				child.visible = true
		_legacy_hidden[pilot] = false

func set_legacy_shadow_hidden(pilot, hidden: bool) -> void:
	_set_legacy_shadow_hidden(pilot, hidden)

# Base ortonormal con +Y alineado a `normal` (normal del disco de sombra).
static func basis_for_normal(normal: Vector3) -> Basis:
	var y_axis: Vector3 = normal.normalized()
	if y_axis.length_squared() < EPSILON:
		y_axis = Vector3.DOWN
	var helper: Vector3 = Vector3(0.0, 0.0, 1.0)
	if abs(y_axis.dot(helper)) > 0.99:
		helper = Vector3.RIGHT
	var x_axis: Vector3 = helper.cross(y_axis).normalized()
	if x_axis.length_squared() < EPSILON:
		x_axis = Vector3.RIGHT
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()

func get_shadow_normal() -> Vector3:
	return shadow_normal

func get_shadow_transform() -> Transform:
	if _disk == null:
		return Transform(basis_for_normal(shadow_normal), global_transform.origin)
	return _disk.global_transform

func _ensure_visual() -> void:
	if _disk != null or not build_visual:
		return
	_material = TronMaterials.shadow_material()
	_material.set_shader_param("core_color", shadow_color)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(shadow_radius * 2.0, shadow_radius * 2.0)
	mesh.material = _material
	_disk = MeshInstance.new()
	_disk.name = "GravityShadowDisk"
	_disk.mesh = mesh
	add_child(_disk)
