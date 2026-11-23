extends Spatial
class_name ArkRunTerraceProps
# FD-324 F2 — domos provisionales y andamios de las terrazas del ArkRun.
# Derivan de `plate_transform` + SLICE_SEED (sin randf): misma semilla => mismo
# layout. Cada domo deja 4 patas y una pasarela al centro de la placa.
const SpiralGeometry = preload("res://core_v2/components/DomeSpiralFieldGeometry.gd")
const DomeResource = preload("res://core_v2/components/DomeSpiralFieldResource.gd")
const SLICE_SEED := 32401
const DOME_MESH = preload("res://core_v2/levels/exteriors/DomeExteriorLowPoly_baked.mesh")
const DOME_MESH_RADIUS := 35.0
const DOME_MESH_HEIGHT := 35.0
const DOME_SLOTS_PER_PLATE := 1
const DOME_COLLISION_SCRIPT = preload("res://core_v2/levels/ark_run/ArkRunDomeCollision.gd")
const PLATE_SIZE := Vector3(200.0, 2.0, 200.0)
const DOME_KINDS := ["dome", "cap", "vat", "tower"]
const DOME_COLORS := {
	"dome": Color(0.46, 0.58, 0.68, 1.0), "cap": Color(0.62, 0.54, 0.44, 1.0),
	"vat": Color(0.44, 0.62, 0.56, 1.0), "tower": Color(0.58, 0.50, 0.62, 1.0),
}
const SCAFFOLD_COLOR := Color(0.72, 0.66, 0.52, 1.0)

var _seed := SLICE_SEED
var _dome_entries: Array = []
var _scaffold_transforms: Array = []
var _variant_counts: Dictionary = {}
var _domes_root: Spatial = null
var _scaffolds_root: Spatial = null
func build(field, seed_value: int = SLICE_SEED) -> void:
	var configs: Array = field.get_spiral_configs() \
		if field != null and field.has_method("get_spiral_configs") else []
	build_from_config(
		configs[0] if not configs.empty() else DomeResource.default_spiral_config(),
		seed_value
	)
func build_from_config(spiral: Dictionary, seed_value: int = SLICE_SEED) -> void:
	build_from_configs([spiral], seed_value)

# Puebla todas las espirales declaradas (6 en ArkRun: 300 placas) con domos
# monumentales 200x200 en MultiMesh. `spiral_index` entra en el hash para que
# el layout sea determinista y distinto entre espirales.
func build_from_configs(spirals: Array, seed_value: int = SLICE_SEED) -> void:
	_seed = int(seed_value)
	_ensure_roots()
	_clear_children(_domes_root)
	_clear_children(_scaffolds_root)
	_dome_entries = []
	_scaffold_transforms = []
	_variant_counts = {}
	var buckets := {}
	for kind in DOME_KINDS:
		buckets[kind] = []
	for spiral_index in range(spirals.size()):
		var spiral: Dictionary = spirals[spiral_index]
		for plate_index in range(SpiralGeometry.plate_count_for(spiral)):
			if (plate_index + spiral_index) % 2 != 0:
				continue
			var plate_xform: Transform = SpiralGeometry.plate_transform(spiral, plate_index)
			var hash_plate: int = spiral_index * 997 + plate_index
			for slot in range(DOME_SLOTS_PER_PLATE):
				var variant: Dictionary = dome_variant(_seed, hash_plate, slot)
				var local: Transform = dome_local_transform(PLATE_SIZE, variant)
				var kind: String = String(variant["kind"])
				buckets[kind].append(plate_xform * local)
				_variant_counts[kind] = int(_variant_counts.get(kind, 0)) + 1
				_dome_entries.append({
					"spiral_index": spiral_index, "plate_index": plate_index, "slot": slot,
					"kind": kind, "variant": variant, "transform": plate_xform * local,
				})
				for scaffold in scaffold_local_transforms(
						PLATE_SIZE, variant, local, _seed, hash_plate, slot):
					_scaffold_transforms.append(plate_xform * scaffold)
	for kind in DOME_KINDS:
		if not buckets[kind].empty():
			_spawn_multimesh(_domes_root, "Domes_" + kind, _mesh_for_kind(kind), buckets[kind])
	var cube := CubeMesh.new()
	cube.size = Vector3(1.0, 1.0, 1.0)
	cube.material = _material(SCAFFOLD_COLOR)
	_spawn_multimesh(_scaffolds_root, "Scaffolds", cube, _scaffold_transforms)
	DOME_COLLISION_SCRIPT.new().rebuild(self, _dome_entries)

# Catálogo determinista: reemplazar `_mesh_for_kind` por el kit de Blender.
static func dome_variant(seed_value: int, plate_index: int, slot: int) -> Dictionary:
	return {
		"kind": DOME_KINDS[_mix(seed_value, plate_index, slot, 0) % DOME_KINDS.size()],
		"radius": lerp(40.0, 52.0, _unit(_mix(seed_value, plate_index, slot, 1))),
		"height": lerp(30.0, 44.0, _unit(_mix(seed_value, plate_index, slot, 2))),
		"rotation": _unit(_mix(seed_value, plate_index, slot, 3)) * TAU,
		"tangent_offset": (_unit(_mix(seed_value, plate_index, slot, 4)) - 0.5) * 16.0,
		"axial_offset": (_unit(_mix(seed_value, plate_index, slot, 5)) - 0.5) * 16.0,
	}

static func dome_local_transform(plate_size: Vector3, variant: Dictionary) -> Transform:
	var radius: float = float(variant["radius"])
	var height: float = float(variant["height"])
	# El mesh baked tiene AABB (70, 35, 70) con base en y=0: se escala para que
	# el domo mida `radius` y `height` reales sobre la placa de 200x200.
	var origin := Vector3(
		float(variant["tangent_offset"]), plate_size.y * 0.5 + 0.05,
		float(variant["axial_offset"])
	)
	var basis: Basis = Basis(Vector3.UP, float(variant["rotation"]))
	var scale_v := Vector3(
		radius / DOME_MESH_RADIUS, height / DOME_MESH_HEIGHT, radius / DOME_MESH_RADIUS)
	return Transform(basis.scaled(scale_v), origin)
# Cuatro patas alrededor del domo + pasarela a la estación del ascensor.
static func scaffold_local_transforms(plate_size: Vector3, variant: Dictionary, dome_local: Transform, seed_value: int, plate_index: int, slot: int) -> Array:
	var transforms: Array = []
	var radius: float = float(variant["radius"])
	var leg_height: float = max(float(variant["height"]) * 0.85, 1.0)
	var base_y: float = plate_size.y * 0.5
	var foot := Vector3(dome_local.origin.x, base_y, dome_local.origin.z)
	for leg in range(4):
		var jitter: float = (_unit(_mix(seed_value, plate_index, slot, 10 + leg)) - 0.5) * 0.3
		var angle: float = TAU * float(leg) / 4.0 + jitter
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * radius * 0.92
		transforms.append(Transform(
			Basis.IDENTITY.scaled(Vector3(0.35, leg_height, 0.35)),
			foot + offset + Vector3(0.0, leg_height * 0.5, 0.0)
		))
	var start := Vector3(foot.x, base_y + 0.15, foot.z)
	var end := Vector3(0.0, start.y, 0.0)
	var delta := end - start
	var length: float = delta.length()
	if length > 0.5:
		var x_axis: Vector3 = delta / length
		var z_axis: Vector3 = x_axis.cross(Vector3.UP).normalized()
		transforms.append(Transform(
			Basis(x_axis, Vector3.UP, z_axis).scaled(Vector3(length, 0.25, 1.4)),
			(start + end) * 0.5
		))
	return transforms
func _spawn_multimesh(root: Spatial, node_name: String, mesh: Mesh, transforms: Array) -> void:
	if transforms.empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance.new()
	instance.name = node_name
	instance.multimesh = multimesh
	root.add_child(instance)
func _mesh_for_kind(kind: String) -> Mesh:
	var mesh: Mesh = DOME_MESH.duplicate()
	mesh.surface_set_material(0, _material(DOME_COLORS.get(kind, SCAFFOLD_COLOR)))
	return mesh
func _material(color: Color) -> SpatialMaterial:
	var material := SpatialMaterial.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material
func _ensure_roots() -> void:
	if _domes_root == null or not is_instance_valid(_domes_root):
		_domes_root = Spatial.new()
		_domes_root.name = "Domes"
		add_child(_domes_root)
	if _scaffolds_root == null or not is_instance_valid(_scaffolds_root):
		_scaffolds_root = Spatial.new()
		_scaffolds_root.name = "Scaffolds"
		add_child(_scaffolds_root)
func _clear_children(root: Spatial) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.free()
func get_dome_count() -> int: return _dome_entries.size()
func get_scaffold_count() -> int: return _scaffold_transforms.size()
func get_variant_counts() -> Dictionary: return _variant_counts.duplicate()
func get_dome_entries() -> Array: return _dome_entries.duplicate(true)
func get_vertex_count() -> int:
	return _vertex_count(self)
func _vertex_count(node: Node) -> int:
	var total: int = 0
	if node is MultiMeshInstance:
		var multimesh: MultiMesh = node.multimesh
		if multimesh != null and multimesh.mesh != null and multimesh.instance_count > 0:
			total += multimesh.mesh.get_faces().size() * multimesh.instance_count
	for child in node.get_children():
		total += _vertex_count(child)
	return total
func get_layout_signature() -> String:
	var parts: Array = []
	for entry in _dome_entries:
		parts.append("%d:%d:%s:%s" % [int(entry["plate_index"]), int(entry["slot"]),
			String(entry["kind"]), var2str(entry["transform"])])
	for scaffold in _scaffold_transforms:
		parts.append("scaffold:%s" % var2str(scaffold))
	return PoolStringArray(parts).join("|")
# Hash puro: mismo (seed, placa, slot) => mismo valor.
static func _mix(seed_value: int, plate_index: int, slot: int, salt: int) -> int:
	var h: int = (seed_value * 73856093) ^ (plate_index * 19349663)
	h = h ^ (slot * 83492791) ^ (salt * 2654435761)
	h = h & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return (h ^ (h >> 16)) & 0x7fffffff

static func _unit(hash_value: int) -> float:
	return float(hash_value % 10007) / 10007.0
