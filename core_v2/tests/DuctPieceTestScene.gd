extends Spatial

const DuctMazeStreamerScript = preload("res://core_v2/systems/DuctMazeSpawner.gd")

const PREVIEW_INNER_RADIUS := 15.0
const PREVIEW_RING_STEP := 10.0
const PREVIEW_DUCT_RADIUS := 3.75

const PIECES = [
	{"name": "EndCap", "path": "res://core_v2/props/duct/DuctEndCap.tscn", "connections": [true, false, false, false], "rotation": 0},
	{"name": "Radial", "path": "res://core_v2/props/duct/DuctRadial.tscn", "connections": [true, false, true, false], "rotation": 0},
	{"name": "Arc", "path": "", "connections": [false, true, false, true], "rotation": 90},
	{"name": "Elbow", "path": "res://core_v2/props/duct/DuctElbow.tscn", "connections": [true, true, false, false], "rotation": 0},
	{"name": "Tee", "path": "res://core_v2/props/duct/DuctTee.tscn", "connections": [true, true, true, false], "rotation": 90},
	{"name": "Cross", "path": "res://core_v2/props/duct/DuctCross.tscn", "connections": [true, true, true, true], "rotation": 0},
	{"name": "Capsule", "path": "res://core_v2/props/duct/CapsuleRoom.tscn", "connections": [true, true, false, true], "rotation": 0}
]

var _red_mat: SpatialMaterial
var _green_mat: SpatialMaterial
var _blue_mat: SpatialMaterial
var _yellow_mat: SpatialMaterial
var _gray_mat: SpatialMaterial

func _ready() -> void:
	_build_materials()
	_build_lighting()
	_build_piece_gallery()
	_build_polar_preview()
	_build_camera()

func _build_materials() -> void:
	_red_mat = _mat(Color(1.0, 0.15, 0.1, 1.0))
	_green_mat = _mat(Color(0.15, 0.9, 0.25, 1.0))
	_blue_mat = _mat(Color(0.2, 0.45, 1.0, 1.0))
	_yellow_mat = _mat(Color(1.0, 0.85, 0.1, 1.0))
	_gray_mat = _mat(Color(0.45, 0.48, 0.52, 1.0))

func _mat(color: Color) -> SpatialMaterial:
	var mat: SpatialMaterial = SpatialMaterial.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	return mat

func _build_lighting() -> void:
	var light: DirectionalLight = DirectionalLight.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = 0.8
	add_child(light)

	var fill: OmniLight = OmniLight.new()
	fill.translation = Vector3(0, 12, 10)
	fill.omni_range = 80.0
	fill.light_energy = 0.45
	add_child(fill)

func _build_piece_gallery() -> void:
	for i in range(PIECES.size()):
		var spec: Dictionary = PIECES[i]
		var root: Spatial = Spatial.new()
		root.name = "Piece_" + String(spec.get("name", "Unknown"))
		root.translation = Vector3(float(i) * 18.0 - 54.0, 0.0, 0.0)
		add_child(root)

		var instance: Spatial = _make_piece(spec)
		if instance:
			root.add_child(instance)
			if instance.has_method("setup"):
				instance.setup(spec.get("connections", []), int(spec.get("rotation", 0)))
		_draw_local_axes(root)
		_draw_ports(root, spec.get("connections", [false, false, false, false]), _ring_radius(0))

func _make_piece(spec: Dictionary) -> Spatial:
	if String(spec.get("name", "")) == "Arc":
		return _make_arc_piece()
	var spawner = DuctMazeStreamerScript.new()
	spawner.inner_radius = PREVIEW_INNER_RADIUS
	spawner.ring_step = PREVIEW_RING_STEP
	spawner.duct_radius = PREVIEW_DUCT_RADIUS
	var node: Spatial = spawner._make_procedural_tile(spec.get("connections", []), [0.0, 0.0, 0.0, 0.0], _ring_radius(0), String(spec.get("name", "")) == "Capsule")
	spawner.free()
	return node

func _make_arc_piece() -> Spatial:
	var root: Spatial = Spatial.new()
	root.name = "DuctArcGenerated"
	var builder = load("res://core_v2/systems/DuctArcBuilder.gd")
	var mesh: ArrayMesh = builder.get_or_build_arc(_ring_radius(0), PREVIEW_DUCT_RADIUS, 30.0)
	var mesh_instance: MeshInstance = MeshInstance.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = load("res://core_v2/props/duct/DuctHull.tres")
	mesh_instance.translation = Vector3(-_ring_radius(0), 0.0, 0.0)
	var body: StaticBody = StaticBody.new()
	body.collision_layer = 1
	body.collision_mask = 255
	var collision: CollisionShape = CollisionShape.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	mesh_instance.add_child(body)
	root.add_child(mesh_instance)
	return root

func _draw_local_axes(parent: Spatial) -> void:
	_add_cylinder(parent, Vector3(2.8, 0, 0), Vector3(1, 0, 0), 5.6, 0.05, _red_mat, "AxisX_Tangent")
	_add_cylinder(parent, Vector3(0, 2.8, 0), Vector3(0, 1, 0), 5.6, 0.05, _green_mat, "AxisY_Cylinder")
	_add_cylinder(parent, Vector3(0, 0, 2.8), Vector3(0, 0, 1), 5.6, 0.05, _blue_mat, "AxisZ_Radial")

func _draw_ports(parent: Spatial, connections: Array, ring_radius: float) -> void:
	for d in range(4):
		if d >= connections.size() or not connections[d]:
			continue
		var endpoint: Vector3 = _local_port_endpoint(d, ring_radius)
		_add_cylinder(parent, endpoint * 0.5, endpoint.normalized(), endpoint.length(), 0.08, _yellow_mat, "OpenPort%d" % d)
		_add_sphere(parent, endpoint, 0.22, _yellow_mat, "PortMarker%d" % d)

func _build_polar_preview() -> void:
	var spawner = DuctMazeStreamerScript.new()
	spawner.name = "PolarMazePreview"
	spawner.translation = Vector3(0, 0, -88)
	spawner.inner_radius = PREVIEW_INNER_RADIUS
	spawner.ring_step = PREVIEW_RING_STEP
	spawner.sectors = 12
	spawner.rings = 4
	spawner.height_steps = 3
	spawner.room_count = 8
	spawner.extra_cycles = 2
	spawner.seed_value = 52
	spawner.add_connection_bridges = true
	add_child(spawner)
	spawner.generate()
	_draw_global_cylinder_axis(spawner)

func _draw_global_cylinder_axis(parent: Spatial) -> void:
	_add_cylinder(parent, Vector3.ZERO, Vector3(0, 1, 0), 18.0, 0.07, _green_mat, "CylinderAxisY")

func _build_camera() -> void:
	var camera: Camera = Camera.new()
	camera.name = "Camera"
	camera.translation = Vector3(0, 72, 148)
	camera.rotation_degrees = Vector3(-28, 0, 0)
	camera.far = 640.0
	camera.current = true
	add_child(camera)

func _add_cylinder(parent: Spatial, pos: Vector3, axis: Vector3, length: float, radius: float, mat: Material, name: String) -> void:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	var inst: MeshInstance = MeshInstance.new()
	inst.name = name
	inst.mesh = mesh
	inst.material_override = mat
	inst.transform = Transform(_basis_from_y_axis(axis), pos)
	parent.add_child(inst)

func _add_sphere(parent: Spatial, pos: Vector3, radius: float, mat: Material, name: String) -> void:
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var inst: MeshInstance = MeshInstance.new()
	inst.name = name
	inst.mesh = mesh
	inst.material_override = mat
	inst.translation = pos
	parent.add_child(inst)

func _local_port_endpoint(direction: int, ring_radius: float) -> Vector3:
	if direction == 0:
		return Vector3(0, 0, -PREVIEW_RING_STEP * 0.5)
	if direction == 2:
		return Vector3(0, 0, PREVIEW_RING_STEP * 0.5)
	var half_angle: float = deg2rad(15.0)
	var tangent_offset: float = ring_radius * sin(half_angle)
	var inward_offset: float = ring_radius * (cos(half_angle) - 1.0)
	if direction == 1:
		return Vector3(tangent_offset, 0, inward_offset)
	return Vector3(-tangent_offset, 0, inward_offset)

func _ring_radius(gy: int) -> float:
	return PREVIEW_INNER_RADIUS + (float(gy) + 0.5) * PREVIEW_RING_STEP

func _basis_from_y_axis(axis: Vector3) -> Basis:
	var y_axis: Vector3 = axis.normalized()
	var x_ref: Vector3 = Vector3.RIGHT
	if abs(y_axis.dot(x_ref)) > 0.92:
		x_ref = Vector3(0, 0, -1)
	var z_axis: Vector3 = x_ref.cross(y_axis).normalized()
	var x_axis: Vector3 = y_axis.cross(z_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)
