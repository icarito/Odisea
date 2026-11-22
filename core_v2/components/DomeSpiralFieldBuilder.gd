extends Reference
class_name DomeSpiralFieldBuilder

# Construcción estática de colisión, visual y marcadores de LOD para
# DomeSpiralField (FD-323, Fase 0 B). Todo deriva de plate_transform.

const GEOMETRY_SCRIPT := preload(
	"res://core_v2/components/DomeSpiralFieldGeometry.gd"
)

static func build_collision(root: Spatial, configs: Array, plate_size: Vector3) -> void:
	for spiral_index in range(configs.size()):
		var spiral: Dictionary = configs[spiral_index]
		var body := StaticBody.new()
		body.name = "PlateCollision_%d" % spiral_index
		body.set_meta("spiral_index", spiral_index)
		root.add_child(body)
		for plate_index in range(GEOMETRY_SCRIPT.plate_count_for(spiral)):
			var shape := BoxShape.new()
			shape.extents = plate_size * 0.5
			var collision := CollisionShape.new()
			collision.name = "Plate_%d" % plate_index
			collision.shape = shape
			collision.transform = GEOMETRY_SCRIPT.plate_transform(spiral, plate_index)
			body.add_child(collision)

static func build_visual(
	root: Spatial, configs: Array, plate_size: Vector3,
	mesh: Mesh, material: Material
) -> Array:
	# Devuelve los transforms horneados por espiral. En headless el backend de
	# render no conserva los transforms del MultiMesh, así que este cache es la
	# fuente de verdad verificable; el MultiMesh recibe exactamente los mismos.
	var baked: Array = []
	for spiral_index in range(configs.size()):
		var spiral: Dictionary = configs[spiral_index]
		var count: int = GEOMETRY_SCRIPT.plate_count_for(spiral)
		var transforms: Array = []
		for plate_index in range(count):
			transforms.append(GEOMETRY_SCRIPT.plate_transform(spiral, plate_index))
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _resolve_mesh(plate_size, mesh, material)
		multimesh.instance_count = count
		for plate_index in range(count):
			multimesh.set_instance_transform(plate_index, transforms[plate_index])
		var instance := MultiMeshInstance.new()
		instance.name = "PlateVisual_%d" % spiral_index
		instance.multimesh = multimesh
		root.add_child(instance)
		baked.append(transforms)
	return baked

static func dome_lod_entries(registry: Node, configs: Array) -> Array:
	var entries: Array = []
	if registry == null:
		return entries
	for dome_id in registry.get_all_dome_ids():
		var info: Dictionary = registry.get_dome(String(dome_id))
		var spiral_index: int = int(info.get("spiral_index", 0))
		var plate_index: int = int(info.get("plate_index", 0))
		if spiral_index < 0 or spiral_index >= configs.size():
			continue
		entries.append({
			"dome_id": String(dome_id),
			"spiral_index": spiral_index,
			"plate_index": plate_index,
			"transform": GEOMETRY_SCRIPT.plate_transform(
				configs[spiral_index], plate_index
			)
		})
	return entries

static func build_dome_lod_markers(root: Spatial, entries: Array) -> void:
	for entry in entries:
		var marker := Spatial.new()
		marker.name = "DomeLOD_%s" % String(entry["dome_id"])
		marker.transform = entry["transform"]
		marker.set_meta("dome_id", String(entry["dome_id"]))
		root.add_child(marker)

static func _resolve_mesh(plate_size: Vector3, mesh: Mesh, material: Material) -> Mesh:
	if mesh != null:
		return mesh
	var box := CubeMesh.new()
	box.size = plate_size
	if material != null:
		box.material = material
	return box
