extends Spatial

export(int, 0, 3) var selected_spiral := 0
export(int, 0, 10000) var selected_plate := 0
export(bool) var snap_on_selection := true
export(PackedScene) var plate_content_scene
export(int, -1, 8) var dome_full_detail_plate_radius := 1
export(int, 0, 64) var dome_full_detail_nearest_count := 3
export(int, 0, 3) var dome_full_detail_spiral_radius := 1
export(int, 0, 32) var dome_inter_spiral_plate_offset := 4
export(int, 0, 8) var dome_full_detail_preload_extra_radius := 2
export(bool) var dome_lod_enabled := true
export(int, 0, 1024) var dome_lod_overlay_max_instances := 64
export(int, 4, 64) var exterior_collision_pool_size := 4
export(int, 1, 30) var exterior_collision_update_interval := 8
export(int, 1, 30) var exterior_target_plate_query_interval := 6

onready var _rotator: Spatial = $WorldRotator
onready var _physical_terrace: StaticBody = $PhysicalTerrace
onready var _player: Spatial = $Pilot
onready var _camera: Camera = null
onready var _plate_content_stream: Spatial = get_node_or_null("PlateContentRoot") as Spatial
onready var _segment_manager: Spatial = get_node_or_null("WorldRotator/TerraceSegmentManager") as Spatial

var _spirals: Array = []
var _selected_plate_canonical := Transform.IDENTITY
var _dome_lod_blueprint_cache := {}
var _scene_bounds_cache := {}
# Cursor pre-instanciado: una sola DomeFacade por tipo, se reposiciona al plate activo
var _dome_facade_cursors: Dictionary = {}  # facade_scene_path -> Spatial
var _active_dome_facade_path := ""            # camino del cursor activo (para tick por frame)
var _active_dome_facade_spawn_offset := Vector3.ZERO
var _lod_hidden_plate_keys := {}              # "spiral:plate" -> true, plates cubiertos por LOD2
var _last_dome_lod_stats := {}
var _last_full_detail_keys := {}
var _last_full_detail_debug_rows := []
var _spatial_full_detail_candidates_cache := []
var _spatial_full_detail_candidates_signature := ""
var _dome_assignment_cache := {}       # "spiral:plate" -> cached dome assignment
var _dome_lod_assignment_keys := []     # Array[String]
var _dome_assignment_cache_ready := false
var _packed_scene_cache := {}

func _ready() -> void:
	if has_node("/root/SessionManager"):
		get_node("/root/SessionManager").register_oys_actor("Odisea", self)
	_camera = _resolve_player_camera()
	_collect_spirals()
	_configure_test_rotator()
	_configure_segment_manager()
	_configure_plate_content_stream()
	var gravity_world: Node = get_node_or_null("/root/GravityWorld")
	if gravity_world:
		gravity_world.set_ship_axis(Vector3.ZERO, Vector3.UP)
	
	_resolve_spawn_state()
	call_deferred("apply_selection")
	call_deferred("_setup_dome_facade_cursors")

func _exit_tree() -> void:
	if has_node("/root/SessionManager"):
		get_node("/root/SessionManager").unregister_oys_actor("Odisea")

func _resolve_player_camera() -> Camera:
	if _player == null or not is_instance_valid(_player):
		return null
	var camera := _player.get_node_or_null("CameraRig/Yaw/Pitch/OTS_Offset/SpringArm/Camera") as Camera
	if camera:
		return camera
	camera = _player.get_node_or_null("CameraRig/Yaw/Pitch/SpringArm/Camera") as Camera
	return camera

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
		var dome_registry: Node = _get_dome_registry()
		var dome_id = dome_registry.find_dome_id_by_interior_spawn(String(spawn_id)) if dome_registry else ""
		if dome_id != "":
			var info = dome_registry.get_dome(dome_id)
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
	_rotator.auto_select_first_platform = false
	_rotator.auto_track_target_plate = false
	_rotator.auto_track_requires_floor_contact = true
	_rotator.tracking_target_path = NodePath("../Pilot")
	_rotator.physical_terrace_path = NodePath("../PhysicalTerrace")
	_rotator.centrifugal_current_plate_only_physics = false
	_rotator.collision_pool_size = int(clamp(exterior_collision_pool_size, 4, 64))
	_rotator.collision_update_interval = int(clamp(exterior_collision_update_interval, 1, 30))
	_rotator.target_plate_query_interval = int(clamp(exterior_target_plate_query_interval, 1, 30))

func _configure_plate_content_stream() -> void:
	if not _plate_content_stream:
		return
	_plate_content_stream.rotator_path = NodePath("../WorldRotator")
	_plate_content_stream.tracking_target_path = NodePath("../Pilot")
	_plate_content_stream.slot_pool_size = 3
	_plate_content_stream.slot_update_interval = 3
	_plate_content_stream.centrifugal_current_plate_only_physics = false
	if _plate_content_stream.has_method("register_rotator"):
		_plate_content_stream.register_rotator(_rotator)

func _configure_segment_manager() -> void:
	if not _segment_manager:
		return
	if _segment_manager.has_method("register_rotator"):
		_segment_manager.register_rotator(_rotator)
	if _segment_manager.get("full_detail_plate_radius") != null:
		_segment_manager.set("full_detail_plate_radius", int(max(0, dome_full_detail_plate_radius)))
	if _segment_manager.get("full_detail_nearest_count") != null:
		_segment_manager.set("full_detail_nearest_count", int(max(0, dome_full_detail_nearest_count)))

func _assign_plate_content() -> void:
	_ensure_dome_assignment_cache()
	_sync_plate_window_for_selection(true)

func _ensure_dome_assignment_cache() -> void:
	if _dome_assignment_cache_ready:
		return
	_dome_assignment_cache.clear()
	_dome_lod_assignment_keys.clear()
	if not _plate_content_stream:
		return
	if _spirals.empty():
		return
	var dome_registry: Node = _get_dome_registry()
	if not dome_registry:
		return
	for spiral_index in range(_spirals.size()):
		var spiral: Spatial = _spirals[spiral_index]
		var plate_count: int = _get_plate_count(spiral)
		if plate_count <= 0:
			continue
		for plate_index in range(plate_count):
			var dome_id: String = dome_registry.get_dome_id_for_plate(spiral_index, plate_index)
			var info: Dictionary = dome_registry.get_dome(dome_id)
			if info.empty():
				continue
			var plate_key := _make_plate_key(spiral_index, plate_index)
			var facade_scene_path := String(info.get("facade_scene", "")).strip_edges()
			var facade_scene := _load_packed_scene_cached(facade_scene_path)
			var blueprint := _resolve_dome_lod_blueprint(info)
			var assignment := {
				"key": plate_key,
				"dome_id": dome_id,
				"spiral_index": spiral_index,
				"plate_index": plate_index,
				"info": info.duplicate(true),
				"facade_scene": facade_scene,
				"facade_spawn_offset": info.get("facade_spawn_offset", Vector3.ZERO),
				"blueprint": blueprint,
				"has_lod_blueprint": not blueprint.empty()
			}
			_dome_assignment_cache[plate_key] = assignment
			if bool(assignment["has_lod_blueprint"]):
				_dome_lod_assignment_keys.append(plate_key)
	_dome_assignment_cache_ready = true

func _sync_plate_window_for_selection(force: bool = false) -> void:
	if not _plate_content_stream:
		return
	_ensure_dome_assignment_cache()
	var lod_mode := _get_dome_lod_mode()
	if lod_mode == "off":
		if _plate_content_stream.has_method("set_active_assignments"):
			_plate_content_stream.set_active_assignments({})
		_update_dome_lod([])
		_apply_lod_hide_for_full_detail_keys({})
		_last_full_detail_keys = {}
		return

	var full_detail_keys := _get_streamed_full_detail_plate_keys_for_selection()
	var stream_assignments := _build_stream_assignments_for_keys(full_detail_keys)
	if _plate_content_stream.has_method("set_active_assignments"):
		_plate_content_stream.set_active_assignments(stream_assignments)
	else:
		_sync_stream_assignments_legacy(stream_assignments)

	if lod_mode == "lod":
		var lod_assignments := _build_lod_overlay_assignments_for_selection()
		_update_dome_lod(lod_assignments)
	else:
		_update_dome_lod(_build_assignments_for_keys(full_detail_keys))

	_apply_lod_hide_for_full_detail_keys(full_detail_keys)
	_last_full_detail_keys = full_detail_keys

func _build_stream_assignments_for_keys(keys: Dictionary) -> Dictionary:
	var assignments := {}
	for key in keys.keys():
		if not _dome_assignment_cache.has(key):
			continue
		var cached: Dictionary = _dome_assignment_cache[key]
		var scene: PackedScene = cached.get("facade_scene", null)
		if scene == null:
			continue
		var spiral_idx := int(cached.get("spiral_index", -1))
		var plate_idx := int(cached.get("plate_index", -1))
		assignments[key] = {
			"scene": scene,
			"spiral_idx": spiral_idx,
			"plate_idx": plate_idx,
			"spawn_offset": cached.get("facade_spawn_offset", Vector3.ZERO),
			"context": {"dome_id": String(cached.get("dome_id", ""))},
			"canonical_tx": _rotator.get_plate_canonical_transform(_spirals[spiral_idx], plate_idx)
		}
	return assignments

func _build_assignments_for_keys(keys: Dictionary) -> Array:
	var assignments := []
	for key in keys.keys():
		if _dome_assignment_cache.has(key):
			assignments.append(_dome_assignment_cache[key])
	return assignments

func _build_lod_overlay_assignments_for_selection() -> Array:
	var keys := _get_lod_overlay_plate_keys_for_selection()
	var assignments := []
	for key in keys.keys():
		if not _dome_assignment_cache.has(key):
			continue
		var cached: Dictionary = _dome_assignment_cache[key]
		if bool(cached.get("has_lod_blueprint", false)):
			assignments.append(cached)
	return assignments

func _get_lod_overlay_plate_keys_for_selection() -> Dictionary:
	var result := {}
	if _spirals.empty():
		return result
	var max_instances := int(dome_lod_overlay_max_instances)
	if max_instances <= 0:
		return result
	var per_spiral_radius := int(max(1, floor(float(max_instances) / float(max(1, _spirals.size() * 2)))))
	for spiral_idx in range(_spirals.size()):
		var plate_count := _get_plate_count(_spirals[spiral_idx])
		if plate_count <= 0:
			continue
		var signed_spiral_delta := _get_signed_wrapped_spiral_delta(selected_spiral, spiral_idx)
		var center_plate := selected_plate - signed_spiral_delta * dome_inter_spiral_plate_offset
		for offset in range(-per_spiral_radius, per_spiral_radius + 1):
			var plate_idx := _wrap_index(center_plate + offset, plate_count)
			var key := _make_plate_key(spiral_idx, plate_idx)
			if _dome_assignment_cache.has(key):
				result[key] = true
			if result.size() >= max_instances:
				return result
	return result

func _sync_stream_assignments_legacy(assignments: Dictionary) -> void:
	if _plate_content_stream.has_method("begin_bulk_assignments"):
		_plate_content_stream.begin_bulk_assignments()
	for old_key in _last_full_detail_keys.keys():
		if assignments.has(old_key):
			continue
		var parsed := _parse_plate_key(String(old_key))
		_plate_content_stream.assign_scene(int(parsed.get("spiral", -1)), int(parsed.get("plate", -1)), null)
	for key in assignments.keys():
		var row: Dictionary = assignments[key]
		_plate_content_stream.assign_scene(
				int(row.get("spiral_idx", -1)),
				int(row.get("plate_idx", -1)),
				row.get("scene", null),
				row.get("spawn_offset", Vector3.ZERO),
				row.get("context", {}))
	if _plate_content_stream.has_method("end_bulk_assignments"):
		_plate_content_stream.end_bulk_assignments()

func _get_dome_lod_mode() -> String:
	var mode := OS.get_environment("ODISEA_DOME_LOD_MODE").strip_edges().to_lower()
	if mode in ["lod", "full_stream", "off"]:
		return mode
	if OS.get_environment("ODISEA_DOME_LOD_ENABLED").strip_edges().to_lower() in ["0", "false", "no", "off"]:
		return "off"
	return "lod" if dome_lod_enabled else "off"

func _uses_dome_lod_overlays() -> bool:
	return _get_dome_lod_mode() == "lod"

func _load_packed_scene(path: String) -> PackedScene:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var resource = load(path)
	if resource is PackedScene:
		return resource
	return null

func _load_packed_scene_cached(path: String) -> PackedScene:
	if path == "":
		return null
	if _packed_scene_cache.has(path):
		return _packed_scene_cache[path]
	var packed := _load_packed_scene(path)
	_packed_scene_cache[path] = packed
	return packed

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
	var use_lod_overlays := _uses_dome_lod_overlays()
	if not use_lod_overlays:
		for spiral in _spirals:
			if spiral is TerraceSpiral:
				spiral.clear_dome_lod_overlays()
		var full_detail_keys := _build_all_assignment_plate_keys(assignments) if _get_dome_lod_mode() == "full_stream" else {}
		_last_dome_lod_stats = _build_dome_lod_stats(assignments, full_detail_keys, 0)
		return
	var overlay_assignments := _select_nearest_dome_lod_assignments(assignments)
	var groups_by_spiral := {}
	for assignment in overlay_assignments:
		var info: Dictionary = assignment.get("info", {})
		var blueprint: Dictionary = assignment.get("blueprint", {})
		if blueprint.empty():
			blueprint = _resolve_dome_lod_blueprint(info)
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
	_last_dome_lod_stats = _build_dome_lod_stats(assignments, _get_full_detail_plate_keys_for_selection(), _count_overlay_parts(groups_by_spiral))
	_last_dome_lod_stats["lod1_visible_instances"] = overlay_assignments.size()

func _select_nearest_dome_lod_assignments(assignments: Array) -> Array:
	var max_instances := int(dome_lod_overlay_max_instances)
	if max_instances <= 0 or assignments.size() <= max_instances:
		return assignments
	if _spirals.empty():
		return assignments
	var per_spiral_radius := int(max(1, floor(float(max_instances) / float(max(1, _spirals.size() * 2)))))
	var allowed_keys := {}
	for spiral_idx in range(_spirals.size()):
		var plate_count := _get_plate_count(_spirals[spiral_idx])
		if plate_count <= 0:
			continue
		var signed_spiral_delta := _get_signed_wrapped_spiral_delta(selected_spiral, spiral_idx)
		var center_plate := selected_plate - signed_spiral_delta * dome_inter_spiral_plate_offset
		for offset in range(-per_spiral_radius, per_spiral_radius + 1):
			allowed_keys[_make_plate_key(spiral_idx, _wrap_index(center_plate + offset, plate_count))] = true
	var selected := []
	for assignment in assignments:
		var spiral_index := int(assignment.get("spiral_index", -1))
		var plate_index := int(assignment.get("plate_index", -1))
		if allowed_keys.has(_make_plate_key(spiral_index, plate_index)):
			selected.append(assignment)
			if selected.size() >= max_instances:
				break
	if selected.empty():
		return assignments
	return selected

func _build_dome_lod_stats(assignments: Array, full_detail_keys: Dictionary, overlay_part_count: int) -> Dictionary:
	if _segment_manager and _segment_manager.has_method("build_stats"):
		var shell_visible := false
		var shell := _rotator.get_node_or_null("FauxSkydome") if _rotator else null
		if shell and shell is Spatial:
			shell_visible = (shell as Spatial).visible
		return _segment_manager.build_stats(assignments, full_detail_keys, overlay_part_count, shell_visible)
	return {
		"total_assignments": assignments.size(),
		"lod2_full_detail_plates": full_detail_keys.size(),
		"lod1_overlay_draw_calls": overlay_part_count
	}

func _build_all_assignment_plate_keys(assignments: Array) -> Dictionary:
	var keys := {}
	for assignment in assignments:
		keys[_make_plate_key(int(assignment.get("spiral_index", -1)), int(assignment.get("plate_index", -1)))] = true
	return keys

func _count_overlay_parts(groups_by_spiral: Dictionary) -> int:
	var count := 0
	for spiral_index in groups_by_spiral.keys():
		var spiral_group_map: Dictionary = groups_by_spiral[spiral_index]
		for cache_key in spiral_group_map.keys():
			var group: Dictionary = spiral_group_map[cache_key]
			var blueprint: Dictionary = group.get("blueprint", {})
			count += int((blueprint.get("parts", []) as Array).size())
	return count

func get_lod_stats() -> Dictionary:
	return _last_dome_lod_stats.duplicate(true)

func print_lod_stats() -> void:
	print("[FD041][LOD_STATS] ", JSON.print(get_lod_stats()))

func get_lod_debug_snapshot() -> Dictionary:
	var active_slots := []
	if _plate_content_stream and _plate_content_stream.has_method("get_active_slots"):
		for slot in _plate_content_stream.get_active_slots():
			if not is_instance_valid(slot):
				continue
			var child_name := ""
			var child_visible := false
			if slot.get_child_count() > 0:
				var child: Node = slot.get_child(0)
				child_name = String(child.name)
				child_visible = bool((child as Spatial).visible) if child is Spatial else true
			active_slots.append({
				"name": String(slot.name),
				"path": String(slot.get_path()),
				"child": child_name,
				"child_visible": child_visible
			})
	return {
		"selected_spiral": selected_spiral,
		"selected_plate": selected_plate,
		"full_detail_keys": _last_full_detail_keys.keys(),
		"full_detail_debug_rows": _last_full_detail_debug_rows,
		"hidden_lod_keys": _lod_hidden_plate_keys.keys(),
		"stats": get_lod_stats(),
		"active_slots": active_slots
	}

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
	_sync_plate_window_for_selection()

func _collect_spirals() -> void:
	_spirals.clear()
	for name in ["TerraceSpiral", "TerraceSpiral2", "TerraceSpiral3", "TerraceSpiral4"]:
		var spiral: Node = _rotator.get_node_or_null(name)
		if spiral:
			_spirals.append(spiral)
	_spatial_full_detail_candidates_cache.clear()
	_spatial_full_detail_candidates_signature = ""

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
	var gravity_world: Node = _get_gravity_world()
	if not gravity_world:
		return
	var radius: float = gravity_world.get_axis_radius(plate_canonical.origin)
	gravity_world.set_centrifugal_reference_radius(radius)
	gravity_world.set_ship_angular_velocity(gravity_world.get_default_angular_velocity_for_one_g(radius))

func _reset_camera_roll() -> void:
	if not _camera:
		return
	_camera.rotation.z = 0.0

# --- DomeFacade Cursor ---
# Pre-instancia una DomeFacade por tipo de escena y la reposiciona al plate activo.
# Evita instanciar/destruir la escena costosa en cada cambio de selección.

func _setup_dome_facade_cursors() -> void:
	# FD-041 no usa cursor full-detail separado: PlateContentStream maneja FULL
	# alrededor del player y TerraceSpiral maneja LOD para el resto.
	_apply_lod_hide_for_full_detail_keys(_last_full_detail_keys)
	return
	var seen_paths := {}
	var dome_registry: Node = _get_dome_registry()
	if not dome_registry:
		return
	for dome_id in dome_registry.get_all_dome_ids():
		var info: Dictionary = dome_registry.get_dome(dome_id)
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
	# FD-041 exterior uses only two visual representations:
	# streamed full-detail facades around the player and MultiMesh LOD elsewhere.
	# Keep the legacy singleton cursor parked so it cannot duplicate/compete.
	_park_all_dome_facade_cursors()

func _get_dome_registry() -> Node:
	return get_node_or_null("/root/DomeRegistry")

func _get_gravity_world() -> Node:
	return get_node_or_null("/root/GravityWorld")

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
	_apply_lod_hide_for_full_detail_keys(_get_full_detail_plate_keys_for_selection(new_spiral, new_plate))

func _apply_lod_hide_for_full_detail_keys(full_detail_keys: Dictionary) -> void:
	for key in _lod_hidden_plate_keys.keys():
		if full_detail_keys.has(key):
			continue
		var parsed := _parse_plate_key(String(key))
		var old_spiral_idx := int(parsed.get("spiral", -1))
		var old_plate_idx := int(parsed.get("plate", -1))
		if old_spiral_idx >= 0 and old_spiral_idx < _spirals.size():
			var old_spiral: Spatial = _spirals[old_spiral_idx]
			if old_spiral.has_method("set_dome_lod_plate_hidden"):
				old_spiral.call("set_dome_lod_plate_hidden", old_plate_idx, false)
			_lod_hidden_plate_keys.erase(key)
	if not _uses_dome_lod_overlays():
		_last_full_detail_debug_rows.clear()
		return
	for key in full_detail_keys.keys():
		if _lod_hidden_plate_keys.has(key):
			continue
		var parsed := _parse_plate_key(String(key))
		var spiral_idx := int(parsed.get("spiral", -1))
		var plate_idx := int(parsed.get("plate", -1))
		if spiral_idx < 0 or spiral_idx >= _spirals.size():
			continue
		var spiral: Spatial = _spirals[spiral_idx]
		if spiral.has_method("set_dome_lod_plate_hidden"):
			spiral.call("set_dome_lod_plate_hidden", plate_idx, true)
			_lod_hidden_plate_keys[key] = true

func _get_full_detail_plate_keys_for_selection(spiral_idx: int = -999, plate_idx: int = -999) -> Dictionary:
	if spiral_idx == -999:
		spiral_idx = selected_spiral
	if plate_idx == -999:
		plate_idx = selected_plate
	if spiral_idx < 0 or spiral_idx >= _spirals.size():
		return {}
	var result := {}
	var target_plate_count := _get_plate_count(_spirals[spiral_idx])
	if target_plate_count <= 0:
		return result
	return _get_local_plate_window_keys(spiral_idx, plate_idx, target_plate_count, dome_full_detail_nearest_count)

func _get_local_plate_window_keys(spiral_idx: int, plate_idx: int, plate_count: int, max_count_value: int) -> Dictionary:
	var result := {}
	var max_count := int(min(max(0, max_count_value), plate_count))
	if max_count <= 0:
		return result
	var offsets := [0, -1, 1, -2, 2, -3, 3]
	var offset_index := 0
	while result.size() < max_count:
		var offset := 0
		if offset_index < offsets.size():
			offset = int(offsets[offset_index])
		else:
			var n := int(ceil(float(offset_index - offsets.size() + 1) / 2.0)) + 3
			offset = -n if offset_index % 2 == 1 else n
		result[_make_plate_key(spiral_idx, _wrap_index(plate_idx + offset, plate_count))] = true
		offset_index += 1
	return result

func _get_current_plate_key_for_selection(spiral_idx: int = -999, plate_idx: int = -999) -> Dictionary:
	if spiral_idx == -999:
		spiral_idx = selected_spiral
	if plate_idx == -999:
		plate_idx = selected_plate
	if spiral_idx < 0 or spiral_idx >= _spirals.size():
		return {}
	var plate_count := _get_plate_count(_spirals[spiral_idx])
	return {
		_make_plate_key(spiral_idx, _wrap_index(plate_idx, plate_count)): true
	}

func _get_streamed_full_detail_plate_keys_for_selection() -> Dictionary:
	return _get_full_detail_plate_keys_for_selection()

func print_full_stream_debug_positions() -> void:
	_refresh_full_detail_debug_rows(selected_spiral, selected_plate, _last_full_detail_keys)
	print("[FD041][FULL_STREAM_DEBUG] selected=%d:%d count=%d" % [selected_spiral, selected_plate, _last_full_detail_debug_rows.size()])
	for row in _last_full_detail_debug_rows:
		print("[FD041][FULL_STREAM_DEBUG] %s world=(%.2f, %.2f, %.2f) canonical=(%.2f, %.2f, %.2f) dist=%.2f" % [
			String(row.get("key", "")),
			float(row.get("world_x", 0.0)),
			float(row.get("world_y", 0.0)),
			float(row.get("world_z", 0.0)),
			float(row.get("canonical_x", 0.0)),
			float(row.get("canonical_y", 0.0)),
			float(row.get("canonical_z", 0.0)),
			float(row.get("distance", 0.0))
		])

func _refresh_full_detail_debug_rows(spiral_idx: int, plate_idx: int, full_detail_keys: Dictionary) -> void:
	_last_full_detail_debug_rows = _build_full_detail_debug_rows(
		full_detail_keys,
		_get_full_detail_reference_canonical_position(spiral_idx, plate_idx)
	)

func _build_full_detail_debug_rows(full_detail_keys: Dictionary, reference: Vector3) -> Array:
	var rows := []
	for key in full_detail_keys.keys():
		var parsed := _parse_plate_key(String(key))
		var spiral_idx := int(parsed.get("spiral", -1))
		var plate_idx := int(parsed.get("plate", -1))
		if spiral_idx < 0 or spiral_idx >= _spirals.size():
			continue
		var spiral: Spatial = _spirals[spiral_idx]
		var canonical_tx: Transform = _rotator.get_plate_canonical_transform(spiral, plate_idx)
		var canonical_origin := canonical_tx.origin
		var world_origin: Vector3 = canonical_origin
		if _rotator and is_instance_valid(_rotator):
			world_origin = _rotator.global_transform.xform(canonical_origin)
		rows.append({
			"key": String(key),
			"spiral": spiral_idx,
			"plate": plate_idx,
			"world_x": world_origin.x,
			"world_y": world_origin.y,
			"world_z": world_origin.z,
			"canonical_x": canonical_origin.x,
			"canonical_y": canonical_origin.y,
			"canonical_z": canonical_origin.z,
			"distance": canonical_origin.distance_to(reference),
			"dist_sq": canonical_origin.distance_squared_to(reference)
		})
	rows.sort_custom(self, "_sort_full_detail_debug_row")
	return rows

func _sort_full_detail_debug_row(a: Dictionary, b: Dictionary) -> bool:
	var dist_a := float(a.get("dist_sq", 0.0))
	var dist_b := float(b.get("dist_sq", 0.0))
	if not is_equal_approx(dist_a, dist_b):
		return dist_a < dist_b
	return String(a.get("key", "")) < String(b.get("key", ""))

func _collect_spatial_full_detail_candidates() -> Array:
	var signature := _build_spatial_full_detail_candidates_signature()
	if signature != "" and signature == _spatial_full_detail_candidates_signature:
		return _spatial_full_detail_candidates_cache
	var candidates := []
	if not _rotator or not is_instance_valid(_rotator):
		return candidates
	for spiral_idx in range(_spirals.size()):
		var spiral: Spatial = _spirals[spiral_idx]
		var plate_count := _get_plate_count(spiral)
		for plate_idx in range(plate_count):
			var canonical_tx: Transform = _rotator.get_plate_canonical_transform(spiral, plate_idx)
			candidates.append({
				"spiral_index": spiral_idx,
				"plate_index": plate_idx,
				"origin": canonical_tx.origin,
				"canonical_tx": canonical_tx
			})
	_spatial_full_detail_candidates_cache = candidates
	_spatial_full_detail_candidates_signature = signature
	return candidates

func _build_spatial_full_detail_candidates_signature() -> String:
	if _spirals.empty():
		return ""
	var parts := PoolStringArray()
	for spiral_idx in range(_spirals.size()):
		var spiral: Spatial = _spirals[spiral_idx]
		if not is_instance_valid(spiral):
			return ""
		var blend := 0.0
		if spiral.get("_last_applied_blend") != null:
			blend = float(spiral.get("_last_applied_blend"))
		parts.append("%d:%d:%.4f" % [spiral_idx, _get_plate_count(spiral), blend])
	return parts.join("|")

func _get_wrapped_spiral_distance(from_spiral: int, to_spiral: int) -> int:
	var count := _spirals.size()
	if count <= 0:
		return 0
	var direct := abs(to_spiral - from_spiral)
	return int(min(direct, count - direct))

func _get_signed_wrapped_spiral_delta(from_spiral: int, to_spiral: int) -> int:
	var count := _spirals.size()
	if count <= 0:
		return 0
	var delta := to_spiral - from_spiral
	var half := count / 2.0
	while float(delta) > half:
		delta -= count
	while float(delta) < -half:
		delta += count
	return delta

func _get_full_detail_reference_canonical_position(spiral_idx: int, plate_idx: int) -> Vector3:
	if _rotator and is_instance_valid(_rotator) and _player and is_instance_valid(_player) and _rotator.has_method("to_canonical"):
		return _rotator.to_canonical(_player.global_transform.origin)
	if _rotator and is_instance_valid(_rotator) and spiral_idx >= 0 and spiral_idx < _spirals.size():
		return _rotator.get_plate_canonical_transform(_spirals[spiral_idx], plate_idx).origin
	return Vector3.ZERO

func _make_plate_key(spiral_idx: int, plate_idx: int) -> String:
	return "%d:%d" % [spiral_idx, plate_idx]

func _parse_plate_key(key: String) -> Dictionary:
	var parts := key.split(":")
	if parts.size() != 2:
		return {}
	return {
		"spiral": int(parts[0]),
		"plate": int(parts[1])
	}
