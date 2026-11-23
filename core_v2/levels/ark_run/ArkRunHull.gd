extends StaticBody
class_name ArkRunHull

# FD-324 F0 — casco exterior del vertical slice "Del hub al motor".
#
# Colisión gruesa, completa e inmutable del cilindro del Arca: pared de 360°
# (cajas tangentes solapadas) + tapas en proa/popa que se solapan con la pared.
# La contención física no depende de contenido streameado: una vez construida
# en _ready(), no se toca. La malla visual es sólo una lectura barata de la
# forma cilíndrica (sin tapas, cara interior visible).
#
# Marco canónico: eje Z, origen en el centro de la nave. Proa = +Z, popa = -Z.

export(float) var hull_radius := 340.0
export(float) var slice_length := 2000.0
export(int) var wall_segments := 24
export(float) var wall_thickness := 20.0
export(float) var cap_extension := 20.0
export(float) var cap_thickness := 60.0
export(float) var wall_overlap := 1.25
export(bool) var build_collision := true
export(bool) var build_visual := true

var _built := false
var _wall_count := 0

func _ready() -> void:
	build()

func build() -> void:
	if _built:
		return
	_built = true
	if build_collision:
		_build_collision()
	if build_visual:
		_build_visual()
	_build_tron_decor()

func _build_collision() -> void:
	var radius: float = max(hull_radius, 1.0)
	var half_length: float = max(slice_length, 0.0) * 0.5
	var thickness: float = max(wall_thickness, 1.0)
	var segments: int = int(max(8, wall_segments))
	var half_width: float = radius * tan(PI / float(segments)) * max(wall_overlap, 1.0)
	var half_thickness: float = thickness * 0.5
	var axis := Vector3(0.0, 0.0, 1.0)

	for index in range(segments):
		var angle: float = TAU * float(index) / float(segments)
		var radial := Vector3(cos(angle), sin(angle), 0.0)
		var tangent := Vector3(-sin(angle), cos(angle), 0.0)
		var wall := BoxShape.new()
		wall.extents = Vector3(half_width, half_length, half_thickness)
		var shape := CollisionShape.new()
		shape.name = "HullWall_%02d" % index
		shape.shape = wall
		# Cara interior exactamente en `radius`; el centro de la caja queda medio
		# espesor hacia afuera.
		shape.transform = Transform(
			Basis(tangent, axis, radial), radial * (radius + half_thickness)
		)
		add_child(shape)
		_wall_count += 1

	# Tapas: discos gruesos solapados con la pared para cerrar la proa y la popa
	# sin rendijas. Centradas en +/- (half_length + cap_extension).
	var cap_radius: float = radius + max(cap_extension, 0.0)
	var cap_height: float = max(cap_thickness, 1.0)
	for sign_z in [1.0, -1.0]:
		var cap := CylinderShape.new()
		cap.radius = cap_radius
		cap.height = cap_height
		var shape := CollisionShape.new()
		shape.name = "HullCap_%s" % ("Fore" if sign_z > 0.0 else "Aft")
		shape.shape = cap
		shape.transform = Transform(
			Basis(Vector3.RIGHT, PI * 0.5),
			Vector3(0.0, 0.0, sign_z * (half_length + max(cap_extension, 0.0)))
		)
		add_child(shape)

func _build_visual() -> void:
	if get_node_or_null("HullVisual") != null:
		return
	var radius: float = max(hull_radius, 0.01)
	var length: float = max(slice_length, 0.01)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = int(max(24, wall_segments * 2))
	mesh.rings = 1
	var material := SpatialMaterial.new()
	material.flags_unshaded = true
	material.params_cull_mode = SpatialMaterial.CULL_DISABLED
	material.albedo_color = Color(0.12, 0.16, 0.22, 1.0)
	mesh.material = material
	var instance := MeshInstance.new()
	instance.name = "HullVisual"
	instance.mesh = mesh
	# CylinderMesh nace con eje Y; se alinea al eje Z del marco canónico.
	instance.transform = Transform(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	add_child(instance)

# FD-324 F7: lectura Tron del casco. Anillos + 8 largueros en MultiMesh (2 draws)
# y balizas grandes de Puente (+Z) y Motor (-Z) visibles desde 2000 m.
func _build_tron_decor() -> void:
	if get_node_or_null("HullTron") != null:
		return
	var decor := Spatial.new()
	decor.name = "HullTron"
	add_child(decor)
	var radius: float = max(hull_radius, 1.0)
	var length: float = max(slice_length, 1.0)
	var cyan := _tron_material(Color(0.1, 0.85, 1.0))
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius - 0.8
	ring_mesh.outer_radius = radius + 0.8
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 6
	ring_mesh.material = cyan
	var ring_count := 9
	var ring_step := length / float(ring_count - 1)
	var ring_mm := MultiMesh.new()
	ring_mm.transform_format = MultiMesh.TRANSFORM_3D
	ring_mm.mesh = ring_mesh
	ring_mm.instance_count = ring_count
	for i in range(ring_count):
		var z: float = -length * 0.5 + ring_step * float(i)
		ring_mm.set_instance_transform(i, Transform(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.0, 0.0, z)))
	var rings := MultiMeshInstance.new()
	rings.name = "HullRings"
	rings.multimesh = ring_mm
	decor.add_child(rings)
	var beam := CubeMesh.new()
	beam.size = Vector3(1.0, 1.0, 1.0)
	beam.material = cyan
	var beam_mm := MultiMesh.new()
	beam_mm.transform_format = MultiMesh.TRANSFORM_3D
	beam_mm.mesh = beam
	beam_mm.instance_count = 8
	for i in range(8):
		var angle: float = TAU * float(i) / 8.0
		var pos := Vector3(cos(angle) * radius, sin(angle) * radius, 0.0)
		beam_mm.set_instance_transform(i, Transform(
			Basis.IDENTITY.scaled(Vector3(0.6, 0.6, length + 20.0)), pos))
	var beams := MultiMeshInstance.new()
	beams.name = "HullLongerons"
	beams.multimesh = beam_mm
	decor.add_child(beams)
	_add_beacon(decor, "BridgeBeacon", Vector3(220.0, 0.0, length * 0.5 - 80.0),
		Color(1.0, 0.85, 0.25), 34.0)
	_add_beacon(decor, "EngineBeacon", Vector3(0.0, 0.0, -length * 0.5 + 40.0),
		Color(1.0, 0.28, 0.08), 44.0)

func _add_beacon(parent: Spatial, beacon_name: String, pos: Vector3, color: Color, size: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	sphere.material = _tron_material(color)
	var node := MeshInstance.new()
	node.name = beacon_name
	node.mesh = sphere
	node.translation = pos
	parent.add_child(node)

func _tron_material(color: Color) -> SpatialMaterial:
	var material := SpatialMaterial.new()
	material.flags_unshaded = true
	material.params_cull_mode = SpatialMaterial.CULL_DISABLED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy = 2.0
	return material

func get_tron_decor() -> Spatial:
	return get_node_or_null("HullTron") as Spatial

func get_hull_radius() -> float:
	return hull_radius

func get_slice_length() -> float:
	return slice_length

func get_wall_segment_count() -> int:
	return _wall_count

func get_collision_shape_count() -> int:
	var count := 0
	for child in get_children():
		if child is CollisionShape:
			count += 1
	return count
