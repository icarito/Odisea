extends BaseZoneV2
class_name AirlockZoneV2

const PRELOAD_POLL_BUDGET_MS := 4
const DEFAULT_FADE_OUT_S := 0.14
const DEFAULT_FADE_IN_S := 0.16
const STALL_START_PROGRESS := 0.5
const TRIGGER_PROGRESS := 0.6

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

func _ready() -> void:
	._ready()
	if Engine.editor_hint:
		return
	set_physics_process(true)
	_update_indicator_lights()

func _on_zone_entered(body: Node) -> void:
	if Engine.editor_hint:
		return
	if not _is_player(body):
		return

	_tracked_player = body
	_player_in_zone = true
	_has_safe_relative_y = false
	_start_airlock_cycle()
	_begin_background_load()

func _physics_process(_delta: float) -> void:
	if Engine.editor_hint:
		return

	_poll_background_load()
	_update_indicator_lights()

	if not _player_in_zone:
		return

	var player := _get_player()
	if not (is_instance_valid(player) and player is Spatial):
		return
	if not is_body_in_zone(player):
		_player_in_zone = false
		_stalling = false
		_update_indicator_lights()
		return

	_update_progress(player as Spatial)

	if _progress >= STALL_START_PROGRESS and not _scene_ready:
		_stalling = true
		_apply_soft_stall(player)
	else:
		_stalling = false

	if _progress >= TRIGGER_PROGRESS and _scene_ready and not _has_triggered:
		_has_triggered = true
		call_deferred("_run_transition", player)

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

func _apply_soft_stall(player: Node) -> void:
	var progress_span := max(TRIGGER_PROGRESS - STALL_START_PROGRESS, 0.001)
	var t := clamp((_progress - STALL_START_PROGRESS) / progress_span, 0.0, 1.0)
	var factor: float = lerp(0.65, 0.35, t)

	if "movement_logic" in player and is_instance_valid(player.movement_logic):
		player.movement_logic.wish_direction *= factor
		# Do NOT multiply horizontal_velocity directly — applying factor every frame
		# causes oscillation: velocity decays, movement regenerates it from input,
		# stall decays again. This 2-5cm oscillation exceeds the camera arm's latch
		# epsilon (2.5cm) and invalidates the collision latch each frame → camera jitter.
		# Scaling wish_direction is enough: the movement system decelerates naturally.

func _run_transition(player: Node) -> void:
	if not is_instance_valid(player):
		player = _get_player()
	if not _is_player(player):
		_has_triggered = false
		return

	_trigger_transition(player)

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

	var params := {
		"spawn_id": resolved_target_spawn_id,
		"target_spawn_id": resolved_target_spawn_id,
		"dome_id": active_dome_id,
		"transition": "fade",
		"transition_style": "airlock",
		"preserve_player_state": true,
		"fade_out": DEFAULT_FADE_OUT_S,
		"fade_in": DEFAULT_FADE_IN_S,
		"show_loading": false,
		"wait_for_fade_out": true,
		"state_data": _build_state_data(player)
	}

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

func _start_airlock_cycle() -> void:
	var airlock = _find_airlock_controller()
	if not is_instance_valid(airlock):
		return
	if airlock.has_method("is_airlock_ready") and airlock.is_airlock_ready():
		return
	var entry_door := "outer" if _is_moving_outer_to_inner() else "inner"
	if airlock.has_method("start_transition_cycle"):
		airlock.start_transition_cycle(entry_door)

func _is_moving_outer_to_inner() -> bool:
	return _get_local_zone_direction().dot(Vector3.FORWARD) >= 0.0

func _get_exit_door_for_direction() -> String:
	return "inner" if _is_moving_outer_to_inner() else "outer"

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

func _is_player(node: Node) -> bool:
	return is_instance_valid(node) and node.is_in_group("player")

func _update_indicator_lights() -> void:
	var red = get_parent().get_node_or_null("LoadingRedLight") if get_parent() else null
	var green = get_parent().get_node_or_null("ReadyGreenLight") if get_parent() else null

	if red and red is Light:
		red.light_energy = 1.8 if _background_load != null or _stalling else 0.25
	if green and green is Light:
		green.light_energy = 1.6 if _scene_ready else 0.2
