extends Reference

# FD-324 F7 — guía 3D de ruta (aros/balizas emisivas) en UN MultiMeshInstance.
# Un anillo octogonal cada 4 waypoints de la ruta canónica + columnas verticales
# en Puente y Motor, todo unshaded/emisivo: +1 draw call para leer el camino.

const GUIDE_COLOR := Color(0.95, 0.85, 0.45, 1.0)
const RING_RADIUS := 14.0
const RING_STEP := 4
const BEAM_HEIGHT := 420.0

func build(parent, waypoints: Array, bridge: Vector3, motor: Vector3):
	if parent == null or waypoints.empty():
		return null
	var mesh := CubeMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)
	var material := SpatialMaterial.new()
	material.flags_unshaded = true
	material.albedo_color = GUIDE_COLOR
	material.emission_enabled = true
	material.emission = GUIDE_COLOR
	material.emission_energy = 1.4
	mesh.material = material
	var transforms: Array = []
	for index in range(0, waypoints.size(), RING_STEP):
		var position: Vector3 = waypoints[index]["position"]
		for segment in range(8):
			var angle: float = TAU * float(segment) / 8.0
			var offset := Vector3(cos(angle), sin(angle), 0.0) * RING_RADIUS
			var basis := Basis(Vector3(0.0, 0.0, 1.0), angle + PI * 0.5)
			transforms.append(Transform(basis.scaled(Vector3(4.0, 0.6, 0.6)), position + offset))
	for beacon in [bridge, motor]:
		transforms.append(Transform(
			Basis.IDENTITY.scaled(Vector3(6.0, BEAM_HEIGHT, 6.0)),
			(beacon as Vector3) + Vector3(0.0, BEAM_HEIGHT * 0.5, 0.0)
		))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance.new()
	instance.name = "RouteGuides"
	instance.multimesh = multimesh
	parent.add_child(instance)
	return instance
