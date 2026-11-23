extends Reference
class_name ArkRunZoneDressing

# FD-324 — vestido de presentacion de la placa 48 (Puente) y la placa 0 (Motor).
# La placa 48 queda como pista de aterrizaje despejada: marco dorado/cian plano
# (no obstruye el centro donde cae Elias) y un portico al borde de proa (local +Z,
# que en el marco canonico es +Z mundo). La placa 0 lleva un anillo/reactor
# naranja-rojo en la meta. No genera domos ni colision de domo: es mera
# presentacion en MultiMesh (2 draw calls de vestido como maximo).

const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const PLATE_SIZE := Vector3(200.0, 2.0, 200.0)
const PAD_HALF := 42.0
const PAD_Y := 1.3
const GOLD := Color(1.0, 0.78, 0.25, 1.0)
const CYAN := Color(0.12, 0.86, 1.0, 1.0)
const REACTOR := Color(1.0, 0.32, 0.10, 1.0)
const BRIDGE_PLATE := 48
const ENGINE_PLATE := 0

static func build(parent: Spatial, spiral_config: Dictionary) -> Spatial:
	if parent == null or spiral_config.empty():
		return null
	var previous = parent.get_node_or_null("ZoneDressing")
	if previous != null:
		parent.remove_child(previous)
		previous.free()
	var root := Spatial.new()
	root.name = "ZoneDressing"
	parent.add_child(root)
	var count: int = SpiralGeometry.plate_count_for(spiral_config)
	if count > BRIDGE_PLATE:
		_build_bridge_pad(root, SpiralGeometry.plate_transform(spiral_config, BRIDGE_PLATE))
	if count > ENGINE_PLATE:
		_build_engine_reactor(root, SpiralGeometry.plate_transform(spiral_config, ENGINE_PLATE))
	return root

static func _build_bridge_pad(root: Spatial, plate_xform: Transform) -> void:
	var gold: Array = []
	var cyan: Array = []
	var bar := 1.3
	var thick := 2.4
	gold.append(_box(Vector3(PAD_HALF * 2.0, bar, thick), Vector3(0.0, PAD_Y, PAD_HALF)))
	gold.append(_box(Vector3(PAD_HALF * 2.0, bar, thick), Vector3(0.0, PAD_Y, -PAD_HALF)))
	cyan.append(_box(Vector3(thick, bar, PAD_HALF * 2.0), Vector3(PAD_HALF, PAD_Y, 0.0)))
	cyan.append(_box(Vector3(thick, bar, PAD_HALF * 2.0), Vector3(-PAD_HALF, PAD_Y, 0.0)))
	var inner := PAD_HALF * 0.58
	cyan.append(_box(Vector3(inner * 2.0, bar * 0.5, thick * 0.5), Vector3(0.0, PAD_Y + 0.05, inner)))
	cyan.append(_box(Vector3(inner * 2.0, bar * 0.5, thick * 0.5), Vector3(0.0, PAD_Y + 0.05, -inner)))
	# Portico al borde de proa: postes y dintel fuera del centro de aterrizaje.
	var portal_z := PLATE_SIZE.z * 0.5 - 12.0
	var post_h := 16.0
	var post_y := PAD_Y + post_h * 0.5
	gold.append(_box(Vector3(2.6, post_h, 2.6), Vector3(-16.0, post_y, portal_z)))
	gold.append(_box(Vector3(2.6, post_h, 2.6), Vector3(16.0, post_y, portal_z)))
	gold.append(_box(Vector3(34.6, 2.6, 2.6), Vector3(0.0, PAD_Y + post_h, portal_z)))
	_spawn_plate_local(root, "BridgePad_Gold", gold, plate_xform, GOLD)
	_spawn_plate_local(root, "BridgePad_Cyan", cyan, plate_xform, CYAN)

static func _build_engine_reactor(root: Spatial, plate_xform: Transform) -> void:
	var ring: Array = []
	var radius := 22.0
	var segments := 18
	var seg_len := (TAU * radius / float(segments)) * 1.15
	for index in range(segments):
		var angle := TAU * float(index) / float(segments)
		var tangent := Vector3(-sin(angle), 0.0, cos(angle))
		var basis := Basis(tangent, Vector3.UP, tangent.cross(Vector3.UP))
		ring.append(Transform(
			basis.scaled(Vector3(seg_len, 1.4, 2.2)),
			Vector3(cos(angle) * radius, PAD_Y, sin(angle) * radius)
		))
	for index in range(6):
		var angle := TAU * float(index) / 6.0
		ring.append(_box(
			Vector3(radius * 0.55, 1.0, 1.6),
			Vector3(cos(angle) * radius * 0.5, PAD_Y - 0.2, sin(angle) * radius * 0.5)
		))
	_spawn_plate_local(root, "EngineReactor", ring, plate_xform, REACTOR)

static func _spawn_plate_local(
	root: Spatial, node_name: String, local_transforms: Array,
	plate_xform: Transform, color: Color
) -> void:
	var world_transforms: Array = []
	for local in local_transforms:
		world_transforms.append(plate_xform * local)
	_spawn_multimesh(root, node_name, world_transforms, color)

static func _spawn_multimesh(
	root: Spatial, node_name: String, transforms: Array, color: Color
) -> void:
	if transforms.empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var cube := CubeMesh.new()
	cube.size = Vector3(1.0, 1.0, 1.0)
	cube.material = _emissive_material(color)
	multimesh.mesh = cube
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance.new()
	instance.name = node_name
	instance.multimesh = multimesh
	root.add_child(instance)

static func _box(size: Vector3, origin: Vector3) -> Transform:
	return Transform(Basis.IDENTITY.scaled(size), origin)

static func _emissive_material(color: Color) -> SpatialMaterial:
	var material := SpatialMaterial.new()
	material.albedo_color = color
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = color
	material.emission_energy = 1.4
	return material
