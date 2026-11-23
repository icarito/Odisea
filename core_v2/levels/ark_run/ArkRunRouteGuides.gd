extends Reference

# FD-324 F7 — guía 3D de ruta (aros/balizas emisivas) en UN MultiMeshInstance.
# Un anillo octogonal cada 2 waypoints de la ruta canónica + columnas verticales en
# Puente y Motor, todo unshaded/emisivo: +1 draw call para leer el camino.
#
# FD-325 polish: las guías se orientan respecto al CILINDRO (SpinFrame.up), no a +Y
# global: en las paredes del ancla el "arriba" es radial. Los arcos se elevan +sim_up*18 m
# sobre cada placa y miran al siguiente waypoint; las columnas de Puente (oro) y Motor
# (naranja-rojo) apuntan al eje desde su propia up.

const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")
const GUIDE_COLOR := Color(0.95, 0.85, 0.45, 1.0)
const BRIDGE_COLOR := Color(1.0, 0.82, 0.25, 1.0)
const MOTOR_COLOR := Color(1.0, 0.35, 0.12, 1.0)
const RING_RADIUS := 14.0
const RING_STEP := 2
const RING_LIFT := 18.0
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
	var transforms: Array = build_transforms(waypoints, bridge, motor)
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

# Transforms de la guía (puro/testeable): anillos orientados por SpinFrame.up + columnas.
static func build_transforms(waypoints: Array, bridge: Vector3, motor: Vector3) -> Array:
	var transforms: Array = []
	for index in range(0, waypoints.size(), RING_STEP):
		var position: Vector3 = waypoints[index]["position"]
		var up: Vector3 = SpinFrame.up(position)
		var next_pos: Vector3 = waypoints[min(index + RING_STEP, waypoints.size() - 1)]["position"]
		_append_ring(transforms, position + up * RING_LIFT, up, next_pos)
	_append_beam(transforms, bridge, BRIDGE_COLOR)
	_append_beam(transforms, motor, MOTOR_COLOR)
	return transforms

# 8 trazos octogonales alrededor de `center` en el plano perpendicular a `up`, girados
# para mirar hacia el siguiente waypoint (tangente horizontal del cilindro).
static func _append_ring(transforms: Array, center: Vector3, up: Vector3, next_pos: Vector3) -> void:
	var to_next: Vector3 = next_pos - center
	var forward: Vector3 = to_next - up * to_next.dot(up)
	forward = forward.normalized() if forward.length_squared() > 1e-6 else up.cross(Vector3.RIGHT).normalized()
	var side: Vector3 = up.cross(forward).normalized()
	for segment in range(8):
		var angle: float = TAU * float(segment) / 8.0
		var offset: Vector3 = (side * cos(angle) + forward * sin(angle)) * RING_RADIUS
		var radial: Vector3 = offset.normalized() if offset.length_squared() > 1e-6 else side
		var basis := Basis(radial.cross(up).normalized(), up, -radial)
		transforms.append(Transform(basis.scaled(Vector3(4.0, 0.6, 0.6)), center + offset))

# Columna vertical (en la up local) sobre la baliza, orientada hacia el eje del cilindro.
static func _append_beam(transforms: Array, beacon: Vector3, _color: Color) -> void:
	var up: Vector3 = SpinFrame.up(beacon)
	var radial: Vector3 = SpinFrame.r_perp(beacon)
	var axis_dir: Vector3 = radial.normalized() if radial.length_squared() > 1e-6 else up
	var x_axis: Vector3 = up.cross(axis_dir)
	x_axis = x_axis.normalized() if x_axis.length_squared() > 1e-6 else up.cross(Vector3.RIGHT).normalized()
	var basis := Basis(x_axis, up, x_axis.cross(up).normalized())
	transforms.append(Transform(basis.scaled(Vector3(6.0, BEAM_HEIGHT, 6.0)), beacon + up * (BEAM_HEIGHT * 0.5)))

