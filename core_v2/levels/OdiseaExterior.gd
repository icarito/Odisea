extends Spatial

export(int, 0, 3) var selected_spiral := 0
export(int, 0, 10000) var selected_plate := 0
export(bool) var snap_on_selection := true
export(PackedScene) var plate_content_scene
export(int, -1, 8) var dome_full_detail_plate_radius := 1
export(int, 0, 8) var dome_full_detail_preload_extra_radius := 2
export(bool) var dome_lod_enabled := true

onready var _rotator: Spatial = $WorldRotator
onready var _physical_terrace: StaticBody = $PhysicalTerrace
onready var _player: Spatial = $Pilot
onready var _camera: Camera = $Pilot/CameraRig/Yaw/Pitch/SpringArm/Camera
onready var _plate_content_stream: Spatial = get_node_or_null("PlateContentRoot") as Spatial

var _spirals: Array = []
var _selected_plate_canonical := Transform.IDENTITY
var _dome_lod_blueprint_cache := {}
var _scene_bounds_cache := {}
# Cursor pre-instanciado: una sola DomeFacade por tipo, se reposiciona al plate activo
var _dome_facade_cursors: Dictionary = {}  # facade_scene_path -> Spatial
var _active_dome_facade_path := ""            # camino del cursor activo (para tick por frame)
var _active_dome_facade_spawn_offset := Vector3.ZERO
var _lod_hidden_spiral := -1                  # spiral cuyo plate activo tiene LOD oculto
var _lod_hidden_plate := -1

func _ready() -> void:
	_collect_spirals()
	_configure_test_rotator()
	_configure_plate_content_stream()
	if has_node("/root/GravityWorld"):
		GravityWorld.set_ship_axis(Vector3.ZERO, Vector3.UP)
	
	_resolve_spawn_state()
	call_deferred("apply_selection")
	call_deferred("_setup_dome_facade_cursors")

func _process(_delta: float) -> void:
	_sync_selection_from_rotator()
	_tick_dome_facade_cursor()  # sigue la animación/rotación del WorldRotator cada frame
	_reset_camera_roll()

func _resolve_spawn_state() -> void:
	if not has_node("/root/SceneManager"):
		return
	var scene_manager = get_node("/root/SceneManager")
	var params = scene_manager.get("_transition_params")
	if typeof(params) == TYPE_DICTIONARY:
		var spawn_id = params.get("target_spawn_id", params.get("spawn_id", ""))
		var dome_id = DomeRegistry.find_dome_id_by_interior_spawn(String(spawn_id))
		if dome_id != "":
			var info = DomeRegistry.get_dome(dome_id)
			selected_spiral = info.get("spiral_index", 0)
			selected_plate = info.get("plate_index", 0)
			snap_on_selection = true

func apply_selection() -> void:
	_collect_spirals()
	if _spirals.empty():
		printerr("[OdiseaExterior] No TerraceSpiral nodes found under WorldRotator")
		return
	selected_spiral = _wrap_index(selected_spiral, _spirals.size())
	_force_spiral_update()

	var spiral: Spatial = _spirals[selected_spiral]
	var plate_count: int = _get_plate_count(spiral)
	if plate_count <= 0:
		printerr("[OdiseaExterior] Selected TerraceSpiral has no plates: ", spiral.name)
		return

	selected_plate = int(clamp(selected_plate, 0, plate_count - 1))
	if not _rotator.select_terrace_plate(selected_spiral, selected_plate, null, snap_on_selection):
		printerr("[OdiseaExterior] Could not select generated terrace collision")
		return
	_rotator.scene_anchor_spiral_index = selected_spiral
	_rotator.scene_anchor_plate_index = selected_plate
	if _rotator.has_method("_apply_scene_anchor"):
		_rotator.call("_apply_scene_anchor")
	var plate_canonical: Transform = _rotator.get_selected_plate_canonical_transform()
	_selected_plate_canonical = plate_canonical
	_configure_gravity_for_selected_plate(plate_canonical)
	_assign_plate_content()
	_rotator.auto_track_target_plate = true

func get_selected_plate_global_transform() -> Transform:
	return _rotator.get_selected_plate_global_transform()

func get_physical_terrace_transform() -> Transform:
	if _physical_terrace:
		return _physical_terrace.global_transform
	return _rotator.get_active_collision_transform()

func get_active_collision_body() -> StaticBody:
	return _rotator.get_active_collision_body()

func get_generated_collision_count() -> int:
	return _rotator.get_generated_collision_count()

func get_plate_content_stream() -> Spatial:
	return _plate_content_stream

func get_streamed_pushable_boxes() -> Array:
	if _plate_content_stream and _plate_content_stream.has_method("get_streamed_nodes_in_group"):
		var boxes: Array = _plate_content_stream.get_streamed_nodes_in_group("pushable_box")
		if boxes.empty():
			boxes = _plate_content_stream.get_streamed_nodes_in_group("pushable")
		return boxes
	return []

func _set_spiral(value: int) -> void:
	selected_spiral = _wrap_index(value, int(max(1, _spirals.size())))
	apply_selection()

func _set_plate(value: int) -> void:
	selected_plate = value
	apply_selection()

func _set_blend(value: float) -> void:
	_rotator.spiral_blend = value
	apply_selection()

func _configure_test_rotator() -> void:
	if not _rotator:
		return
	_rotator.spiral_blend = 1.0
	_rotator.auto_select_first_platform = false
	_rotator.auto_track_target_plate = false
	_rotator.auto_track_requires_floor_contact = true
	_rotator.tracking_target_path = NodePath("../Pilot")
	_rotator.physical_terrace_path = NodePath("../PhysicalTerrace")
	_rotator.collision_pool_size = max(_rotator.collision_pool_size, 32)
	_rotator.collision_update_interval = 3

func _configure_plate_content_stream() -> void:
	if not _plate_content_stream:
		return
	_plate_content_stream.rotator_path = NodePath("../WorldRotator")
	_plate_content_stream.tracking_target_path = NodePath("../Pilot")
	_plate_content_stream.slot_pool_size = 16
	_plate_content_stream.slot_update_interval = 1
	if _plate_content_stream.has_method("register_rotator"):
		_plate_content_stream.register_rotator(_rotator)

func _assign_plate_content() -> void:
	if not _plate_content_stream:
		return
	if _spirals.empty():
		return
	if _plate_content_stream.has_method("register_rotator"):
		_plate_content_stream.register_rotator(_rotator)
	if _plate_content_stream.has_method("begin_bulk_assignments"):
		_plate_content_stream.begin_bulk_assignments()
	var dome_lod_assignments := []

	for spiral_index in range(_spirals.size()):
		var spiral: Spatial = _spirals[spiral_index]
		var plate_count: int = _get_plate_count(spiral)
		if plate_count <= 0:
			continue
		for plate_index in range(plate_count):
			var dome_id := DomeRegistry.get_dome_id_for_plate(spiral_index, plate_index)
			var info := DomeRegistry.get_dome(dome_id)
			# Si hay blueprint LOD, la visual la maneja el LOD MultiMesh (todas las terrazas).
			# El cursor maneja la facade full-detail solo para domos explícitos.
			if info.empty() or not (dome_lod_enabled and _has_dome_lod_blueprint(info)):
				if plate_content_scene != null:
					_plate_content_stream.assign_scene(spiral_index, plate_index, plate_content_scene)
				continue
			_plate_content_stream.assign_scene(spiral_index, plate_index, null)
			dome_lod_assignments.append({
				"dome_id": dome_id,
				"spiral_index": spiral_index,
				"plate_index": plate_index,
				"info": info
			})
	if _plate_content_stream.has_method("end_bulk_assignments"):
		_plate_content_stream.end_bulk_assignments()
	_update_dome_lod(dome_lod_assignments)

func _should_use_dome_lod(info: Dictionary, dome_spiral_idx: int, dome_plate_idx: int) -> bool:
	if not dome_lod_enabled:
		return false
	if not _has_dome_lod_blueprint(info):
		return false
	if dome_full_detail_plate_radius < 0:
		return false
	if dome_spiral_idx != selected_spiral:
		return true
	if dome_spiral_idx < 0 or dome_spiral_idx >= _spirals.size():
		return false
	var plate_count := _get_plate_count(_spirals[dome_spiral_idx])
	if plate_count <= 0:
		return false
	return _get_wrapped_plate_distance(selected_plate, dome_plate_idx, plate_count) > dome_full_detail_plate_radius

func _should_prewarm_full_detail_dome(info: Dictionary, dome_spiral_idx: int, dome_plate_idx: int) -> bool:
	if not dome_lod_enabled:
		return false
	if dome_full_detail_preload_extra_radius <= 0:
		return false
	if not _has_dome_lod_blueprint(info):
		return false
	if dome_full_detail_plate_radius < 0:
		return false
	if dome_spiral_idx != selected_spiral:
		return false
	if dome_spiral_idx < 0 or dome_spiral_idx >= _spirals.size():
		return false
	var plate_count := _get_plate_count(_spirals[dome_spiral_idx])
	if plate_count <= 0:
		return false
	var distance := _get_wrapped_plate_distance(selected_plate, dome_plate_idx, plate_count)
	return _is_distance_within_full_detail_prewarm(distance)

func _is_distance_within_full_detail_prewarm(distance: int) -> bool:
	return distance > dome_full_detail_plate_radius and distance <= dome_full_detail_plate_radius + dome_full_detail_preload_extra_radius

func _get_wrapped_plate_distance(from_plate: int, to_plate: int, plate_count: int) -> int:
	if plate_count <= 0:
		return 0
	var direct := abs(to_plate - from_plate)
	return int(min(direct, plate_count - direct))

func _update_dome_lod(assignments: Array) -> void:
	var groups_by_spiral := {}
	for assignment in assignments:
		var info: Dictionary = assignment.get("info", {})
		var blueprint := _resolve_dome_lod_blueprint(info)
		if blueprint.empty():
			continue
		var spiral_index := int(assignment.get("spiral_index", -1))
		if spiral_index < 0 or spiral_index >= _spirals.size():
			continue
		var cache_key := String(blueprint.get("cache_key", "")).strip_edges()
		if cache_key == "":
			cache_key = String(assignment.get("dome_id", "lod"))
		if not groups_by_spiral.has(spiral_index):
			groups_by_spiral[spiral_index] = {}
		if not groups_by_spiral[spiral_index].has(cache_key):
			groups_by_spiral[spiral_index][cache_key] = {"blueprint": blueprint, "items": []}
		groups_by_spiral[spiral_index][cache_key]["items"].append(assignment)

	for spiral_index in range(_spirals.size()):
		var spiral: Spatial = _spirals[spiral_index]
		if not (spiral is TerraceSpiral):
			continue
		if not groups_by_spiral.has(spiral_index):
			spiral.clear_dome_lod_overlays()
			continue
		var spiral_groups := _build_spiral_dome_lod_groups(groups_by_spiral[spiral_index])
		spiral.set_dome_lod_overlays(spiral_groups)

func _build_spiral_dome_lod_groups(spiral_group_map: Dictionary) -> Array:
	var groups := []
	for cache_key in spiral_group_map.keys():
		var group: Dictionary = spiral_group_map[cache_key]
		var blueprint: Dictionary = group.get("blueprint", {})
		var items: Array = group.get("items", [])
		var parts: Array = blueprint.get("parts", [])
		if parts.empty() or items.empty():
			continue
		var group_parts := []
		for part_index in range(parts.size()):
			var part: Dictionary = parts[part_index]
			var mesh: Mesh = _build_mesh_for_multimesh_part(part)
			if mesh == null:
				continue
			var overlay_items := []
			var signature_parts := PoolStringArray()
			for item in items:
				var info: Dictionary = item.get("info", {})
				var plate_index := int(item.get("plate_index", -1))
				var lod_scale: Vector3 = _resolve_effective_dome_lod_scale(info, blueprint)
				var scaled_local := _scale_transform(part.get("local_transform", Transform.IDENTITY), lod_scale)
				var origin_offset: Vector3 = info.get("facade_spawn_offset", Vector3.ZERO)
				overlay_items.append({
					"plate_index": plate_index,
					"local_transform": scaled_local,
					"origin_offset": origin_offset
				})
				signature_parts.append("%d:%s:%s" % [plate_index, var2str(scaled_local.origin), var2str(origin_offset)])
			group_parts.append({
				"mesh": mesh,
				"material_override": part.get("material_override", null),
				"items": overlay_items,
				"signature": "%s|%d|%s" % [cache_key, part_index, signature_parts.join(",")]
			})
		if not group_parts.empty():
			groups.append({
				"key": String(cache_key),
				"parts": group_parts
			})
	return groups

func _has_dome_lod_blueprint(info: Dictionary) -> bool:
	return not _resolve_dome_lod_blueprint(info).empty()

func _resolve_dome_lod_blueprint(info: Dictionary) -> Dictionary:
	var mesh_path := String(info.get("facade_lod_mesh", "")).strip_edges()
	if mesh_path != "":
		var mesh_key := "mesh|%s" % mesh_path
		if _dome_lod_blueprint_cache.has(mesh_key):
			return _dome_lod_blueprint_cache[mesh_key]
		if ResourceLoader.exists(mesh_path):
			var mesh_resource = load(mesh_path)
			if mesh_resource is Mesh:
				var blueprint := {
					"parts": [{
						"mesh": mesh_resource,
						"local_transform": Transform.IDENTITY,
						"material_override": null,
						"surface_materials": [],
						"aabb": mesh_resource.get_aabb()
					}],
					"aabb": mesh_resource.get_aabb(),
					"aabb_size": mesh_resource.get_aabb().size,
					"cache_key": mesh_key
				}
				_dome_lod_blueprint_cache[mesh_key] = blueprint
				return blueprint

	var scene_path := String(info.get("facade_lod_scene", "")).strip_edges()
	if scene_path == "":
		return {}
	var mesh_node_path := String(info.get("facade_lod_mesh_node", "")).strip_edges()
	var scene_key := "scene|%s|%s" % [scene_path, mesh_node_path]
	if _dome_lod_blueprint_cache.has(scene_key):
		return _dome_lod_blueprint_cache[scene_key]
	if not ResourceLoader.exists(scene_path):
		return {}
	var scene_resource = load(scene_path)
	if not (scene_resource is PackedScene):
		return {}
	var scene_root = scene_resource.instance()
	if not is_instance_valid(scene_root):
		return {}
	var mesh_blueprint := _extract_dome_lod_blueprint(scene_root, mesh_node_path)
	scene_root.free()
	if mesh_blueprint.empty():
		return {}
	mesh_blueprint["cache_key"] = scene_key
	_dome_lod_blueprint_cache[scene_key] = mesh_blueprint
	return mesh_blueprint

func _extract_dome_lod_blueprint(root: Node, mesh_node_path: String) -> Dictionary:
	var search_root: Node = root
	if mesh_node_path != "":
		var explicit_node = root.get_node_or_null(mesh_node_path)
		if explicit_node != null:
			search_root = explicit_node
	var parts := _collect_mesh_instance_parts(search_root, root)
	if parts.empty():
		return {}
	var parts_aabb := _compute_parts_aabb(parts)
	return {
		"parts": parts,
		"aabb": parts_aabb,
		"aabb_size": parts_aabb.size
	}

func _collect_mesh_instance_parts(search_root: Node, root: Node) -> Array:
	var parts := []
	_collect_mesh_instance_parts_recursive(search_root, root, parts)
	return parts

func _collect_mesh_instance_parts_recursive(node: Node, root: Node, parts: Array) -> void:
	if node is MeshInstance and node.mesh != null:
		var mesh_instance := node as MeshInstance
		var local_transform := _get_transform_relative_to_root(mesh_instance, root)
		parts.append({
			"mesh": mesh_instance.mesh,
			"local_transform": local_transform,
			"material_override": mesh_instance.material_override,
			"surface_materials": _get_mesh_instance_surface_materials(mesh_instance),
			"aabb": _transform_aabb(mesh_instance.mesh.get_aabb(), local_transform)
		})
	for child in node.get_children():
		_collect_mesh_instance_parts_recursive(child, root, parts)

func _get_mesh_instance_surface_materials(mesh_instance: MeshInstance) -> Array:
	var materials := []
	if mesh_instance.mesh == null:
		return materials
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		materials.append(mesh_instance.get_surface_material(surface_index))
	return materials

func _build_mesh_for_multimesh_part(part: Dictionary) -> Mesh:
	var mesh: Mesh = part.get("mesh", null)
	if mesh == null:
		return null
	var surface_materials: Array = part.get("surface_materials", [])
	var has_override := false
	for material in surface_materials:
		if material != null:
			has_override = true
			break
	if not has_override:
		return mesh
	var duplicated = mesh.duplicate()
	if not (duplicated is Mesh):
		return mesh
	for surface_index in range(min(duplicated.get_surface_count(), surface_materials.size())):
		if surface_materials[surface_index] != null:
			duplicated.surface_set_material(surface_index, surface_materials[surface_index])
	return duplicated

func _resolve_effective_dome_lod_scale(info: Dictionary, blueprint: Dictionary) -> Vector3:
	var configured_scale: Vector3 = info.get("facade_lod_scale", Vector3.ONE)
	var source_size: Vector3 = blueprint.get("aabb_size", Vector3.ONE)
	var target_size: Vector3 = _resolve_facade_reference_size(info)
	var fit_scale := _resolve_uniform_fit_scale_for_sizes(source_size, target_size)
	return configured_scale * fit_scale

func _resolve_facade_reference_size(info: Dictionary) -> Vector3:
	var facade_scene_path := String(info.get("facade_scene", "")).strip_edges()
	if facade_scene_path == "":
		return Vector3.ONE
	if _scene_bounds_cache.has(facade_scene_path):
		return _scene_bounds_cache[facade_scene_path]
	if not ResourceLoader.exists(facade_scene_path):
		return Vector3.ONE
	var facade_scene = load(facade_scene_path)
	if not (facade_scene is PackedScene):
		return Vector3.ONE
	var facade_root = facade_scene.instance()
	if not is_instance_valid(facade_root):
		return Vector3.ONE
	var blueprint := _extract_dome_lod_blueprint(facade_root, "")
	facade_root.free()
	var size: Vector3 = blueprint.get("aabb_size", Vector3.ONE)
	_scene_bounds_cache[facade_scene_path] = size
	return size

func _resolve_uniform_fit_scale_for_sizes(source_size: Vector3, target_size: Vector3) -> float:
	var ratios := []
	if source_size.x > 0.001 and target_size.x > 0.001:
		ratios.append(target_size.x / source_size.x)
	if source_size.y > 0.001 and target_size.y > 0.001:
		ratios.append(target_size.y / source_size.y)
	if source_size.z > 0.001 and target_size.z > 0.001:
		ratios.append(target_size.z / source_size.z)
	if ratios.empty():
		return 1.0
	var fit_scale := float(ratios[0])
	for ratio in ratios:
		fit_scale = min(fit_scale, float(ratio))
	return fit_scale

func _compute_parts_aabb(parts: Array) -> AABB:
	if parts.empty():
		return AABB(Vector3.ZERO, Vector3.ONE)
	var merged: AABB = parts[0].get("aabb", AABB(Vector3.ZERO, Vector3.ONE))
	for i in range(1, parts.size()):
		merged = merged.merge(parts[i].get("aabb", AABB(Vector3.ZERO, Vector3.ONE)))
	return merged

func _transform_aabb(aabb: AABB, xform: Transform) -> AABB:
	var corners := [
		xform.xform(aabb.position),
		xform.xform(aabb.position + Vector3(aabb.size.x, 0, 0)),
		xform.xform(aabb.position + Vector3(0, aabb.size.y, 0)),
		xform.xform(aabb.position + Vector3(0, 0, aabb.size.z)),
		xform.xform(aabb.position + Vector3(aabb.size.x, aabb.size.y, 0)),
		xform.xform(aabb.position + Vector3(aabb.size.x, 0, aabb.size.z)),
		xform.xform(aabb.position + Vector3(0, aabb.size.y, aabb.size.z)),
		xform.xform(aabb.position + aabb.size)
	]
	var result := AABB(corners[0], Vector3.ZERO)
	for i in range(1, corners.size()):
		result = result.expand(corners[i])
	return result

func _get_transform_relative_to_root(node: Spatial, root: Node) -> Transform:
	var current: Node = node
	var accumulated := Transform.IDENTITY
	while current != null and current != root:
		if current is Spatial:
			accumulated = (current as Spatial).transform * accumulated
		current = current.get_parent()
	return accumulated

func _scale_transform(local_transform: Transform, scale: Vector3) -> Transform:
	var scaled_origin := Vector3(
		local_transform.origin.x * scale.x,
		local_transform.origin.y * scale.y,
		local_transform.origin.z * scale.z
	)
	return Transform(local_transform.basis.scaled(scale), scaled_origin)

func _sync_selection_from_rotator() -> void:
	if not _rotator:
		return
	if not _rotator.has_method("get_selected_spiral_index") or not _rotator.has_method("get_selected_plate_index"):
		return
	var rotator_spiral: int = _rotator.get_selected_spiral_index()
	var rotator_plate: int = _rotator.get_selected_plate_index()
	if rotator_spiral < 0 or rotator_plate < 0:
		return
	if rotator_spiral == selected_spiral and rotator_plate == selected_plate:
		_selected_plate_canonical = _rotator.get_selected_plate_canonical_transform()
		return
	selected_spiral = rotator_spiral
	selected_plate = rotator_plate
	_selected_plate_canonical = _rotator.get_selected_plate_canonical_transform()
	_configure_gravity_for_selected_plate(_selected_plate_canonical)
	# Posicionar el cursor ANTES de ocultar el LOD para evitar el frame vacío
	_sync_dome_facade_cursor()
	_apply_lod_hide_for_selection(selected_spiral, selected_plate)

func _collect_spirals() -> void:
	_spirals.clear()
	for name in ["TerraceSpiral", "TerraceSpiral2", "TerraceSpiral3", "TerraceSpiral4"]:
		var spiral: Node = _rotator.get_node_or_null(name)
		if spiral:
			_spirals.append(spiral)

func _force_spiral_update() -> void:
	for spiral in _spirals:
		if spiral.has_method("_rebuild_multimesh_if_needed"):
			spiral.call("_rebuild_multimesh_if_needed")
		if spiral.has_method("_update_spiral_animation"):
			spiral.call("_update_spiral_animation")

func _get_plate_count(spiral: Spatial) -> int:
	return _rotator.get_plate_count(spiral)

func _get_plate_canonical_transform(spiral: Spatial, plate_index: int) -> Transform:
	return _rotator.get_plate_canonical_transform(spiral, plate_index)

func _wrap_index(value: int, size: int) -> int:
	if size <= 0:
		return 0
	var wrapped: int = value % size
	if wrapped < 0:
		wrapped += size
	return wrapped

func _respawn_player() -> void:
	var player: Node = get_node_or_null("Pilot")
	if player is Spatial:
		player.global_transform.origin = _rotator.get_active_collision_transform().origin + Vector3(0, 3, 3)
		if player.has_method("set_external_velocity"):
			player.set_external_velocity(Vector3.ZERO)

func _configure_gravity_for_selected_plate(plate_canonical: Transform) -> void:
	if not has_node("/root/GravityWorld"):
		return
	var radius: float = GravityWorld.get_axis_radius(plate_canonical.origin)
	GravityWorld.set_centrifugal_reference_radius(radius)
	GravityWorld.set_ship_angular_velocity(GravityWorld.get_default_angular_velocity_for_one_g(radius))

func _reset_camera_roll() -> void:
	if not _camera:
		return
	_camera.rotation.z = 0.0

# --- DomeFacade Cursor ---
# Pre-instancia una DomeFacade por tipo de escena y la reposiciona al plate activo.
# Evita instanciar/destruir la escena costosa en cada cambio de selección.

func _setup_dome_facade_cursors() -> void:
	var seen_paths := {}
	for dome_id in DomeRegistry.get_all_dome_ids():
		var info := DomeRegistry.get_dome(dome_id)
		var path := String(info.get("facade_scene", "")).strip_edges()
		if path == "" or seen_paths.has(path):
			continue
		if not ResourceLoader.exists(path):
			continue
		var packed = load(path)
		if not (packed is PackedScene):
			continue
		var cursor: Spatial = (packed as PackedScene).instance()
		cursor.name = "DomeFacadeCursor_%s" % path.get_file().get_basename()
		# Aparcar fuera del mundo hasta que se seleccione un plate con domo
		cursor.global_transform = Transform(Basis.IDENTITY, Vector3(0.0, -99999.0, 0.0))
		add_child(cursor)
		_dome_facade_cursors[path] = cursor
		seen_paths[path] = true
	_sync_dome_facade_cursor()
	_apply_lod_hide_for_selection(selected_spiral, selected_plate)

func _sync_dome_facade_cursor() -> void:
	if not _rotator or not is_instance_valid(_rotator):
		return
	var cur_spiral := int(_rotator.get_selected_spiral_index()) if _rotator.has_method("get_selected_spiral_index") else -1
	var cur_plate := int(_rotator.get_selected_plate_index()) if _rotator.has_method("get_selected_plate_index") else -1
	if cur_spiral < 0 or cur_plate < 0:
		_park_all_dome_facade_cursors()
		return

	var dome_id := DomeRegistry.get_dome_id_for_plate(cur_spiral, cur_plate)
	var info := DomeRegistry.get_dome(dome_id)
	# Usar facade_scene del registro (get_dome ya devuelve DomeFacade_01 por defecto para domos sintéticos)
	var facade_path := String(info.get("facade_scene", "")).strip_edges()

	for path in _dome_facade_cursors.keys():
		var cursor: Spatial = _dome_facade_cursors[path]
		if not is_instance_valid(cursor):
			continue
		if path != facade_path:
			cursor.global_transform = Transform(Basis.IDENTITY, Vector3(0.0, -99999.0, 0.0))
			if cursor.has_meta("dome_id"):
				cursor.remove_meta("dome_id")

	if facade_path == "" or not _dome_facade_cursors.has(facade_path):
		_active_dome_facade_path = ""
		return

	var active_cursor: Spatial = _dome_facade_cursors[facade_path]
	if not is_instance_valid(active_cursor):
		_active_dome_facade_path = ""
		return

	var spawn_offset: Vector3 = info.get("facade_spawn_offset", Vector3.ZERO)
	# Cachear para que _tick_dome_facade_cursor() pueda actualizar el transform cada frame
	_active_dome_facade_path = facade_path
	_active_dome_facade_spawn_offset = spawn_offset
	# Posicionar usando transform vivo (sigue animación de la espiral)
	_tick_dome_facade_cursor()

	# Fijar dome_id como meta directamente en el cursor para que AirlockZoneV2
	# pueda encontrarlo traversando hacia arriba en el árbol de nodos.
	active_cursor.set_meta("dome_id", dome_id)
	# También propagar contexto a hijos que lo acepten (solo en cambio)
	var context := {"dome_id": dome_id}
	if active_cursor.has_method("apply_plate_content_context"):
		active_cursor.apply_plate_content_context(context)
	for child in active_cursor.get_children():
		if child.has_method("apply_plate_content_context"):
			child.apply_plate_content_context(context)

func _tick_dome_facade_cursor() -> void:
	# Actualiza SOLO el transform del cursor activo cada frame para seguir la rotación
	# de WorldRotator y la animación blend de TerraceSpiral.
	if _active_dome_facade_path == "":
		return
	if not _dome_facade_cursors.has(_active_dome_facade_path):
		return
	var active_cursor: Spatial = _dome_facade_cursors[_active_dome_facade_path]
	if not is_instance_valid(active_cursor):
		return
	var cur_spiral := int(_rotator.get_selected_spiral_index()) if _rotator.has_method("get_selected_spiral_index") else -1
	var cur_plate := int(_rotator.get_selected_plate_index()) if _rotator.has_method("get_selected_plate_index") else -1
	if cur_spiral < 0 or cur_spiral >= _spirals.size() or cur_plate < 0:
		return
	var spiral: Spatial = _spirals[cur_spiral]
	var canonical_tx: Transform = _rotator.get_plate_canonical_transform(spiral, cur_plate)
	var world_tx: Transform = _rotator.global_transform * canonical_tx
	# spawn_offset es world-space: añadir directamente sin rotar
	active_cursor.global_transform = Transform(world_tx.basis, world_tx.origin + _active_dome_facade_spawn_offset)

func _park_all_dome_facade_cursors() -> void:
	_active_dome_facade_path = ""
	for path in _dome_facade_cursors.keys():
		var cursor: Spatial = _dome_facade_cursors[path]
		if is_instance_valid(cursor):
			cursor.global_transform = Transform(Basis.IDENTITY, Vector3(0.0, -99999.0, 0.0))
			if cursor.has_meta("dome_id"):
				cursor.remove_meta("dome_id")

func _apply_lod_hide_for_selection(new_spiral: int, new_plate: int) -> void:
	# Quita el LOD del plate anterior y oculta el del plate nuevo (el cursor lo cubre)
	if _lod_hidden_spiral >= 0 and _lod_hidden_spiral < _spirals.size():
		var old_spiral: Spatial = _spirals[_lod_hidden_spiral]
		if old_spiral.has_method("set_dome_lod_plate_hidden"):
			old_spiral.call("set_dome_lod_plate_hidden", _lod_hidden_plate, false)
	_lod_hidden_spiral = -1
	_lod_hidden_plate = -1
	if new_spiral < 0 or new_spiral >= _spirals.size():
		return
	var spiral: Spatial = _spirals[new_spiral]
	if spiral.has_method("set_dome_lod_plate_hidden"):
		spiral.call("set_dome_lod_plate_hidden", new_plate, true)
	_lod_hidden_spiral = new_spiral
	_lod_hidden_plate = new_plate
