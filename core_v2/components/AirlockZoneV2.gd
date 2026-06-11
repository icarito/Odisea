extends BaseZoneV2
class_name AirlockZoneV2

const PRELOAD_POLL_BUDGET_MS := 4
const DEFAULT_FADE_OUT_S := 0.017
const DEFAULT_FADE_IN_S := 0.08
const TRANSITION_TRIGGER_PROGRESS := 0.6
const OPEN_EXIT_RETURN_TRIGGER_PROGRESS := 0.4
const OPEN_EXIT_RETURN_PROGRESS_EPSILON := 0.12

export(String, FILE, "*.tscn") var target_scene := ""
export(String) var target_spawn_id := ""
export(NodePath) var airlock_controller_path
export(NodePath) var target_airlock_path
export(Vector3) var zone_dir := Vector3.FORWARD

var _progress := 0.0
var _relative_position := Vector3.ZERO
var _background_load: ResourceInteractiveLoader = null
var _preloaded_scene: PackedScene = null
var _scene_ready := false
var _player_in_zone := false
var _has_triggered := false
var _stalling := false
var _tracked_player: Node = null
var _load_error := ""
var _has_safe_relative_y := false
var _last_safe_relative_y := 0.0
var _entry_door_name := "outer"
var _cycle_started := false
var _passive_exit_open := false
var _saved_spring_length := -1.0
var _open_exit_return_arm_progress := -1.0
var _open_exit_return_last_progress := -1.0

const AIRLOCK_OTS_SPRING_LENGTH := 1.5
const SEAMLESS_TRANSITION_ANIM_FREEZE_FRAMES := 4

func _ready() -> void:
	._ready()
	if Engine.editor_hint:
		return
	set_physics_process(false)
	set_process(true)
	_update_indicator_lights()

func _process(delta: float) -> void:
	._process(delta)
	if Engine.editor_hint:
		return
	_poll_background_load()
	_update_indicator_lights()

func _on_zone_entered(body: Node) -> void:
	if Engine.editor_hint:
		return
	if not _is_player(body):
		return

	var airlock = _find_airlock_controller()
	if _try_arm_passive_open_exit(body, airlock):
		return

	_tracked_player = body
	_player_in_zone = true
	_has_safe_relative_y = false
	_has_triggered = false
	_cycle_started = true
	_passive_exit_open = false
	_reset_open_exit_return_tracking()
	set_physics_process(true)
	_set_airlock_tracking_suspended(body, true)
	_push_airlock_camera(body)
	_start_airlock_cycle_from_body(body)
	_begin_background_load()

func _on_zone_exited(body: Node) -> void:
	if Engine.editor_hint:
		return
	if not _is_player(body):
		return
	_player_in_zone = false
	_stalling = false
	if _cycle_started and not _has_triggered:
		_abort_airlock_cycle()
	elif _passive_exit_open and not _has_triggered:
		_resume_exit_open_auto_reset()
	_cycle_started = false
	_passive_exit_open = false
	_reset_open_exit_return_tracking()
	set_physics_process(false)
	_set_airlock_tracking_suspended(body, false)
	_pop_airlock_camera(body)
	_update_indicator_lights()

func _physics_process(_delta: float) -> void:
	if Engine.editor_hint:
		return

	if not _player_in_zone:
		_arm_player_already_inside_zone()
	if not _player_in_zone:
		return

	var player := _get_player()
	if not (is_instance_valid(player) and player is Spatial):
		return
	if not is_body_in_zone(player) and not _is_spatial_geometrically_in_zone(player as Spatial):
		_player_in_zone = false
		_stalling = false
		if _cycle_started and not _has_triggered:
			_abort_airlock_cycle()
		_cycle_started = false
		_passive_exit_open = false
		_reset_open_exit_return_tracking()
		set_physics_process(false)
		return

	_update_progress(player as Spatial)

	if _passive_exit_open and not _has_triggered and _should_force_return_from_open_exit(player):
		_commit_return_from_open_exit(player)

	if not _passive_exit_open and not _has_triggered and _past_trigger_threshold():
		var airlock = _find_airlock_controller()
		if is_instance_valid(airlock):
			_ensure_transition_cycle_started(airlock, true)
		if is_instance_valid(airlock) and airlock.has_method("request_transition_pressurization"):
			airlock.request_transition_pressurization(_entry_door_name)

	var can_transition := _can_transition_now()
	_stalling = false

	if can_transition and not _has_triggered:
		_has_triggered = true
		# Freeze animator immediately — before the deferred call and scene load spikes.
		var animator = player.get("animator") if "animator" in player else null
		if is_instance_valid(animator) and animator.has_method("freeze"):
			animator.call("freeze", _get_transition_anim_freeze_frames(120))
		call_deferred("_run_transition", player)

func _arm_player_already_inside_zone() -> void:
	var player := _get_player()
	if not (is_instance_valid(player) and player is Spatial):
		return
	if not is_body_in_zone(player) and not _is_spatial_geometrically_in_zone(player as Spatial):
		return
	var airlock = _find_airlock_controller()
	if _try_arm_passive_open_exit(player, airlock):
		return
	_on_zone_entered(player)

func _try_arm_passive_open_exit(body: Node, airlock: Node) -> bool:
	if not is_instance_valid(airlock):
		return false
	var state = airlock.get("state")
	if state == null or int(state) != int(AirlockControllerV2.State.EXIT_OPEN):
		return false

	_tracked_player = body
	_player_in_zone = true
	_has_safe_relative_y = false
	_has_triggered = false
	_cycle_started = false
	_passive_exit_open = true
	if airlock.has_method("get_open_exit_door_name"):
		var open_exit := String(airlock.get_open_exit_door_name()).strip_edges().to_lower()
		if open_exit == "inner" or open_exit == "outer":
			_entry_door_name = open_exit
	_reset_open_exit_return_tracking()
	set_physics_process(true)
	# Re-assert tracking suspension while the player sits in the just-arrived
	# destination chamber (EXIT_OPEN). Without this the rotator resumes prematurely
	# — before the player walks out of the airlock — because the inherited
	# "suspended" meta has no owner in the passive-open-exit path and the world
	# starts chasing the still-settling spawn position (the arrival yank). It is
	# cleared in _on_zone_exited() when the player actually crosses the threshold.
	_set_airlock_tracking_suspended(body, true)
	_push_airlock_camera(body)
	_begin_background_load()
	return true

func _is_spatial_geometrically_in_zone(body: Spatial) -> bool:
	var local_pos: Vector3 = global_transform.affine_inverse().xform(body.global_transform.origin)
	var extents := zone_extents
	var shape_node := _find_collision_shape_direct()
	if shape_node and shape_node.shape is BoxShape:
		extents = shape_node.shape.extents
	return abs(local_pos.x) <= extents.x and abs(local_pos.y) <= extents.y and abs(local_pos.z) <= extents.z

func prepare_for_open_exit(open_exit_door_name: String) -> void:
	var normalized := String(open_exit_door_name).strip_edges().to_lower()
	if normalized != "inner":
		normalized = "outer"
	_entry_door_name = normalized
	_has_triggered = false
	_cycle_started = false
	_passive_exit_open = true
	_stalling = false
	_player_in_zone = false
	_tracked_player = null
	_reset_open_exit_return_tracking()
	set_physics_process(true)

func _begin_background_load() -> bool:
	if _scene_ready or _background_load != null:
		return true
	if target_scene.strip_edges() == "":
		_load_error = "missing_target_scene"
		printerr("[AirlockZoneV2] Missing target_scene on ", name)
		return false

	_background_load = ResourceLoader.load_interactive(target_scene)
	if _background_load == null:
		_load_error = "loader_create_failed"
		printerr("[AirlockZoneV2] Could not create ResourceInteractiveLoader for ", target_scene)
		return false
	return true

func _poll_background_load() -> void:
	if _background_load == null or _scene_ready:
		return

	var start_ms := OS.get_ticks_msec()
	while _background_load != null and OS.get_ticks_msec() - start_ms < PRELOAD_POLL_BUDGET_MS:
		var err := _background_load.poll()
		if err == OK:
			continue
		if err == ERR_FILE_EOF:
			var resource = _background_load.get_resource()
			if resource and resource is PackedScene:
				_preloaded_scene = resource
				_scene_ready = true
			else:
				_load_error = "loaded_resource_is_not_scene"
				printerr("[AirlockZoneV2] Loaded resource is not a PackedScene: ", target_scene)
			_background_load = null
			return

		_load_error = "loader_poll_failed_%d" % err
		printerr("[AirlockZoneV2] Loader poll failed (", err, ") for ", target_scene)
		_background_load = null
		return

func _update_progress(player: Spatial) -> void:
	var local_pos: Vector3 = global_transform.affine_inverse().xform(player.global_transform.origin)
	var dir := _get_local_zone_direction()
	var half_length := _get_zone_half_length(dir)
	var length := max(half_length * 2.0, 0.001)
	var projected := local_pos.dot(dir)

	_progress = clamp((projected + half_length) / length, 0.0, 1.0)
	_relative_position = local_pos
	_update_safe_relative_y(player, local_pos)

func _run_transition(player: Node) -> void:
	if not is_instance_valid(player):
		player = _get_player()
	if not _is_player(player):
		_has_triggered = false
		return

	# Freeze animator so fall/not-grounded pose doesn't flash during scene load
	var animator = player.get("animator") if "animator" in player else null
	if is_instance_valid(animator) and animator.has_method("freeze"):
		animator.call("freeze", _get_transition_anim_freeze_frames(60))

	_trigger_transition(player)

func _get_transition_anim_freeze_frames(default_frames: int) -> int:
	var airlock_manager = get_node_or_null("/root/AirlockManager")
	if airlock_manager != null and airlock_manager.has_method("notify_transition"):
		if default_frames < SEAMLESS_TRANSITION_ANIM_FREEZE_FRAMES:
			return default_frames
		return SEAMLESS_TRANSITION_ANIM_FREEZE_FRAMES
	return default_frames

func _trigger_transition(player: Node) -> bool:
	if target_scene.strip_edges() == "":
		printerr("[AirlockZoneV2] Missing target_scene on ", name)
		return false

	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager == null or not scene_manager.has_method("goto_scene"):
		printerr("[AirlockZoneV2] SceneManager autoload missing")
		return false

	var resolved_target_scene := target_scene
	var resolved_target_spawn_id := target_spawn_id
	var active_dome_id := _resolve_active_dome_id()
	if active_dome_id != "":
		var dome_info: Dictionary = DomeRegistry.get_dome(active_dome_id)
		if not dome_info.empty():
			if _is_moving_outer_to_inner():
				var interior_scene := String(dome_info.get("interior_scene", "")).strip_edges()
				if interior_scene != "":
					resolved_target_scene = interior_scene
				var exterior_spawn := String(dome_info.get("spawn_id_from_exterior", "")).strip_edges()
				if exterior_spawn != "":
					resolved_target_spawn_id = exterior_spawn
			else:
				var interior_spawn := String(dome_info.get("spawn_id_from_interior", "")).strip_edges()
				if interior_spawn != "":
					resolved_target_spawn_id = interior_spawn

	# If AirlockManager is active it will reparent the player — no black flash needed.
	var airlock_manager = get_node_or_null("/root/AirlockManager")
	var use_airlock_manager: bool = airlock_manager != null and airlock_manager.has_method("notify_transition")

	var params := {
		"spawn_id": resolved_target_spawn_id,
		"target_spawn_id": resolved_target_spawn_id,
		"dome_id": active_dome_id,
		"transition": "none" if use_airlock_manager else "fade",
		"transition_style": "airlock",
		"preserve_player_state": true,
		"fade_out": 0.0 if use_airlock_manager else DEFAULT_FADE_OUT_S,
		"fade_in": 0.0 if use_airlock_manager else DEFAULT_FADE_IN_S,
		"show_loading": false,
		"wait_for_fade_out": false,
		"state_data": _build_state_data(player)
	}

	if use_airlock_manager:
		airlock_manager.notify_transition(resolved_target_scene)

	if _preloaded_scene != null and resolved_target_scene == target_scene:
		params["_preloaded_scene"] = _preloaded_scene

	scene_manager.goto_scene(resolved_target_scene, params)
	return true

func _build_state_data(player: Node) -> Dictionary:
	var state_data := {}
	if is_instance_valid(player) and player.has_method("get_full_snapshot"):
		var snapshot = player.get_full_snapshot()
		if typeof(snapshot) == TYPE_DICTIONARY:
			var clean_snapshot: Dictionary = snapshot.duplicate(true)
			# Clear global position so SceneManager uses SpawnPointV2 + relative offset
			for key in ["pos", "position", "global_position", "origin"]:
				if clean_snapshot.has(key):
					clean_snapshot[key] = Vector3.ZERO
			# Clear velocity so player arrives at rest
			for key in ["vel", "velocity", "linear_velocity"]:
				if clean_snapshot.has(key):
					clean_snapshot[key] = Vector3.ZERO
			state_data["player_snapshot"] = clean_snapshot
			if snapshot.has("gravity_mode"):
				state_data["gravity_mode"] = snapshot["gravity_mode"]
			if snapshot.has("controller_mode"):
				state_data["controller_mode"] = snapshot["controller_mode"]

	# Capture camera orientation before transition
	if is_instance_valid(player):
		if "yaw" in player:
			state_data["camera_yaw"] = float(player.yaw)
		if "pitch" in player:
			state_data["camera_pitch"] = float(player.pitch)
		# Arrive in the same tight airlock framing instead of lerping from the
		# normal exterior distance back into OTS on the destination scene.
		state_data["camera_arm_spring_length"] = AIRLOCK_OTS_SPRING_LENGTH
		if _saved_spring_length > 0.0:
			state_data["camera_restore_spring_length"] = _saved_spring_length

	var active_dome_id := _resolve_active_dome_id()
	if active_dome_id != "":
		state_data["active_dome_id"] = active_dome_id

	var airlock = _find_airlock_controller()
	if is_instance_valid(player) and player is Spatial:
		var frame: Transform = global_transform
		if is_instance_valid(airlock) and airlock is Spatial:
			frame = (airlock as Spatial).global_transform

		var player_transform: Transform = (player as Spatial).global_transform
		var relative_transform: Transform = frame.affine_inverse() * player_transform
		var sanitized_transform := _sanitize_relative_transform(relative_transform, player)
		state_data["airlock_relative_position"] = sanitized_transform.origin
		state_data["airlock_relative_transform"] = sanitized_transform
		if "yaw" in player:
			state_data["camera_body_yaw_offset"] = float(player.yaw) - player_transform.basis.get_euler().y
			var camera_forward: Vector3 = Basis(Vector3.UP, float(player.yaw)).xform(Vector3.FORWARD)
			state_data["camera_relative_forward"] = frame.basis.xform_inv(camera_forward).normalized()
		var animator = player.get("animator") if "animator" in player else null
		if is_instance_valid(animator) and animator is Spatial:
			var visual_forward: Vector3 = (animator as Spatial).global_transform.basis.z
			visual_forward.y = 0.0
			if visual_forward.length_squared() > 0.0001:
				state_data["visual_relative_forward"] = frame.basis.xform_inv(visual_forward.normalized()).normalized()
		state_data["target_airlock_exit_door"] = _get_exit_door_for_direction()
		if not target_airlock_path.is_empty():
			state_data["target_airlock_path"] = String(target_airlock_path)
		if "velocity" in player:
			var velocity: Vector3 = player.velocity
			var relative_velocity: Vector3 = frame.basis.xform_inv(velocity)
			if _has_safe_relative_y and float(player.velocity.y) < -1.0:
				relative_velocity.y = 0.0
			state_data["airlock_relative_velocity"] = relative_velocity

	return state_data

func _update_safe_relative_y(player: Node, local_pos: Vector3) -> void:
	var velocity_y := 0.0
	if "velocity" in player:
		velocity_y = float(player.velocity.y)

	var grounded := false
	if player.has_method("is_on_floor"):
		grounded = bool(player.is_on_floor())

	if grounded or (local_pos.y > -1.0 and velocity_y > -1.5):
		_last_safe_relative_y = local_pos.y
		_has_safe_relative_y = true

func _sanitize_relative_transform(relative_transform: Transform, player: Node) -> Transform:
	var out := relative_transform
	if not _has_safe_relative_y:
		return out

	var falling_fast := false
	if "velocity" in player:
		falling_fast = float(player.velocity.y) < -1.0

	if falling_fast and out.origin.y < _last_safe_relative_y - 0.35:
		out.origin.y = _last_safe_relative_y
	return out

func _start_airlock_cycle_from_body(body: Node) -> void:
	var airlock = _find_airlock_controller()
	if not is_instance_valid(airlock):
		return
	if body is Spatial:
		_entry_door_name = _get_nearest_door_name(body as Spatial)
	if airlock.has_method("start_transition_cycle"):
		airlock.start_transition_cycle(_entry_door_name)

func _start_airlock_cycle() -> void:
	var airlock = _find_airlock_controller()
	if not is_instance_valid(airlock):
		return
	_entry_door_name = "outer" if _is_moving_outer_to_inner() else "inner"
	if airlock.has_method("start_transition_cycle"):
		airlock.start_transition_cycle(_entry_door_name)

func _abort_airlock_cycle() -> void:
	var airlock = _find_airlock_controller()
	if not is_instance_valid(airlock):
		return
	if airlock.has_method("abort_transition_cycle"):
		airlock.abort_transition_cycle(_entry_door_name)

func _resume_exit_open_auto_reset() -> void:
	var airlock = _find_airlock_controller()
	if is_instance_valid(airlock) and airlock.has_method("resume_exit_open_auto_reset"):
		airlock.resume_exit_open_auto_reset()

func _set_airlock_tracking_suspended(body: Node, suspended: bool) -> void:
	if not is_instance_valid(body):
		return
	if suspended:
		body.set_meta("airlock_tracking_suspended", true)
	elif body.has_meta("airlock_tracking_suspended"):
		body.remove_meta("airlock_tracking_suspended")

func _past_trigger_threshold() -> bool:
	return _past_progress_between_doors(TRANSITION_TRIGGER_PROGRESS)

func _past_return_trigger_threshold() -> bool:
	return _past_progress_between_doors(OPEN_EXIT_RETURN_TRIGGER_PROGRESS)

func _should_force_return_from_open_exit(_player: Node) -> bool:
	if not _passive_exit_open:
		return false
	var airlock = _find_airlock_controller()
	if not is_instance_valid(airlock):
		return false
	var state = airlock.get("state")
	if state == null or int(state) != int(AirlockControllerV2.State.EXIT_OPEN):
		return false
	if not airlock.has_method("get_open_exit_door_name"):
		return false
	var open_exit := String(airlock.get_open_exit_door_name()).strip_edges().to_lower()
	if open_exit != "inner" and open_exit != "outer":
		return false
	_entry_door_name = open_exit
	return _past_return_trigger_threshold_with_intent()

func _commit_return_from_open_exit(player: Node) -> void:
	var airlock = _find_airlock_controller()
	if not is_instance_valid(airlock):
		return
	var started := _ensure_transition_cycle_started(airlock, true)
	if not started:
		return
	_cycle_started = true
	_passive_exit_open = false
	_reset_open_exit_return_tracking()
	if _cycle_started:
		_set_airlock_tracking_suspended(player, true)
		if airlock.has_method("request_transition_pressurization"):
			airlock.request_transition_pressurization(_entry_door_name)

func _ensure_transition_cycle_started(airlock: Node, immediate_close: bool) -> bool:
	if not is_instance_valid(airlock):
		return false
	var state = airlock.get("state")
	if state != null and int(state) == int(AirlockControllerV2.State.PRESSURIZING):
		return true
	if airlock.has_method("start_transition_cycle"):
		return bool(airlock.start_transition_cycle(_entry_door_name, immediate_close))
	return true

func _past_progress_between_doors(fraction: float) -> bool:
	var entry_progress := _get_door_progress(_entry_door_name)
	var exit_progress := _get_door_progress(_get_exit_door_for_direction())
	var trigger_progress: float = lerp(entry_progress, exit_progress, clamp(fraction, 0.0, 1.0))
	if entry_progress <= exit_progress:
		return _progress >= trigger_progress
	return _progress <= trigger_progress

func _past_return_trigger_threshold_with_intent() -> bool:
	var current := _progress_between_doors()
	if _open_exit_return_arm_progress < 0.0:
		_open_exit_return_arm_progress = current
		_open_exit_return_last_progress = current
		return false

	var crossed_from_below := _open_exit_return_last_progress < OPEN_EXIT_RETURN_TRIGGER_PROGRESS and current >= OPEN_EXIT_RETURN_TRIGGER_PROGRESS
	var moved_toward_exit := current > _open_exit_return_arm_progress + OPEN_EXIT_RETURN_PROGRESS_EPSILON
	_open_exit_return_last_progress = current
	if current < OPEN_EXIT_RETURN_TRIGGER_PROGRESS:
		return false
	return crossed_from_below or moved_toward_exit

func _reset_open_exit_return_tracking() -> void:
	_open_exit_return_arm_progress = -1.0
	_open_exit_return_last_progress = -1.0

func _progress_between_doors() -> float:
	var entry_progress := _get_door_progress(_entry_door_name)
	var exit_progress := _get_door_progress(_get_exit_door_for_direction())
	var span := exit_progress - entry_progress
	if abs(span) <= 0.001:
		return 0.0
	return clamp((_progress - entry_progress) / span, 0.0, 1.0)

func _is_moving_outer_to_inner() -> bool:
	return _get_local_zone_direction().dot(Vector3.FORWARD) >= 0.0

func _get_exit_door_for_direction() -> String:
	if _entry_door_name == "inner":
		return "outer"
	return "inner"

func _get_nearest_door_name(player: Spatial) -> String:
	var local_pos: Vector3 = global_transform.affine_inverse().xform(player.global_transform.origin)
	var dir := _get_local_zone_direction()
	var player_projected := local_pos.dot(dir)
	var inner_projected := _get_door_projected_position("inner", dir)
	var outer_projected := _get_door_projected_position("outer", dir)
	return "inner" if abs(player_projected - inner_projected) <= abs(player_projected - outer_projected) else "outer"

func _get_door_progress(door_name: String) -> float:
	var dir := _get_local_zone_direction()
	var half_length := _get_zone_half_length(dir)
	var length := max(half_length * 2.0, 0.001)
	var projected := _get_door_projected_position(door_name, dir)
	return clamp((projected + half_length) / length, 0.0, 1.0)

func _get_door_projected_position(door_name: String, dir: Vector3) -> float:
	var airlock = _find_airlock_controller()
	if is_instance_valid(airlock) and airlock is Spatial:
		var door_path = airlock.get("inner_door_path") if door_name == "inner" else airlock.get("outer_door_path")
		if typeof(door_path) == TYPE_NODE_PATH and not door_path.is_empty():
			var door = airlock.get_node_or_null(door_path)
			if is_instance_valid(door) and door is Spatial:
				var local_pos: Vector3 = global_transform.affine_inverse().xform((door as Spatial).global_transform.origin)
				return local_pos.dot(dir)
	var fallback := -1.0 if door_name == "inner" else 1.0
	return fallback * _get_zone_half_length(dir)

func _get_local_zone_direction() -> Vector3:
	if zone_dir.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return zone_dir.normalized()

func _get_zone_half_length(dir: Vector3) -> float:
	var extents := zone_extents
	var shape_node := _find_collision_shape_direct()
	if shape_node and shape_node.shape is BoxShape:
		extents = shape_node.shape.extents

	var abs_dir := Vector3(abs(dir.x), abs(dir.y), abs(dir.z))
	return max(abs_dir.x * extents.x + abs_dir.y * extents.y + abs_dir.z * extents.z, 0.001)

func _is_airlock_entry_sealed() -> bool:
	var airlock := _find_airlock_controller()
	if not is_instance_valid(airlock):
		return true  # no controller — don't block
	if not airlock.has_method("start_transition_cycle"):
		return true  # not an AirlockControllerV2 — don't block
	if airlock.has_method("is_transition_entry_sealed"):
		return bool(airlock.is_transition_entry_sealed(_entry_door_name))
	return true

func _is_airlock_pressurizing() -> bool:
	var airlock := _find_airlock_controller()
	if not is_instance_valid(airlock):
		return false
	if airlock.has_method("is_pressurizing"):
		return bool(airlock.is_pressurizing())
	var s = airlock.get("state")
	return s != null and int(s) == int(AirlockControllerV2.State.PRESSURIZING)

func _can_transition_now() -> bool:
	if not (_scene_ready and _is_airlock_pressurizing() and _is_airlock_entry_sealed() and _is_airlock_transition_requested()):
		return false
	var fx := _find_transition_fx()
	if fx != null:
		return fx.is_transition_moment_reached()
	return true

func _find_transition_fx() -> Node:
	var airlock := _find_airlock_controller()
	if not is_instance_valid(airlock):
		return null
	for child in airlock.get_children():
		if child.has_method("is_transition_moment_reached"):
			return child
	return null

func _is_airlock_transition_requested() -> bool:
	var airlock := _find_airlock_controller()
	if not is_instance_valid(airlock):
		return true
	if airlock.has_method("is_transition_requested"):
		return bool(airlock.is_transition_requested())
	return true

func _find_airlock_controller() -> Node:
	if not airlock_controller_path.is_empty():
		var configured = get_node_or_null(airlock_controller_path)
		if configured:
			return configured

	var node: Node = self
	while node:
		if node is AirlockControllerV2:
			return node
		node = node.get_parent()
	return null

func _get_player() -> Node:
	if is_instance_valid(_tracked_player):
		return _tracked_player

	var session = get_node_or_null("/root/SessionManager")
	if session and is_instance_valid(session.player):
		_tracked_player = session.player
		return _tracked_player

	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player):
			_tracked_player = player
			return _tracked_player
	return null

func _resolve_active_dome_id() -> String:
	var node: Node = self
	while node:
		if node.has_meta("dome_id"):
			return String(node.get_meta("dome_id")).strip_edges()
		node = node.get_parent()

	var player = _get_player()
	if is_instance_valid(player) and player.has_meta("dome_id"):
		return String(player.get_meta("dome_id")).strip_edges()

	var scene = get_tree().current_scene
	if is_instance_valid(scene) and scene.has_meta("dome_id"):
		return String(scene.get_meta("dome_id")).strip_edges()

	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager:
		var params = scene_manager.get("_transition_params")
		if typeof(params) == TYPE_DICTIONARY:
			if params.has("dome_id"):
				return String(params.get("dome_id", "")).strip_edges()
			var state_data = params.get("state_data", {})
			if typeof(state_data) == TYPE_DICTIONARY and state_data.has("active_dome_id"):
				return String(state_data.get("active_dome_id", "")).strip_edges()

	return ""

func _push_airlock_camera(body: Node) -> void:
	if not is_instance_valid(body):
		return
	var current = body.get("base_spring_length_3d")
	if current == null:
		return
	var restore_length := -1.0
	if body.has_meta("airlock_restore_spring_length"):
		restore_length = float(body.get_meta("airlock_restore_spring_length"))
	_saved_spring_length = restore_length if restore_length > 0.0 else float(current)
	_set_player_spring_length(body, AIRLOCK_OTS_SPRING_LENGTH)

func _pop_airlock_camera(body: Node) -> void:
	if not is_instance_valid(body) or _saved_spring_length < 0.0:
		return
	_set_player_spring_length(body, _saved_spring_length, false)
	if body.has_meta("airlock_restore_spring_length"):
		body.remove_meta("airlock_restore_spring_length")
	_saved_spring_length = -1.0

func _set_player_spring_length(body: Node, length: float, immediate: bool = true) -> void:
	if "base_spring_length_3d" in body:
		body.set("base_spring_length_3d", length)
	if immediate and "current_spring_length" in body:
		body.set("current_spring_length", length)
	var arm = _find_spring_arm(body)
	if is_instance_valid(arm) and "spring_length" in arm:
		arm.set("spring_length", length)
		if immediate and "current_length" in arm:
			arm.set("current_length", length)

func _find_spring_arm(body: Node) -> Node:
	var rig = body.get_node_or_null("CameraRig/Yaw/Pitch/OTS_Offset/SpringArm")
	if is_instance_valid(rig):
		return rig
	return body.get_node_or_null("CameraRig/Yaw/Pitch/SpringArm")

func _is_player(node: Node) -> bool:
	return is_instance_valid(node) and node.is_in_group("player")

func _update_indicator_lights() -> void:
	var red = get_parent().get_node_or_null("LoadingRedLight") if get_parent() else null
	var green = get_parent().get_node_or_null("ReadyGreenLight") if get_parent() else null

	if red and red is Light:
		red.light_energy = 1.8 if _background_load != null or _stalling else 0.25
	if green and green is Light:
		green.light_energy = 1.6 if _scene_ready else 0.2
