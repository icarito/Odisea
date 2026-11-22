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
