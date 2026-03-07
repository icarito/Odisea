tool
extends DualScalingObjectV2
class_name ElevatorDoor
# Auto-fit the shaft fence so each door fills the gap up to the next floor.
export(bool) var auto_fit_shaft_fence := true setget set_auto_fit_shaft_fence
export(float, 0.0, 2.0, 0.01) var shaft_top_margin := 0.0 setget set_shaft_top_margin
export(float, -2.0, 2.0, 0.01) var per_floor_height_offset := -0.2 setget set_per_floor_height_offset
export(float, 0.0, 5.0, 0.01) var top_floor_height := 0.5 setget set_top_floor_height
export(float, 0.1, 20.0, 0.1) var fallback_shaft_height := 2.5 setget set_fallback_shaft_height
export(float, 0.0, 2.0, 0.01) var shaft_pole_overlap := 0.15 setget set_shaft_pole_overlap
export(float, 0.0, 2.0, 0.01) var top_floor_pole_overlap := 0.05 setget set_top_floor_pole_overlap
export(float, 0.01, 0.5, 0.01) var shaft_collision_thickness := 0.03 setget set_shaft_collision_thickness
export(float, 0.0, 0.5, 0.005) var shaft_cap_clearance := 0.03 setget set_shaft_cap_clearance

const EPSILON := 0.01
const SHAFT_TILING_MULT := 6.0
const PROP_LAYER := 64
const SHAFT_COLLISION_NAME := "ShaftFenceBody"
const DEFAULT_SHAFT_WIDTH := 3.0

var _last_fit_signature := ""

func _ready() -> void:
	._ready()
	_fit_shaft_fence()
	call_deferred("_fit_shaft_fence")

func _process(delta: float) -> void:
	._process(delta)
	if Engine.editor_hint:
		_fit_shaft_fence()

func _physics_process(_delta: float) -> void:
	if not Engine.editor_hint:
		_fit_shaft_fence()

func set_auto_fit_shaft_fence(v: bool) -> void:
	auto_fit_shaft_fence = v
	_fit_shaft_fence()

func set_shaft_top_margin(v: float) -> void:
	shaft_top_margin = max(v, 0.0)
	_fit_shaft_fence()

func set_per_floor_height_offset(v: float) -> void:
	per_floor_height_offset = v
	_fit_shaft_fence()

func set_top_floor_height(v: float) -> void:
	top_floor_height = max(v, 0.0)
	_fit_shaft_fence()

func set_fallback_shaft_height(v: float) -> void:
	fallback_shaft_height = max(v, 0.1)
	_fit_shaft_fence()

func set_shaft_pole_overlap(v: float) -> void:
	shaft_pole_overlap = max(v, 0.0)
	_fit_shaft_fence()

func set_top_floor_pole_overlap(v: float) -> void:
	top_floor_pole_overlap = max(v, 0.0)
	_fit_shaft_fence()

func set_shaft_collision_thickness(v: float) -> void:
	shaft_collision_thickness = max(v, 0.01)
	_fit_shaft_fence()

func set_shaft_cap_clearance(v: float) -> void:
	shaft_cap_clearance = max(v, 0.0)
	_fit_shaft_fence()

func _fit_shaft_fence() -> void:
	if not auto_fit_shaft_fence:
		return
	if not is_inside_tree():
		return

	var shaft_fence := get_node_or_null("ShaftFence") as MeshInstance
	if shaft_fence == null:
		return

	var header_top_y := _get_header_top_local_y()
	var is_last_floor := _is_last_floor()
	var next_floor_y = _find_next_floor_local_y()
	var target_height := fallback_shaft_height
	var pole_overlap := shaft_pole_overlap
	var use_top_floor_mode: bool = is_last_floor or (Engine.editor_hint and next_floor_y == null)

	if next_floor_y != null:
		target_height = max(0.1, next_floor_y - shaft_top_margin - header_top_y + per_floor_height_offset)
	elif use_top_floor_mode:
		target_height = max(0.1, top_floor_height)
		pole_overlap = top_floor_pole_overlap

	var shaft_cap_bottom_y = _find_shaft_cap_bottom_local_y()
	if shaft_cap_bottom_y != null:
		var cap_limited_height = float(shaft_cap_bottom_y) - shaft_cap_clearance - header_top_y
		target_height = min(target_height, cap_limited_height)
		target_height = max(0.01, target_height)

	var signature = "%s|%s|%s|%s|%0.4f|%0.4f|%0.4f|%0.4f|%0.4f|%0.4f" % [str(next_floor_y), str(is_last_floor), str(use_top_floor_mode), str(shaft_cap_bottom_y), header_top_y, target_height, pole_overlap, per_floor_height_offset, top_floor_height, shaft_cap_clearance]
	if signature == _last_fit_signature:
		return
	_last_fit_signature = signature

	var quad_size := Vector2(DEFAULT_SHAFT_WIDTH, target_height)
	var quad := _ensure_unique_quad_mesh(shaft_fence)
	if quad:
		var new_size := quad.size
		new_size.y = target_height
		quad.size = new_size
		_update_shaft_material_tiling(shaft_fence, new_size)
		quad_size = new_size

	var center_y := header_top_y + target_height * 0.5
	var shaft_t := shaft_fence.translation
	shaft_t.y = center_y
	shaft_fence.translation = shaft_t
	_update_shaft_collision(shaft_fence, center_y, quad_size)

	var pole_height := target_height + pole_overlap * 2.0
	_fit_shaft_pole("ShaftPoleLeft", center_y, pole_height)
	_fit_shaft_pole("ShaftPoleRight", center_y, pole_height)

func _get_header_top_local_y() -> float:
	var header := get_node_or_null("Header")
	if header and header is CSGBox:
		return header.translation.y + header.height * 0.5
	return 3.4

func _find_next_floor_local_y():
	var floor_node := get_parent() as Spatial
	if floor_node == null:
		return null
	var floors_node := floor_node.get_parent()
	if floors_node == null:
		return null

	var current_y_global: float = floor_node.global_transform.origin.y
	var next_y_global: float = INF
	for child in floors_node.get_children():
		if child == floor_node:
			continue
		if not (child is Spatial):
			continue
		var y: float = child.global_transform.origin.y
		if y > current_y_global + EPSILON and y < next_y_global:
			next_y_global = y

	if next_y_global == INF:
		return null

	var sample_global := global_transform.origin
	sample_global.y = next_y_global
	return to_local(sample_global).y

func _is_last_floor() -> bool:
	var floor_node := get_parent() as Spatial
	if floor_node == null:
		return false
	var floors_node := floor_node.get_parent()
	if floors_node == null:
		return false
	var current_y_global: float = floor_node.global_transform.origin.y
	var has_any_other_floor := false
	for child in floors_node.get_children():
		if child == floor_node:
			continue
		if not (child is Spatial):
			continue
		has_any_other_floor = true
		var y: float = child.global_transform.origin.y
		if y > current_y_global + EPSILON:
			return false
	return has_any_other_floor

func _ensure_unique_quad_mesh(shaft_fence: MeshInstance) -> QuadMesh:
	var quad := shaft_fence.mesh as QuadMesh
	if quad == null:
		return null
	if not quad.resource_local_to_scene:
		quad = quad.duplicate(true) as QuadMesh
		quad.resource_local_to_scene = true
		shaft_fence.mesh = quad
	return quad

func _update_shaft_material_tiling(shaft_fence: MeshInstance, quad_size: Vector2) -> void:
	var mat := shaft_fence.get_surface_material(0) as ShaderMaterial
	if mat == null:
		return
	if not mat.resource_local_to_scene:
		mat = mat.duplicate(true) as ShaderMaterial
		mat.resource_local_to_scene = true
		shaft_fence.set_surface_material(0, mat)
	mat.set_shader_param("tiling", Vector2(max(1.0, quad_size.x * SHAFT_TILING_MULT), max(1.0, quad_size.y * SHAFT_TILING_MULT)))

func _fit_shaft_pole(node_name: String, center_y: float, pole_height: float) -> void:
	var pole := get_node_or_null(node_name) as MeshInstance
	if pole == null:
		return

	var cylinder := pole.mesh as CylinderMesh
	if cylinder != null:
		if not cylinder.resource_local_to_scene:
			cylinder = cylinder.duplicate(true) as CylinderMesh
			cylinder.resource_local_to_scene = true
			pole.mesh = cylinder
		cylinder.height = max(0.1, pole_height)

	var t := pole.translation
	t.y = center_y
	pole.translation = t

func _update_shaft_collision(shaft_fence: MeshInstance, center_y: float, quad_size: Vector2) -> void:
	var body := _ensure_shaft_collision_body()
	if body == null:
		return

	body.collision_layer = PROP_LAYER
	body.collision_mask = 255

	var col := body.get_node_or_null("CollisionShape") as CollisionShape
	if col == null:
		return

	var box := col.shape as BoxShape
	if box == null:
		box = BoxShape.new()
		col.shape = box

	box.extents = Vector3(
		max(0.05, quad_size.x * 0.5),
		max(0.05, quad_size.y * 0.5),
		max(0.01, shaft_collision_thickness)
	)

	var t := body.translation
	t.x = shaft_fence.translation.x
	t.y = center_y
	t.z = shaft_fence.translation.z
	body.translation = t

func _ensure_shaft_collision_body() -> StaticBody:
	var body := get_node_or_null(SHAFT_COLLISION_NAME) as StaticBody
	if body == null:
		body = StaticBody.new()
		body.name = SHAFT_COLLISION_NAME
		add_child(body)

	var col := body.get_node_or_null("CollisionShape") as CollisionShape
	if col == null:
		col = CollisionShape.new()
		col.name = "CollisionShape"
		body.add_child(col)

	if col.shape == null:
		col.shape = BoxShape.new()

	return body

func _find_shaft_cap_bottom_local_y():
	var elevator_root = _find_elevator_root()
	if elevator_root == null:
		return null

	var cap_node = elevator_root.get_node_or_null("MetalFence/Path2/CSGCylinder")
	if cap_node == null:
		return null
	if not (cap_node is Spatial):
		return null

	var cap_spatial := cap_node as Spatial
	var bottom_global_y = INF

	if cap_spatial is VisualInstance:
		var vi := cap_spatial as VisualInstance
		var aabb := vi.get_transformed_aabb()
		bottom_global_y = aabb.position.y
	else:
		var h = cap_spatial.get("height")
		if typeof(h) == TYPE_REAL or typeof(h) == TYPE_INT:
			bottom_global_y = cap_spatial.global_transform.origin.y - float(h) * 0.5

	if bottom_global_y == INF:
		return null

	var sample_global := global_transform.origin
	sample_global.y = bottom_global_y
	return to_local(sample_global).y

func _find_elevator_root() -> Spatial:
	var node := get_parent()
	while node != null:
		if node is Spatial and node.has_node("MetalFence/Path2"):
			return node as Spatial
		node = node.get_parent()
	return null
