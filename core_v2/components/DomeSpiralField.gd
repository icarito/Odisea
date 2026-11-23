extends Spatial
class_name DomeSpiralField

# Campo estático de placas en espiral dentro del cilindro (FD-323, Fase 0 B).
# Marco canónico: eje del cilindro = Z y origen en el centro de la nave.
# La geometría se hornea una sola vez en rebuild_field(); las placas nunca se
# mueven por frame. Sólo el pool de detalle se reasigna cada N ticks.

const SPIRAL_RESOURCE_SCRIPT := preload(
	"res://core_v2/components/DomeSpiralFieldResource.gd"
)
const GEOMETRY_SCRIPT := preload(
	"res://core_v2/components/DomeSpiralFieldGeometry.gd"
)
const BUILDER_SCRIPT := preload(
	"res://core_v2/components/DomeSpiralFieldBuilder.gd"
)
const DETAIL_POOL_SCRIPT := preload(
	"res://core_v2/components/DomeSpiralDetailPool.gd"
)

const DEFAULT_PLATE_SIZE := Vector3(200.0, 2.0, 200.0)

export(Resource) var field_config: Resource = null
export(Array, Dictionary) var spirals: Array = []
export var plate_size: Vector3 = DEFAULT_PLATE_SIZE
export(Mesh) var plate_mesh: Mesh = null
export(Material) var plate_material: Material = null
export var detail_slot_count: int = 8
export var detail_update_interval_ticks: int = 10
export var detail_reference_position: Vector3 = Vector3.ZERO
export var build_on_ready: bool = true

var _spiral_configs: Array = []
var _baked_transforms: Array = []
var _active_plate_size: Vector3 = DEFAULT_PLATE_SIZE
var _visual_root: Spatial = null
var _collision_root: Spatial = null
var _dome_lod_root: Spatial = null
var _detail_pool: Spatial = null
var _built: bool = false

func _ready() -> void:
	if build_on_ready:
		rebuild_field()

# Sólo delega el tick del pool; jamás toca las placas estáticas.
func _physics_process(_delta: float) -> void:
	if _built and is_instance_valid(_detail_pool):
		_detail_pool.tick()

# --- Configuración ---

func get_spiral_configs() -> Array:
	return _resolve_spiral_configs().duplicate(true)

func _resolve_spiral_configs() -> Array:
	if field_config != null and field_config.has_method("get_spiral_configs"):
		var from_resource: Array = field_config.get_spiral_configs()
		if not from_resource.empty():
			return from_resource
	if not spirals.empty():
		var configs: Array = []
		for raw in spirals:
			configs.append(SPIRAL_RESOURCE_SCRIPT.normalize_spiral_config(raw))
		return configs
	return [SPIRAL_RESOURCE_SCRIPT.default_spiral_config()]

func _resolve_plate_size() -> Vector3:
	if plate_size != DEFAULT_PLATE_SIZE:
		return plate_size
	if field_config != null and field_config.has_method("get_spiral_configs"):
		return field_config.plate_size
	return plate_size

# --- Geometría pura (marco canónico Z) ---

static func plate_count_for(spiral: Dictionary) -> int:
	return GEOMETRY_SCRIPT.plate_count_for(spiral)

# Determinista y sin estado; z centrado en [-total_height/2, +total_height/2].
static func plate_transform(spiral: Dictionary, i: int) -> Transform:
	return GEOMETRY_SCRIPT.plate_transform(spiral, i)

# --- Construcción estática ---

func rebuild_field() -> void:
	_ensure_roots()
	_clear_root(_visual_root)
	_clear_root(_collision_root)
	_clear_root(_dome_lod_root)
	_spiral_configs = _resolve_spiral_configs()
	_active_plate_size = _resolve_plate_size()
	_baked_transforms = []
	BUILDER_SCRIPT.build_collision(
		_collision_root, _spiral_configs, _active_plate_size
	)
	_baked_transforms = BUILDER_SCRIPT.build_visual(
		_visual_root, _spiral_configs, _active_plate_size,
		plate_mesh, plate_material
	)
	BUILDER_SCRIPT.build_dome_lod_markers(_dome_lod_root, get_dome_lod_entries())
	_ensure_detail_pool()
	_detail_pool.configure(
		_spiral_configs,
		detail_slot_count,
		detail_update_interval_ticks,
		detail_reference_position
	)
	_built = true

func _ensure_roots() -> void:
	_visual_root = _ensure_root(_visual_root, "SpiralVisuals")
	_collision_root = _ensure_root(_collision_root, "SpiralCollisions")
	_dome_lod_root = _ensure_root(_dome_lod_root, "SpiralDomeLODs")

func _ensure_root(existing: Spatial, node_name: String) -> Spatial:
	if is_instance_valid(existing):
		return existing
	var node := Spatial.new()
	node.name = node_name
	add_child(node)
	return node

func _ensure_detail_pool() -> void:
	if not is_instance_valid(_detail_pool):
		_detail_pool = DETAIL_POOL_SCRIPT.new()
		_detail_pool.name = "SpiralDetailPool"
		add_child(_detail_pool)

func _clear_root(root: Spatial) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.free()

# Reemplaza el material de las placas ya horneadas sin reconstruir el campo ni
# agregar draw calls (mismo pase, otro material). Lo usa el pase Tron del ArkRun.
func set_plate_material(material: Material) -> void:
	if material == null or not is_instance_valid(_visual_root):
		return
	for child in _visual_root.get_children():
		var instance := child as MultiMeshInstance
		if instance == null or instance.multimesh == null or instance.multimesh.mesh == null:
			continue
		instance.multimesh.mesh.surface_set_material(0, material)

# --- Pool de detalle, anclajes y LODs ---

func select_closest_plates(ref_pos: Vector3, k: int) -> Array:
	var configs: Array = _spiral_configs
	if configs.empty():
		configs = _resolve_spiral_configs()
	return GEOMETRY_SCRIPT.select_closest_plates(configs, ref_pos, k)

# Anclajes en el marco canónico (el campo se asume en identidad).
func get_plate_world_anchors(spiral_index: int, plate_index: int, local_anchors: Array) -> Array:
	return GEOMETRY_SCRIPT.compose_anchors(
		_resolve_spiral_configs(), spiral_index, plate_index, local_anchors
	)

# Punto de conexión de un spoke: offset local en el espacio de la placa.
func get_plate_spoke_anchor(
	spiral_index: int, plate_index: int, local_offset: Vector3
) -> Vector3:
	return GEOMETRY_SCRIPT.spoke_anchor(
		_resolve_spiral_configs(), spiral_index, plate_index, local_offset
	)

func get_dome_lod_entries() -> Array:
	return BUILDER_SCRIPT.dome_lod_entries(
		get_node_or_null("/root/DomeRegistry"), _resolve_spiral_configs()
	)

# Getters de inspección.
func get_spiral_count() -> int:
	return _spiral_configs.size()
func get_collision_body(spiral_index: int) -> StaticBody:
	if not is_instance_valid(_collision_root):
		return null
	if spiral_index < 0 or spiral_index >= _collision_root.get_child_count():
		return null
	return _collision_root.get_child(spiral_index) as StaticBody
func get_plate_multimesh(spiral_index: int) -> MultiMesh:
	if not is_instance_valid(_visual_root):
		return null
	if spiral_index < 0 or spiral_index >= _visual_root.get_child_count():
		return null
	var instance := _visual_root.get_child(spiral_index) as MultiMeshInstance
	return instance.multimesh if instance != null else null
# Transforms exactos usados para hornear el visual de una espiral.
func get_baked_plate_transforms(spiral_index: int) -> Array:
	if spiral_index < 0 or spiral_index >= _baked_transforms.size():
		return []
	return _baked_transforms[spiral_index].duplicate()
func get_detail_pool_revision() -> int:
	return _detail_pool.get_revision() if is_instance_valid(_detail_pool) else 0
func get_detail_selection() -> Array:
	return _detail_pool.get_selection() if is_instance_valid(_detail_pool) else []
func get_detail_slots() -> Array:
	return _detail_pool.get_slots() if is_instance_valid(_detail_pool) else []
func set_detail_reference_position(position: Vector3) -> void:
	detail_reference_position = position
	if _built and is_instance_valid(_detail_pool):
		_detail_pool.set_reference_position(position)
