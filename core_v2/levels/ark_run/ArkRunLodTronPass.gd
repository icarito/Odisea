extends Spatial
class_name ArkRunLodTronPass
# FD-324 F6 — LOD de 3 niveles (horneado una vez para geometria estatica) y pase
# visual Tron aliado de performance. Lejos: malla simplificada por sector de la
# espiral; medio: MultiMesh; cerca: pool chico alrededor del jugador. Presentacion
# pura: no toca fisica. Materiales unshaded/emisivos y Environment oscuro.
const LEVEL_FAR := 0
const LEVEL_MEDIUM := 1
const LEVEL_NEAR := 2
const DEFAULT_SECTORS := 10
const DEFAULT_SLICE_HALF := 1000.0
const DEFAULT_NEAR_DIST := 140.0
const DEFAULT_MEDIUM_DIST := 420.0
const DEFAULT_HYSTERESIS := 25.0
const NEAR_POOL_SIZE := 4
const R_IN := 220.0
const R_OUT := 260.0
const TRON_COLOR := Color(0.1, 0.85, 1.0, 1.0)
const ACCENT_COLOR := Color(1.0, 0.3, 0.7, 1.0)

export(int) var sector_count := DEFAULT_SECTORS
export(float) var slice_half := DEFAULT_SLICE_HALF
export(float) var near_dist := DEFAULT_NEAR_DIST
export(float) var medium_dist := DEFAULT_MEDIUM_DIST
export(float) var hysteresis := DEFAULT_HYSTERESIS
export(bool) var auto_build := true
var _centers: Array = []
var _levels: Array = []
var _far_nodes: Array = []
var _medium_nodes: Array = []
var _near_pool: Array = []
var _material: SpatialMaterial = null
var _accent_material: SpatialMaterial = null
var _environment: Environment = null
var _built := false
func _ready() -> void:
	if auto_build:
		build_static()
func build_static() -> void:
	if _built:
		return
	_built = true
	_material = create_tron_material(TRON_COLOR)
	_accent_material = create_tron_material(ACCENT_COLOR)
	_environment = build_environment()
	var step: float = (2.0 * slice_half) / float(max(sector_count, 1))
	for index in range(sector_count):
		var z: float = -slice_half + step * (float(index) + 0.5)
		_centers.append(Vector3(0.0, 0.0, z))
		_levels.append(LEVEL_FAR)
		_far_nodes.append(_build_far_sector(index, z, step))
		_medium_nodes.append(_build_medium_sector(index, z, step))
	for index in range(NEAR_POOL_SIZE):
		_near_pool.append(_build_near_detail(index))
	update_lod_for_position(Vector3.ZERO)
# Asigna niveles por distancia axial con histeresis (sin popping) y reposiciona
# el pool cercano. Determinista: misma posicion => mismos niveles.
func update_lod_for_position(pos: Vector3) -> Array:
	_ensure_built()
	for index in range(_centers.size()):
		var center: Vector3 = _centers[index]
		var distance: float = abs(pos.z - center.z)
		var level: int = classify_distance(distance, int(_levels[index]))
		_levels[index] = level
		(_far_nodes[index] as Spatial).visible = level == LEVEL_FAR
		(_medium_nodes[index] as Spatial).visible = level == LEVEL_MEDIUM
	_position_near_pool(pos)
	return _levels.duplicate()
func classify_distance(distance: float, current: int) -> int:
	var band: float = max(hysteresis, 0.0)
	if current == LEVEL_NEAR and distance <= near_dist + band:
		return LEVEL_NEAR
	if current == LEVEL_MEDIUM:
		if distance < near_dist - band:
			return LEVEL_NEAR
		if distance <= medium_dist + band:
			return LEVEL_MEDIUM
		return LEVEL_FAR
	if distance < near_dist - band:
		return LEVEL_NEAR
	if distance < medium_dist - band:
		return LEVEL_MEDIUM
	return LEVEL_FAR
func _ensure_built() -> void:
	if not _built:
		build_static()
func _build_far_sector(index: int, z: float, step: float) -> Spatial:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0: float = z - step * 0.5
	var z1: float = z + step * 0.5
	var corners: Array = [
		Vector3(R_IN, 0.0, z0), Vector3(R_OUT, 0.0, z0),
		Vector3(R_OUT, 0.0, z1), Vector3(R_IN, 0.0, z1)
	]
	for corner in corners:
		st.add_normal(Vector3.UP)
		st.add_vertex(corner)
	st.add_index(0)
	st.add_index(1)
	st.add_index(2)
	st.add_index(0)
	st.add_index(2)
	st.add_index(3)
	var node := MeshInstance.new()
	node.name = "FarSector_%d" % index
	node.mesh = st.commit()
	node.material_override = _material
	add_child(node)
	return node
func _build_medium_sector(index: int, z: float, step: float) -> Spatial:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var cube := CubeMesh.new()
	cube.size = Vector3(22.0, 2.0, 8.0)
	cube.material = _material
	multimesh.mesh = cube
	var count: int = 6
	multimesh.instance_count = count
	for slot in range(count):
		var f: float = (float(slot) + 0.5) / float(count)
		var angle: float = f * TAU
		var sample_z: float = z - step * 0.5 + step * f
		var origin := Vector3(R_OUT * cos(angle), R_OUT * sin(angle), sample_z)
		multimesh.set_instance_transform(slot, Transform(Basis(Vector3(0, 0, 1), angle), origin))
	var node := MultiMeshInstance.new()
	node.name = "MediumSector_%d" % index
	node.multimesh = multimesh
	add_child(node)
	return node
func _build_near_detail(index: int) -> Spatial:
	var node := MeshInstance.new()
	node.name = "NearDetail_%d" % index
	var cube := CubeMesh.new()
	cube.size = Vector3(2.0, 0.6, 2.0)
	cube.material = _accent_material
	node.mesh = cube
	node.visible = false
	add_child(node)
	return node
func _position_near_pool(pos: Vector3) -> void:
	var any_near: bool = false
	for level in _levels:
		if int(level) == LEVEL_NEAR:
			any_near = true
			break
	for index in range(_near_pool.size()):
		var angle: float = TAU * float(index) / float(max(_near_pool.size(), 1))
		var origin := Vector3(R_OUT * cos(angle), R_OUT * sin(angle), pos.z + float(index))
		var node: Spatial = _near_pool[index]
		node.translation = origin
		node.visible = any_near
# Lineas emisivas unshaded para anclajes de cuerda, ruta canonica y predictor.
func add_emissive_polyline(points: Array, color: Color) -> Spatial:
	_ensure_built()
	var geometry := ImmediateGeometry.new()
	geometry.name = "EmissiveLine_%d" % get_child_count()
	geometry.material_override = create_tron_material(color)
	geometry.begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		geometry.add_vertex(point as Vector3)
	geometry.end()
	add_child(geometry)
	return geometry
static func create_tron_material(color: Color) -> SpatialMaterial:
	var material := SpatialMaterial.new()
	material.flags_unshaded = true
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy = 1.6
	material.params_cull_mode = SpatialMaterial.CULL_DISABLED
	return material
static func build_environment() -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.02, 0.035)
	environment.ambient_light_color = Color(0.05, 0.08, 0.12)
	environment.ambient_light_energy = 0.6
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.15
	environment.glow_strength = 1.1
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	return environment
func get_sector_count() -> int:
	return _centers.size()
func get_level(index: int) -> int:
	return int(_levels[index])
func get_sector_center(index: int) -> Vector3:
	return _centers[index]
func get_material() -> SpatialMaterial:
	return _material
func get_accent_material() -> SpatialMaterial:
	return _accent_material
func get_environment() -> Environment:
	return _environment
func is_built() -> bool:
	return _built
