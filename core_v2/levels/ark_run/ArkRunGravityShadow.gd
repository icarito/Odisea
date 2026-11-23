extends Spatial
class_name ArkRunGravityShadow

# FD-324 F6 — sombra falsa del Ark-Run proyectada a lo largo de la gravedad
# efectiva. El disco se orienta al plano perpendicular a `g_eff`, asi que gira
# visiblemente hacia popa durante el encendido (a_axial > 0). Presentacion pura:
# no lee transform del jugador salvo la posicion que recibe; no toca fisica.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const EPSILON := 1e-6

export(float) var shadow_radius := 1.4
export(float) var shadow_distance := 0.05
export(Color) var shadow_color := Color(0.02, 0.03, 0.05, 0.55)
export(bool) var build_visual := true

var shadow_normal := Vector3.DOWN
var _disk: MeshInstance = null
var _material: SpatialMaterial = null

func _ready() -> void:
	if build_visual:
		_ensure_visual()

# Proyecta el disco desde `pos` a lo largo de g_eff y orienta su normal (eje Y
# del CylinderMesh) al vector de gravedad efectiva normalizado.
func update_shadow(pos: Vector3, omega: float, a_axial: float = 0.0) -> Dictionary:
	var g_eff: Vector3 = SpinFrame.g_eff(pos, omega, a_axial)
	var direction: Vector3 = Vector3.DOWN
	if g_eff.length() >= EPSILON:
		direction = g_eff.normalized()
	shadow_normal = direction
	var origin: Vector3 = pos + direction * shadow_distance
	_ensure_visual()
	var transform := Transform(basis_for_normal(direction), origin)
	if _disk != null:
		_disk.global_transform = transform
		_disk.visible = true
	return {"normal": direction, "origin": origin, "g_eff": g_eff}

# Base ortnormal con +Y alineado a `normal` (normal del disco de sombra).
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
	_material = SpatialMaterial.new()
	_material.flags_unshaded = true
	_material.flags_transparent = true
	_material.albedo_color = shadow_color
	_disk = MeshInstance.new()
	_disk.name = "GravityShadowDisk"
	var mesh := CylinderMesh.new()
	mesh.top_radius = max(shadow_radius, 0.01)
	mesh.bottom_radius = max(shadow_radius, 0.01)
	mesh.height = 0.02
	mesh.radial_segments = 20
	mesh.rings = 1
	mesh.material = _material
	_disk.mesh = mesh
	add_child(_disk)
