extends Spatial

export(int, 0, 3) var selected_spiral := 0
export(int, 0, 10000) var selected_plate := 0
export(bool) var snap_on_selection := true
export(PackedScene) var plate_content_scene
export(int, -1, 8) var dome_full_detail_plate_radius := 1
export(int, 0, 64) var dome_full_detail_nearest_count := 1
export(int, 0, 3) var dome_full_detail_spiral_radius := 1
export(int, 0, 32) var dome_inter_spiral_plate_offset := 4
export(int, 0, 8) var dome_full_detail_preload_extra_radius := 0 if OS.has_feature("HTML5") else 1
export(bool) var dome_lod_enabled := true
# Domes LOD dibujados por MultiMesh (batched: ~1 draw call por mesh-part sin importar
# la cantidad de instancias). Subir el cap es barato en GPU; el coste extra es lineal en
# la escritura de instancias del MultiMesh, no en draw calls. 128 = más domes visibles.
export(int, 0, 1024) var dome_lod_overlay_max_instances := 128
export(int, 0, 16) var dome_lod_adjacent_spiral_slots := 4
export(float, 0.0, 180.0) var dome_lod_frustum_half_fov_deg := 180.0 if OS.has_feature("HTML5") else 80.0
export(float, 1.0, 32.0) var dome_lod_backface_penalty := 8.0
export(bool) var dome_lod_camera_update_enabled := not OS.has_feature("HTML5")
export(float, 1.0, 90.0) var dome_lod_camera_angle_threshold := 20.0
# El bug no era el TAMAÑO del pool sino que el re-centrado no corría en continuous_tracking
# (los colliders no se ponían al día con el jugador). Con reasignación cada frame, 6 slots
# bastan: ±1 en el espiral actual (3) + las plates vecinas más cercanas vía offset (3).
export(int, 4, 64) var exterior_collision_pool_size := 6
export(int, 1, 30) var exterior_collision_update_interval := 1
export(int, 1, 30) var exterior_target_plate_query_interval := 2

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

# Incremental cache build state — populated lazily across frames to avoid startup stall
var _cache_build_pending := false      # build has been requested but not finished
var _cache_build_spiral := 0
var _cache_build_plate := 0
var _cache_build_apply_selection_deferred := false  # apply_selection waiting for cache

# Background resource preload: unique .glb/.tscn loaded via ResourceInteractiveLoader
# to avoid blocking the main thread on the first blueprint resolution.
# path -> ResourceInteractiveLoader (null once finished)
var _preload_loaders: Dictionary = {}
# path -> loaded Resource (PackedScene/Mesh), populated as loaders finish
var _preload_resources: Dictionary = {}

# Airlock chamber gate for WorldRotator tracking. While the player is inside an
# airlock chamber (entering it from the exterior, or appearing there after a
# scene swap) continuous tracking is disabled and the world is left flat relative
# to the active terrace. This kills the per-frame radial tracking cost and, more
# importantly, removes the rotation snap on transition: there is no accumulated
# rotation to apply when the player walks back out. Tracking resumes (easing over
# WorldRotator.RESUME_TRACKING_DURATION) only when the player exits the chamber.
# AirlockZoneV2 toggles the player's "airlock_tracking_suspended" meta on chamber
# enter/exit, so we mirror it. Initialized to false so that a player appearing
# inside the destination chamber is detected as a false->true transition on the
# first tick and pauses tracking.
var _airlock_chamber_suspended := false

# Pipeline LOD: fase única por frame (snapshot + sort + flush todas las espirales).
var _lod_update_phase := 0              # 0=idle, 1=ejecutar ciclo completo
var _lod_pipeline_all_assignments := [] # candidatos para el ciclo actual
var _lod_dirty := false                 # plate cambió mientras el pipeline corría; reiniciar al terminar
var _lod_last_camera_fwd := Vector3.ZERO  # forward canónico en el último LOD update
# Bake-once para el caso ESTÁTICO (todas las espirales con animate=false): se hornean
# TODOS los domes en los MultiMesh una sola vez y el pipeline LOD por-frame queda inactivo
# (la GPU hace el frustum-culling). En cuanto haya animación, _is_dome_layout_static()
# devuelve false y se usa la ruta O(k) windowed de re-selección por-frame.
var _dome_lod_baked := false

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

	# Kick off background loads for unique dome resources so the first frame is free
	_begin_dome_resource_preloads()

	_resolve_spawn_state()
	call_deferred("apply_selection")
	call_deferred("_setup_dome_facade_cursors")

func _exit_tree() -> void:
	if has_node("/root/SessionManager"):
		get_node("/root/SessionManager").unregister_oys_actor("Odisea")
	_preload_loaders.clear()

var _streaming_paused := false

func pause_streaming() -> void:
	if _streaming_paused:
		return
	_streaming_paused = true
	set_process(false)
	set_physics_process(false)

func resume_streaming() -> void:
	if not _streaming_paused:
		return
	_streaming_paused = false
	set_process(true)
	set_physics_process(true)

# --- Background resource preloading ---

func _begin_dome_resource_preloads() -> void:
	var dome_registry: Node = _get_dome_registry()
	if not dome_registry:
		return
	var seen := {}
	for dome_id in dome_registry.get_all_dome_ids():
		var info: Dictionary = dome_registry.get_dome(dome_id)
		for key in ["facade_scene", "facade_lod_scene"]:
			var path := String(info.get(key, "")).strip_edges()
			if path == "" or seen.has(path):
				continue
			seen[path] = true
			if _preload_resources.has(path):
				continue
			if not ResourceLoader.exists(path):
				continue
			var loader = ResourceLoader.load_interactive(path)
			if loader:
				_preload_loaders[path] = loader

func _tick_preload_loaders() -> void:
	if _preload_loaders.empty():
		return
	var budget_usec := 2000
	var start := OS.get_ticks_usec()
	var finished := []
	for path in _preload_loaders.keys():
		var loader = _preload_loaders[path]
		if loader == null:
			finished.append(path)
			continue
		while OS.get_ticks_usec() - start < budget_usec:
			var err = loader.poll()
			if err == ERR_FILE_EOF:
				_preload_resources[path] = loader.get_resource()
				finished.append(path)
				break
			elif err != OK:
				finished.append(path)
				break
		if OS.get_ticks_usec() - start >= budget_usec:
			break
	for path in finished:
		_preload_loaders.erase(path)

func _resolve_player_camera() -> Camera:
	if _player == null or not is_instance_valid(_player):
		return null
	var camera := _player.get_node_or_null("CameraRig/Yaw/Pitch/OTS_Offset/SpringArm/Camera") as Camera
	if camera:
		return camera
	camera = _player.get_node_or_null("CameraRig/Yaw/Pitch/SpringArm/Camera") as Camera
	return camera

var _process_tick := 0

func _process(_delta: float) -> void:
	_process_tick += 1
	_tick_airlock_chamber_gate()
	if _process_tick % 2 == 0:
		_tick_preload_loaders()
		_tick_dome_assignment_cache_build()
	_tick_frustum_lod_update()
	_tick_lod_update_phase()
	_sync_selection_from_rotator()
	_tick_dome_facade_cursor()
	_reset_camera_roll()
	if _process_tick % 4 == 0:
		_tick_camera_yank_debug()

# Yank telemetry: measures how much the camera's world-forward jumps per frame.
# A clean arrival is ~0 deg/frame; a camera yank spikes several degrees. Pushed to
# ANNAV2 so it rides the heartbeat — readable from the bridge peer without any
# in-runtime command. Pairs with WorldRotator's "world_rotator_yank" point.
var _cam_yank_prev_fwd := Vector3.ZERO
var _cam_yank_have_prev := false
var _cam_yank_max_deg := 0.0

func _tick_camera_yank_debug() -> void:
	if OS.get_environment("ODISEA_YANK_DEBUG").strip_edges() == "0":
		return
	if _camera == null or not is_instance_valid(_camera):
		_camera = _resolve_player_camera()
		if _camera == null:
			return
	var fwd: Vector3 = -_camera.global_transform.basis.z
	var deg := 0.0
	if _cam_yank_have_prev and fwd.length_squared() > 0.0001 and _cam_yank_prev_fwd.length_squared() > 0.0001:
		var d: float = clamp(fwd.normalized().dot(_cam_yank_prev_fwd.normalized()), -1.0, 1.0)
		deg = rad2deg(acos(d))
	_cam_yank_prev_fwd = fwd
	_cam_yank_have_prev = true
	if deg > _cam_yank_max_deg:
		_cam_yank_max_deg = deg
	var anna = get_node_or_null("/root/ANNAV2")
	if anna != null and anna.has_method("add_telemetry_data"):
		anna.add_telemetry_data("camera_yank", {
			"deg_per_frame": stepify(deg, 0.001),
			"max_deg": stepify(_cam_yank_max_deg, 0.001)
		})

var _airlock_streaming_throttled := false

func _tick_airlock_chamber_gate() -> void:
	if not _rotator or not is_instance_valid(_rotator):
		return
	if not _rotator.has_method("pause_tracking"):
		return
	var suspended := _is_player_airlock_suspended()
	if suspended == _airlock_chamber_suspended:
		return
	_airlock_chamber_suspended = suspended
	if suspended:
		_rotator.pause_tracking()
		_throttle_streaming_for_airlock(true)
	else:
		_rotator.resume_tracking()
		_throttle_streaming_for_airlock(false)

func _throttle_streaming_for_airlock(throttle: bool) -> void:
	if throttle == _airlock_streaming_throttled:
		return
	_airlock_streaming_throttled = throttle
	if throttle:
		if _plate_content_stream and is_instance_valid(_plate_content_stream):
			_plate_content_stream.set_physics_process(false)
	else:
		if _plate_content_stream and is_instance_valid(_plate_content_stream):
			_plate_content_stream.set_physics_process(true)

func _is_player_airlock_suspended() -> bool:
	var player := _resolve_tracking_player()
	if player == null:
		# No player resolvable yet (e.g. mid scene-load) — keep the current state.
		return _airlock_chamber_suspended
	return player.has_meta("airlock_tracking_suspended") \
		and bool(player.get_meta("airlock_tracking_suspended"))

func _resolve_tracking_player() -> Node:
	if _player != null and is_instance_valid(_player):
		return _player
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p):
			return p
	return null

func _resolve_spawn_state() -> void:
	if not has_node("/root/SceneManager"):
		return
	var scene_manager = get_node("/root/SceneManager")
	var params = scene_manager.get("_transition_params")
	if typeof(params) == TYPE_DICTIONARY:
		# AirlockManager already placed the player at the correct airlock position.
		# Do not change selected_spiral/selected_plate — the WorldRotator is already
		# in the right state and repositioning it would yank the player away.
		if bool(params.get("_airlock_manager_placed", false)):
			return
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
	_rotator.auto_track_target_plate = true

	# LOD/content assignment requires the dome cache.
	# _ensure_dome_assignment_cache() eagerly seeds the selected plate's keys so we
	# can call _assign_plate_content() immediately for the full-detail dome, and then
	# let the background build finish the rest (LOD overlay will refresh when done).
	if not _dome_assignment_cache_ready:
		_ensure_dome_assignment_cache()
		_cache_build_apply_selection_deferred = true
	_assign_plate_content()

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
	_plate_content_stream.slot_pool_size = 4
	_plate_content_stream.slot_update_interval = 12
	_plate_content_stream.centrifugal_current_plate_only_physics = true
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
	if _cache_build_pending:
		return
	# Start incremental build — actual work runs in _tick_dome_assignment_cache_build()
	_dome_assignment_cache.clear()
	_dome_lod_assignment_keys.clear()
	_cache_build_spiral = 0
	_cache_build_plate = 0
	_cache_build_pending = true
	# Eagerly populate the selected plate and its full-detail neighbours so that
	# _assign_plate_content() can run immediately on the first apply_selection() call,
	# avoiding the blank-dome flash while the background build finishes.
	_seed_cache_for_selection(selected_spiral, selected_plate)

func _seed_cache_for_selection(spiral_idx: int, plate_idx: int) -> void:
	var dome_registry: Node = _get_dome_registry()
	if not dome_registry or _spirals.empty():
		return
	if spiral_idx < 0 or spiral_idx >= _spirals.size():
		return
	var plate_count := _get_plate_count(_spirals[spiral_idx])
	if plate_count <= 0:
		return
	var keys := _get_full_detail_plate_keys_for_selection(spiral_idx, plate_idx)
	for key in keys.keys():
		if _dome_assignment_cache.has(key):
			continue
		var parsed := _parse_plate_key(String(key))
		var s := int(parsed.get("spiral", -1))
		var p := int(parsed.get("plate", -1))
		if s < 0 or p < 0:
			continue
		var dome_id: String = dome_registry.get_dome_id_for_plate(s, p)
		var info: Dictionary = dome_registry.get_dome(dome_id)
		if info.empty():
			continue
		var facade_scene_path := String(info.get("facade_scene", "")).strip_edges()
		var facade_scene := _load_packed_scene_cached(facade_scene_path)
		# LOD blueprint is expensive (instances a scene to extract mesh data) — skip
		# during the eager seed pass.  The background build will fill it in later.
		var assignment := {
			"key": key,
			"dome_id": dome_id,
			"spiral_index": s,
			"plate_index": p,
			"info": info.duplicate(true),
			"facade_scene": facade_scene,
			"facade_spawn_offset": info.get("facade_spawn_offset", Vector3.ZERO),
			"blueprint": {},
			"has_lod_blueprint": false
		}
		_dome_assignment_cache[key] = assignment

func _tick_dome_assignment_cache_build() -> void:
	if not _cache_build_pending:
		return
	if _spirals.empty():
		return
	# Wait for background preloaders to finish before building the cache.
	# This avoids blocking load() calls inside _resolve_dome_lod_blueprint().
	if not _preload_loaders.empty():
		return
	var dome_registry: Node = _get_dome_registry()
	if not dome_registry:
		_cache_build_pending = false
		return

	var budget_usec := 2000  # 2ms per frame — reduced from 4ms to lower main-thread pressure near airlocks
	var start := OS.get_ticks_usec()

	while _cache_build_spiral < _spirals.size():
		var spiral: Spatial = _spirals[_cache_build_spiral]
		var plate_count: int = _get_plate_count(spiral)
		while _cache_build_plate < plate_count:
			var dome_id: String = dome_registry.get_dome_id_for_plate(_cache_build_spiral, _cache_build_plate)
			var info: Dictionary = dome_registry.get_dome(dome_id)
			if not info.empty():
				var plate_key := _make_plate_key(_cache_build_spiral, _cache_build_plate)
				var needs_refresh := not _dome_assignment_cache.has(plate_key)
				if not needs_refresh:
					var existing: Dictionary = _dome_assignment_cache[plate_key]
					var existing_scene = existing.get("facade_scene", null)
					var existing_has_lod := bool(existing.get("has_lod_blueprint", false))
					# The eager seed pass can leave the selected spawn plate half-populated.
					# Rebuild any incomplete entry so the initial terrace gets the same
					# full-detail/LOD data as plates discovered later in the background pass.
					needs_refresh = existing_scene == null or not existing_has_lod
				if needs_refresh:
					var facade_scene_path := String(info.get("facade_scene", "")).strip_edges()
					var facade_scene := _load_packed_scene_cached(facade_scene_path)
					var blueprint := _resolve_dome_lod_blueprint(info)
					var assignment := {
						"key": plate_key,
						"dome_id": dome_id,
						"spiral_index": _cache_build_spiral,
						"plate_index": _cache_build_plate,
						"info": info.duplicate(true),
						"facade_scene": facade_scene,
						"facade_spawn_offset": info.get("facade_spawn_offset", Vector3.ZERO),
						"blueprint": blueprint,
						"has_lod_blueprint": not blueprint.empty()
					}
					_dome_assignment_cache[plate_key] = assignment
					if bool(assignment["has_lod_blueprint"]) and not _dome_lod_assignment_keys.has(plate_key):
						_dome_lod_assignment_keys.append(plate_key)
			_cache_build_plate += 1
			if OS.get_ticks_usec() - start >= budget_usec:
				return  # yield until next frame
		_cache_build_spiral += 1
		_cache_build_plate = 0

	# All spirals processed
	_cache_build_pending = false
	_dome_assignment_cache_ready = true
	if _cache_build_apply_selection_deferred:
		_cache_build_apply_selection_deferred = false
		_assign_plate_content()

func _sync_plate_window_for_selection(_force: bool = false) -> void:
	if not _plate_content_stream:
		return
	if not _dome_assignment_cache_ready and _dome_assignment_cache.empty():
		return  # nothing seeded yet; wait for first _seed_cache_for_selection pass
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
		if _dome_lod_baked:
			# Escena estática ya horneada: todos los domes están presentes, no re-seleccionar.
			pass
		elif _is_dome_layout_static() and _dome_assignment_cache_ready:
			# Hornear TODOS los domes una sola vez; luego el pipeline por-frame queda inactivo.
			_bake_all_dome_lod_overlays()
		elif _lod_update_phase == 0:
			_schedule_lod_overlay_update(_build_lod_overlay_assignments_for_selection())
		else:
			_lod_dirty = true
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
	# O(k) en vez de O(N): en vez de devolver TODAS las plates con blueprint (~596) para
	# que _select_nearest las puntúe y ordene por distancia 3D, devolvemos sólo la VENTANA
	# de plates alrededor del jugador, indexada por la fórmula de offsets (igual que el pool
	# de colisión). Tomamos un radio generoso (≈2× lo necesario) para que el sort por
	# frustum/adyacencia siga teniendo de dónde elegir, pero acotado a O(max_instances).
	# Fallback: si la ventana no llena el cupo (cache parcial), completar con el set total.
	var max_instances := int(dome_lod_overlay_max_instances)
	if max_instances <= 0:
		return _build_all_lod_overlay_assignments()
	var windowed := _build_windowed_lod_overlay_assignments(max_instances)
	# Si la ventana indexada quedó corta (p.ej. cache aún parcial), usar el set completo.
	if windowed.size() < max_instances:
		return _build_all_lod_overlay_assignments()
	return windowed

func _build_all_lod_overlay_assignments() -> Array:
	var assignments := []
	for key in _dome_lod_assignment_keys:
		if _dome_assignment_cache.has(key):
			assignments.append(_dome_assignment_cache[key])
	return assignments

# Hornea TODOS los domes en los MultiMesh de cada espiral una sola vez (escena estática).
# No hay cap ni sort por distancia/frustum: cada dome queda presente y la GPU descarta los
# que están fuera de cámara. Tras esto, _dome_lod_baked=true desactiva el pipeline por-frame.
func _bake_all_dome_lod_overlays() -> void:
	var assignments := _build_all_lod_overlay_assignments()
	var groups_by_spiral := {}
	for assignment in assignments:
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
		if groups_by_spiral.has(spiral_index):
			spiral.set_dome_lod_overlays(_build_spiral_dome_lod_groups(groups_by_spiral[spiral_index]))
		else:
			spiral.clear_dome_lod_overlays()
	_last_dome_lod_stats = _build_dome_lod_stats(
		assignments, _get_full_detail_plate_keys_for_selection(), _count_overlay_parts(groups_by_spiral))
	_last_dome_lod_stats["lod1_visible_instances"] = assignments.size()
	_last_dome_lod_stats["baked_static"] = true
	_dome_lod_baked = true

# Candidatos LOD por ventana de índices alrededor del jugador (sin escanear las 596).
# Radio por espiral dimensionado para entregar ~2× max_instances candidatos repartidos
# entre las espirales, de modo que el sort por frustum/distancia tenga margen de elección.
func _build_windowed_lod_overlay_assignments(max_instances: int) -> Array:
	var assignments := []
	if _spirals.empty():
		return assignments
	var spiral_count := int(max(1, _spirals.size()))
	# 2× el cupo, repartido en (espirales × 2 lados) → radio por espiral.
	var per_spiral_radius := int(max(1, ceil(float(max_instances * 2) / float(spiral_count * 2))))
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
				assignments.append(_dome_assignment_cache[key])
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

# El layout de domes es estático si NINGUNA espiral anima (animate=false en todas). En
# ese caso podemos hornear todos los domes una vez en vez de re-seleccionar por frame.
func _is_dome_layout_static() -> bool:
	if _spirals.empty():
		return false
	for spiral in _spirals:
		if spiral == null or not is_instance_valid(spiral):
			continue
		if bool(spiral.get("animate")):
			return false
	return true

func _load_packed_scene(path: String) -> PackedScene:
	if path == "":
		return null
	if _preload_resources.has(path):
		var cached = _preload_resources[path]
		if cached is PackedScene:
			return cached
		# Resource preloaded to a non-PackedScene type or stale entry; retry via normal load.
	# If a background loader is still in flight for this path, finish it now
	# (blocking) rather than starting a second load() call.
	if _preload_loaders.has(path):
		var loader = _preload_loaders[path]
		if loader != null:
			while true:
				var err = loader.poll()
				if err == ERR_FILE_EOF:
					var res = loader.get_resource()
					_preload_resources[path] = res
					_preload_loaders.erase(path)
					if res is PackedScene:
						return res
					break
				elif err != OK:
					_preload_loaders.erase(path)
					break
		else:
			_preload_loaders.erase(path)
	if not ResourceLoader.exists(path):
		return null
	var resource = load(path)
	if resource is PackedScene:
		return resource
	return null

func _load_packed_scene_cached(path: String) -> PackedScene:
	if path == "":
		return null
	if _packed_scene_cache.has(path):
		var cached = _packed_scene_cache[path]
		if cached is PackedScene:
			return cached
		# Retry failed loads on subsequent frames instead of pinning the scene to null forever.
		_packed_scene_cache.erase(path)
	var packed := _load_packed_scene(path)
	if packed != null:
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

# Dispara un nuevo ciclo LOD si la cámara giró más de dome_lod_camera_angle_threshold grados.
func _tick_frustum_lod_update() -> void:
	# Si ya horneamos todos los domes (escena estática), no hay nada que re-seleccionar al
	# girar la cámara: están todos presentes y la GPU los descarta fuera del frustum.
	if _dome_lod_baked:
		return
	if not dome_lod_camera_update_enabled:
		return
	if _lod_update_phase != 0:
		return
	if not _uses_dome_lod_overlays():
		return
	var cam_fwd := _get_camera_forward_canonical()
	if cam_fwd.length_squared() < 0.01:
		return
	if _lod_last_camera_fwd.length_squared() < 0.01:
		_lod_last_camera_fwd = cam_fwd
		return
	var cos_threshold := cos(deg2rad(clamp(dome_lod_camera_angle_threshold, 1.0, 90.0)))
	if cam_fwd.dot(_lod_last_camera_fwd) < cos_threshold:
		_lod_last_camera_fwd = cam_fwd
		_schedule_lod_overlay_update(_build_lod_overlay_assignments_for_selection())

# Inicia el pipeline LOD con nuevas asignaciones.
func _schedule_lod_overlay_update(assignments: Array) -> void:
	_lod_update_phase = 1
	_lod_pipeline_all_assignments = assignments
	_lod_last_camera_fwd = _get_camera_forward_canonical()

# Snapshot de orígenes canónicos: una inversión de WorldRotator + una base canónica por espiral.
func _snapshot_canonical_origins(assignments: Array) -> Dictionary:
	var snap := {}
	if not _rotator or not is_instance_valid(_rotator):
		return snap
	var rotator_inv := _rotator.global_transform.affine_inverse()
	var spiral_canonicals := {}  # spiral_index -> Transform (cacheado por espiral)
	for assignment in assignments:
		var spiral_index := int(assignment.get("spiral_index", -1))
		var plate_index := int(assignment.get("plate_index", -1))
		if spiral_index < 0 or spiral_index >= _spirals.size():
			continue
		if not spiral_canonicals.has(spiral_index):
			spiral_canonicals[spiral_index] = rotator_inv * _spirals[spiral_index].global_transform
		var spiral: Spatial = _spirals[spiral_index]
		var local_xform: Transform
		var cached_list = spiral.get("_cached_transforms")
		if cached_list != null and cached_list is Array and plate_index < cached_list.size():
			local_xform = cached_list[plate_index]
		else:
			var multimesh: MultiMesh = spiral.get("multimesh")
			if multimesh == null or multimesh.instance_count <= 0:
				continue
			local_xform = multimesh.get_instance_transform(int(clamp(plate_index, 0, multimesh.instance_count - 1)))
		snap[_make_plate_key(spiral_index, plate_index)] = (spiral_canonicals[spiral_index] * local_xform).origin
	return snap

# Ejecuta el pipeline LOD completo en un solo frame.
# Fase 1 (snapshot + sort + build) es barata tras la optimización de spiral_canonicals.
# Fase 2 (flush a espirales) usa structural signature para evitar rebuilds de MultiMesh.
func _tick_lod_update_phase() -> void:
	if _lod_update_phase != 1:
		return
	var origin_snap := _snapshot_canonical_origins(_lod_pipeline_all_assignments)
	var sorted := _select_nearest_dome_lod_assignments(_lod_pipeline_all_assignments, origin_snap)
	var groups_by_spiral := {}
	for assignment in sorted:
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
	# Flush todas las espirales en el mismo frame (structural signature evita rebuild si no cambió).
	var covered_spirals := {}
	for spiral_index in groups_by_spiral.keys():
		var spiral: Spatial = _spirals[int(spiral_index)]
		if not (spiral is TerraceSpiral):
			continue
		spiral.set_dome_lod_overlays(_build_spiral_dome_lod_groups(groups_by_spiral[spiral_index]))
		covered_spirals[int(spiral_index)] = true
	for i in range(_spirals.size()):
		if covered_spirals.has(i):
			continue
		var spiral: Spatial = _spirals[i]
		if spiral is TerraceSpiral:
			spiral.clear_dome_lod_overlays()
	_last_dome_lod_stats = _build_dome_lod_stats(
		_lod_pipeline_all_assignments,
		_get_full_detail_plate_keys_for_selection(),
		_count_overlay_parts(groups_by_spiral))
	_last_dome_lod_stats["lod1_visible_instances"] = sorted.size()
	_lod_update_phase = 0
	if _lod_dirty:
		_lod_dirty = false
		_schedule_lod_overlay_update(_build_lod_overlay_assignments_for_selection())

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

func _select_nearest_dome_lod_assignments(assignments: Array, origin_snap: Dictionary = {}) -> Array:
	var max_instances := int(dome_lod_overlay_max_instances)
	if max_instances <= 0 or assignments.size() <= max_instances:
		return assignments
	if _spirals.empty() or not _rotator or not is_instance_valid(_rotator):
		return assignments.slice(0, max_instances - 1)
	var reference_pos := _get_full_detail_reference_canonical_position(selected_spiral, selected_plate)
	var cam_fwd := _get_camera_forward_canonical()
	var use_frustum := cam_fwd.length_squared() > 0.01
	var fov_cos := cos(deg2rad(clamp(float(dome_lod_frustum_half_fov_deg), 0.0, 179.9))) if use_frustum else -1.0
	var penalty := float(dome_lod_backface_penalty)

	# --- Pass 1: slots garantizados para espirales adyacentes (≠ selected_spiral) ---
	var adj_slots := int(clamp(dome_lod_adjacent_spiral_slots, 0, max_instances))
	var adjacent_keys := {}
	var adjacent_selected := []
	if adj_slots > 0 and _spirals.size() > 1:
		var adj_scored := []
		for assignment in assignments:
			var spiral_index := int(assignment.get("spiral_index", -1))
			if spiral_index < 0 or spiral_index >= _spirals.size() or spiral_index == selected_spiral:
				continue
			var plate_index := int(assignment.get("plate_index", -1))
			var snap_key := _make_plate_key(spiral_index, plate_index)
			var canonical_origin: Vector3 = origin_snap[snap_key] if origin_snap.has(snap_key) else \
				_rotator.get_plate_canonical_transform(_spirals[spiral_index], plate_index).origin
			adj_scored.append({"assignment": assignment, "dist_sq": canonical_origin.distance_squared_to(reference_pos)})
		adj_scored.sort_custom(self, "_sort_lod_entry_by_dist")
		for i in range(min(adj_slots, adj_scored.size())):
			var asn: Dictionary = adj_scored[i]["assignment"]
			adjacent_selected.append(asn)
			adjacent_keys[_make_plate_key(int(asn.get("spiral_index", -1)), int(asn.get("plate_index", -1)))] = true

	# --- Pass 2: relleno por distancia con bias de frustum (todas las espirales) ---
	var remaining := int(max(0, max_instances - adjacent_selected.size()))
	var main_scored := []
	for assignment in assignments:
		var spiral_index := int(assignment.get("spiral_index", -1))
		var plate_index := int(assignment.get("plate_index", -1))
		var key := _make_plate_key(spiral_index, plate_index)
		if adjacent_keys.has(key):
			continue
		if spiral_index < 0 or spiral_index >= _spirals.size():
			continue
		var canonical_origin: Vector3 = origin_snap[key] if origin_snap.has(key) else \
			_rotator.get_plate_canonical_transform(_spirals[spiral_index], plate_index).origin
		var to_plate := canonical_origin - reference_pos
		var dist_sq := to_plate.length_squared()
		var score := dist_sq
		if use_frustum and dist_sq > 0.001:
			var dot := to_plate.normalized().dot(cam_fwd)
			if dot < fov_cos:
				score = dist_sq * penalty
		main_scored.append({"assignment": assignment, "dist_sq": score})
	main_scored.sort_custom(self, "_sort_lod_entry_by_dist")

	var selected := []
	selected.append_array(adjacent_selected)
	for i in range(min(remaining, main_scored.size())):
		selected.append(main_scored[i]["assignment"])
	if selected.empty():
		return assignments
	return selected

func _get_camera_forward_canonical() -> Vector3:
	if not _camera or not is_instance_valid(_camera):
		return Vector3.ZERO
	if not _rotator or not is_instance_valid(_rotator):
		return Vector3.ZERO
	# En Godot el forward de la cámara es -Z en espacio local
	var cam_fwd_global := -_camera.global_transform.basis.z
	# Convertir dirección a espacio canónico: solo aplicar la inversa de la base (sin traslación)
	return _rotator.global_transform.basis.inverse().xform(cam_fwd_global).normalized()

func _sort_lod_entry_by_dist(a: Dictionary, b: Dictionary) -> bool:
	# Deterministic tie-break: sort_custom is unstable, so equal distances could
	# swap rank between recomputes. Fall back to a stable key (spiral, then plate).
	var da := float(a.get("dist_sq", 0.0))
	var db := float(b.get("dist_sq", 0.0))
	if da != db:
		return da < db
	var aa: Dictionary = a.get("assignment", {})
	var ab: Dictionary = b.get("assignment", {})
	var asp := int(aa.get("spiral_index", -1))
	var bsp := int(ab.get("spiral_index", -1))
	if asp != bsp:
		return asp < bsp
	return int(aa.get("plate_index", -1)) < int(ab.get("plate_index", -1))

func _insert_ranked_lod_entry(ranked: Array, entry: Dictionary, max_count: int) -> void:
	if max_count <= 0:
		return
	var dist_sq := float(entry.get("dist_sq", 0.0))
	var insert_at := ranked.size()
	while insert_at > 0 and dist_sq < float(ranked[insert_at - 1].get("dist_sq", 0.0)):
		insert_at -= 1
	if insert_at >= max_count:
		return
	ranked.insert(insert_at, entry)
	if ranked.size() > max_count:
		ranked.pop_back()

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
		# lod_scale es igual para todos los items del mismo cache_key — calcular una sola vez
		var shared_lod_scale: Vector3 = _resolve_effective_dome_lod_scale(
			(items[0] as Dictionary).get("info", {}), blueprint)
		var group_parts := []
		for part_index in range(parts.size()):
			var part: Dictionary = parts[part_index]
			var mesh: Mesh = _build_mesh_for_multimesh_part(part)
			if mesh == null:
				continue
			var scaled_local := _scale_transform(part.get("local_transform", Transform.IDENTITY), shared_lod_scale)
			var overlay_items := []
			var signature_parts := PoolStringArray()
			for item in items:
				var plate_index := int(item.get("plate_index", -1))
				var origin_offset: Vector3 = item.get("info", {}).get("facade_spawn_offset", Vector3.ZERO)
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

func _resolve_dome_lod_blueprint(info: Dictionary, preload_only: bool = false) -> Dictionary:
	var mesh_path := String(info.get("facade_lod_mesh", "")).strip_edges()
	if mesh_path != "":
		var mesh_key := "mesh|%s" % mesh_path
		if _dome_lod_blueprint_cache.has(mesh_key):
			return _dome_lod_blueprint_cache[mesh_key]
		var mesh_resource = _preload_resources.get(mesh_path, null)
		if mesh_resource == null and not preload_only and ResourceLoader.exists(mesh_path):
			mesh_resource = load(mesh_path)
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
	var scene_resource = _preload_resources.get(scene_path, null)
	if scene_resource == null:
		if preload_only or not ResourceLoader.exists(scene_path):
			return {}
		scene_resource = load(scene_path)
	if not (scene_resource is PackedScene):
		return {}
	var scene_root = scene_resource.instance()
	if not is_instance_valid(scene_root):
		return {}
	var mesh_blueprint := _extract_dome_lod_blueprint(scene_root, mesh_node_path)
	scene_root.free()
	if mesh_blueprint.empty():
		return {}
	var alignment_fix := _get_dome_lod_alignment_fix(scene_path, info, mesh_blueprint)
	if alignment_fix != Transform.IDENTITY:
		mesh_blueprint = _apply_dome_lod_alignment_fix(mesh_blueprint, alignment_fix)
	if scene_path == "res://models/lod/DomeFacade_01_LOD.glb":
		mesh_blueprint = _normalize_domefacade_01_lod_parts(mesh_blueprint)
	mesh_blueprint["cache_key"] = scene_key
	_dome_lod_blueprint_cache[scene_key] = mesh_blueprint
	return mesh_blueprint

func _get_dome_lod_alignment_fix(scene_path: String, info: Dictionary, source_blueprint: Dictionary) -> Transform:
	var rotation_deg: Vector3 = info.get("facade_lod_rotation_degrees", Vector3.ZERO)
	if rotation_deg != Vector3.ZERO:
		return _build_rotation_transform_from_degrees(rotation_deg)
	if scene_path == "res://models/lod/DomeFacade_01_LOD.glb":
		return _pick_best_domefacade_01_alignment(source_blueprint, info)
	return Transform.IDENTITY

func _build_rotation_transform_from_degrees(rotation_deg: Vector3) -> Transform:
	var basis := Basis.IDENTITY
	if abs(rotation_deg.x) > 0.001:
		basis = Basis(Vector3(1, 0, 0), deg2rad(rotation_deg.x)) * basis
	if abs(rotation_deg.y) > 0.001:
		basis = Basis(Vector3(0, 1, 0), deg2rad(rotation_deg.y)) * basis
	if abs(rotation_deg.z) > 0.001:
		basis = Basis(Vector3(0, 0, 1), deg2rad(rotation_deg.z)) * basis
	return Transform(basis, Vector3.ZERO)

func _pick_best_domefacade_01_alignment(source_blueprint: Dictionary, info: Dictionary) -> Transform:
	var target_size: Vector3 = _resolve_facade_reference_size(info)
	if source_blueprint.empty() or target_size.length_squared() <= 0.001:
		# Known good fallback for this exported asset.
		return _build_rotation_transform_from_degrees(Vector3(90.0, 0.0, 0.0))
	var candidates := [
		Vector3(90.0, 0.0, 0.0),
		Vector3(-90.0, 0.0, 0.0),
		Vector3.ZERO
	]
	var best_fix := Transform.IDENTITY
	var best_score := INF
	for candidate_deg in candidates:
		var candidate_fix := _build_rotation_transform_from_degrees(candidate_deg)
		var aligned := _apply_dome_lod_alignment_fix(source_blueprint, candidate_fix)
		var source_size: Vector3 = aligned.get("aabb_size", Vector3.ONE)
		var score := _compute_size_match_score(source_size, target_size)
		if score < best_score:
			best_score = score
			best_fix = candidate_fix
	return best_fix

func _compute_size_match_score(source_size: Vector3, target_size: Vector3) -> float:
	var sx := max(abs(source_size.x), 0.001)
	var sy := max(abs(source_size.y), 0.001)
	var sz := max(abs(source_size.z), 0.001)
	var tx := max(abs(target_size.x), 0.001)
	var ty := max(abs(target_size.y), 0.001)
	var tz := max(abs(target_size.z), 0.001)
	var ex := abs((sx / tx) - 1.0)
	var ey := abs((sy / ty) - 1.0)
	var ez := abs((sz / tz) - 1.0)
	return ex + ey + ez

func _apply_dome_lod_alignment_fix(blueprint: Dictionary, fix: Transform) -> Dictionary:
	var parts: Array = blueprint.get("parts", [])
	if parts.empty():
		return blueprint
	var fixed_parts := []
	for part in parts:
		var fixed_part: Dictionary = (part as Dictionary).duplicate(true)
		var local_transform: Transform = fixed_part.get("local_transform", Transform.IDENTITY)
		var fixed_local := fix * local_transform
		fixed_part["local_transform"] = fixed_local
		var mesh: Mesh = fixed_part.get("mesh", null)
		if mesh != null:
			fixed_part["aabb"] = _transform_aabb(mesh.get_aabb(), fixed_local)
		fixed_parts.append(fixed_part)
	var fixed_blueprint: Dictionary = blueprint.duplicate(true)
	fixed_blueprint["parts"] = fixed_parts
	var fixed_aabb := _compute_parts_aabb(fixed_parts)
	fixed_blueprint["aabb"] = fixed_aabb
	fixed_blueprint["aabb_size"] = fixed_aabb.size
	return fixed_blueprint

func _normalize_domefacade_01_lod_parts(blueprint: Dictionary) -> Dictionary:
	var parts: Array = blueprint.get("parts", [])
	# Keep only the visual essentials for this optimized facade: dome shell + 4 cardinal cylinders.
	if parts.size() <= 5:
		return blueprint
	var shell_index := -1
	var shell_volume := -1.0
	for i in range(parts.size()):
		var aabb: AABB = (parts[i] as Dictionary).get("aabb", AABB(Vector3.ZERO, Vector3.ZERO))
		var size := aabb.size
		var volume := abs(size.x * size.y * size.z)
		if volume > shell_volume:
			shell_volume = volume
			shell_index = i
	if shell_index < 0:
		return blueprint

	var selected_indices := [shell_index]
	for _slot in range(4):
		var best_index := -1
		var best_score := -INF
		for i in range(parts.size()):
			if selected_indices.has(i):
				continue
			var aabb: AABB = (parts[i] as Dictionary).get("aabb", AABB(Vector3.ZERO, Vector3.ZERO))
			var size := aabb.size
			var max_axis := max(size.x, max(size.y, size.z))
			if max_axis <= 0.001:
				continue
			var min_axis := min(size.x, min(size.y, size.z))
			var compactness := min_axis / max_axis
			var volume := abs(size.x * size.y * size.z)
			# Prefer chunky near-isotropic parts (cylinders) over thin strips/panels.
			var score := compactness * 1000000.0 + min(volume, 999999.0)
			if score > best_score:
				best_score = score
				best_index = i
		if best_index >= 0:
			selected_indices.append(best_index)

	var filtered_parts := []
	for idx in selected_indices:
		if idx >= 0 and idx < parts.size():
			filtered_parts.append((parts[idx] as Dictionary).duplicate(true))
	if filtered_parts.size() < 5:
		return blueprint

	var normalized := blueprint.duplicate(true)
	normalized["parts"] = filtered_parts
	var normalized_aabb := _compute_parts_aabb(filtered_parts)
	normalized["aabb"] = normalized_aabb
	normalized["aabb_size"] = normalized_aabb.size
	return normalized

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
	var facade_scene = _preload_resources.get(facade_scene_path, null)
	if facade_scene == null:
		if not ResourceLoader.exists(facade_scene_path):
			return Vector3.ONE
		facade_scene = load(facade_scene_path)
	if not (facade_scene is PackedScene):
		return Vector3.ONE
	var facade_root = facade_scene.instance()
	if not is_instance_valid(facade_root):
		return Vector3.ONE
	var size: Vector3 = Vector3.ONE
	var dome_mesh: Node = facade_root.get_node_or_null("DomeMesh")
	if dome_mesh is Spatial:
		var dome_mesh_spatial: Spatial = dome_mesh as Spatial
		var blueprint: Dictionary = _extract_dome_lod_blueprint(dome_mesh_spatial, "")
		size = blueprint.get("aabb_size", Vector3.ONE)
		var wrapper_scale: Vector3 = dome_mesh_spatial.transform.basis.get_scale()
		size = Vector3(
			size.x / max(abs(wrapper_scale.x), 0.001),
			size.y / max(abs(wrapper_scale.y), 0.001),
			size.z / max(abs(wrapper_scale.z), 0.001)
		)
	else:
		var blueprint: Dictionary = _extract_dome_lod_blueprint(facade_root, "")
		size = blueprint.get("aabb_size", Vector3.ONE)
	facade_root.free()
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
	if not is_instance_valid(_camera):
		_camera = _resolve_player_camera()
	if not is_instance_valid(_camera):
		return
	_camera.rotation.z = 0.0

# --- DomeFacade Cursor ---
# Pre-instancia una DomeFacade por tipo de escena y la reposiciona al plate activo.
# Evita instanciar/destruir la escena costosa en cada cambio de selección.

func _setup_dome_facade_cursors() -> void:
	# FD-041 no usa cursor full-detail separado: PlateContentStream maneja FULL
	# alrededor del player y TerraceSpiral maneja LOD para el resto.
	# (La instanciación legacy de DomeFacadeCursor fue retirada; ver historial git.)
	_apply_lod_hide_for_full_detail_keys(_last_full_detail_keys)
	_sync_dome_facade_cursor()  # mantiene aparcados los cursores legacy si existieran

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
