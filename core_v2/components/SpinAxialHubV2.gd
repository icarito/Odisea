extends Spatial
class_name SpinAxialHubV2

# FD-323 Fase 3A — tubo axial co-rotante del hub con gravedad ZERO_G.
# La zona implementa la interfaz que consume GravityWorld/ControllerManager.
# El hub se autora en el marco rotante; el volumen es radialmente simétrico.

const GravityModes = preload("res://core_v2/systems/GravityModes.gd")
const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const EPSILON := 1e-6

export(float) var hub_radius := 8.0
export(float) var z_min := -4000.0
export(float) var z_max := 4000.0
export(int) var gravity_priority := 120
export(bool) var build_visual := true

func _ready() -> void:
	add_to_group("zero_gravity_zones")
	if build_visual:
		_ensure_visual()
	if has_node("/root/GravityWorld"):
		var world = get_node("/root/GravityWorld")
		if world.has_method("register_zone"):
			world.register_zone(self)

func _exit_tree() -> void:
	if has_node("/root/GravityWorld"):
		var world = get_node("/root/GravityWorld")
		if world.has_method("unregister_zone"):
			world.unregister_zone(self)

func contains_global_point(global_position: Vector3) -> bool:
	var low_z: float = min(z_min, z_max)
	var high_z: float = max(z_min, z_max)
	if global_position.z < low_z or global_position.z > high_z:
		return false
	return SpinFrame.r_perp(global_position).length() <= max(hub_radius, 0.0)

func get_gravity_mode() -> int:
	return GravityModes.Mode.ZERO_G

func get_gravity_priority() -> int:
	return gravity_priority

func get_volume() -> float:
	return PI * max(hub_radius, 0.0) * max(hub_radius, 0.0) * abs(z_max - z_min)

func get_angular_velocity() -> float:
	# Co-rotante con el cilindro SPIN_REAL.
	return SpinFrame.omega_for()

# Salida de escotilla: posición actual + empuje radial hacia afuera.
func compute_hatch_launch(
	hatch_pos: Vector3, radial_dir: Vector3, v0: float
) -> Dictionary:
	var hatch_radial: Vector3 = SpinFrame.r_perp(hatch_pos)
	var radial: Vector3 = SpinFrame.r_perp(radial_dir)
	if radial.length_squared() < EPSILON:
		radial = hatch_radial
	if radial.length_squared() < EPSILON:
		radial = Vector3.RIGHT
	radial = radial.normalized()
	# La escotilla siempre expulsa hacia afuera del eje, sin importar el signo.
	if hatch_radial.length_squared() > EPSILON and radial.dot(hatch_radial) < 0.0:
		radial = -radial
	return {"position": hatch_pos, "velocity": radial * abs(v0)}

func _ensure_visual() -> void:
	if get_node_or_null("HubVisual") != null:
		return
	var height: float = abs(z_max - z_min)
	if height <= 0.0:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = max(hub_radius, 0.01)
	mesh.bottom_radius = max(hub_radius, 0.01)
	mesh.height = height
	mesh.radial_segments = 24
	mesh.rings = 1
	var material := SpatialMaterial.new()
	material.flags_unshaded = true
	material.flags_transparent = true
	material.albedo_color = Color(0.35, 0.7, 1.0, 0.035)
	mesh.material = material
	var instance := MeshInstance.new()
	instance.name = "HubVisual"
	instance.mesh = mesh
	instance.transform = Transform(
		Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, (z_min + z_max) * 0.5)
	)
	add_child(instance)
	# FD-324 F7: núcleo abierto/costillas. 12 largueros + anillos cada 100 m en UN
	# MultiMeshInstance emisivo (cian tenue), para ver todo el cilindro desde r=4.
	var rib_material := SpatialMaterial.new()
	rib_material.flags_unshaded = true
	rib_material.albedo_color = Color(0.35, 0.85, 1.0, 1.0)
	rib_material.emission_enabled = true
	rib_material.emission = Color(0.2, 0.7, 1.0)
	rib_material.emission_energy = 0.8
	var cube := CubeMesh.new()
	cube.size = Vector3(1.0, 1.0, 1.0)
	cube.material = rib_material
	var transforms: Array = []
	for i in range(12):
		var angle: float = TAU * float(i) / 12.0
		var pos := Vector3(cos(angle) * hub_radius, sin(angle) * hub_radius, 0.0)
		transforms.append(Transform(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(0.12, 0.12, height)), pos))
	var ring_count: int = int(max(2.0, floor(height / 100.0)))
	var ring_step: float = height / float(ring_count)
	for i in range(ring_count + 1):
		var z: float = z_min + ring_step * float(i)
		transforms.append(Transform(
			Basis.IDENTITY.scaled(Vector3(hub_radius * 2.0, 0.08, 0.08)),
			Vector3(0.0, 0.0, z)
		))
		transforms.append(Transform(
			Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(hub_radius * 2.0, 0.08, 0.08)),
			Vector3(0.0, 0.0, z)
		))
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = cube
	batch.instance_count = transforms.size()
	for i in range(transforms.size()):
		batch.set_instance_transform(i, transforms[i])
	var ribs := MultiMeshInstance.new()
	ribs.name = "HubRibs"
	ribs.multimesh = batch
	add_child(ribs)
