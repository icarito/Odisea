extends BaseZoneV2
class_name AirlockZoneV2

const PRELOAD_POLL_BUDGET_MS := 4
const DEFAULT_FADE_OUT_S := 0.2
const DEFAULT_FADE_IN_S := 0.2
const STALL_START_PROGRESS := 0.85
const TRIGGER_PROGRESS := 0.9

export(String, FILE, "*.tscn") var target_scene := ""
export(String) var target_spawn_id := ""
export(NodePath) var airlock_controller_path
export(NodePath) var target_airlock_path
export(Vector3) var zone_dir := Vector3.FORWARD

var _progress := 0.0
var _relative_position := Vector3.ZERO
var _relative_transform := Transform.IDENTITY
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
	_relative_transform = global_transform.affine_inverse() * player.global_transform
	_update_safe_relative_y(player, local_pos)

func _apply_soft_stall(player: Node) -> void:
	var progress_span := max(TRIGGER_PROGRESS - STALL_START_PROGRESS, 0.001)
	var t := clamp((_progress - STALL_START_PROGRESS) / progress_span, 0.0, 1.0)
	var factor: float = lerp(0.65, 0.35, t)

	if "movement_logic" in player and is_instance_valid(player.movement_logic):
		player.movement_logic.wish_direction *= factor
		if "horizontal_velocity" in player.movement_logic:
			player.movement_logic.horizontal_velocity *= factor

func _run_transition(player: Node) -> void:
	if not is_instance_valid(player):
		player = _get_player()
	if not _is_player(player):
		_has_triggered = false
		return

	var transition_layer = get_node_or_null("/root/TransitionLayer")
	if transition_layer and transition_layer.has_method("play"):
		transition_layer.play("fade_out", {
			"duration": DEFAULT_FADE_OUT_S,
			"show_loading": false
		})
		yield(get_tree().create_timer(DEFAULT_FADE_OUT_S), "timeout")

	_trigger_transition(player)

func _trigger_transition(player: Node) -> bool:
	if target_scene.strip_edges() == "":
		printerr("[AirlockZoneV2] Missing target_scene on ", name)
		return false

	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager == null or not scene_manager.has_method("goto_scene"):
		printerr("[AirlockZoneV2] SceneManager autoload missing")
		return false

	var params := {
		"spawn_id": target_spawn_id,
		"target_spawn_id": target_spawn_id,
		"transition": "fade",
		"transition_style": "airlock",
		"preserve_player_state": true,
		"fade_out": 0.0,
		"fade_in": DEFAULT_FADE_IN_S,
		"show_loading": false,
		"state_data": _build_state_data(player)
	}

	if _preloaded_scene != null:
		params["_preloaded_scene"] = _preloaded_scene

	scene_manager.goto_scene(target_scene, params)
	return true

func _build_state_data(player: Node) -> Dictionary:
	var state_data := {}
	if is_instance_valid(player) and player.has_method("get_full_snapshot"):
		var snapshot = player.get_full_snapshot()
		if typeof(snapshot) == TYPE_DICTIONARY:
			state_data["player_snapshot"] = snapshot.duplicate(true)
			if snapshot.has("gravity_mode"):
				state_data["gravity_mode"] = snapshot["gravity_mode"]
			if snapshot.has("controller_mode"):
				state_data["controller_mode"] = snapshot["controller_mode"]

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
		state_data["target_airlock_exit_door"] = _get_exit_door_for_direction()
		if not target_airlock_path.is_empty():
			state_data["target_airlock_path"] = String(target_airlock_path)

		if "velocity" in player:
			var velocity: Vector3 = player.velocity
			var relative_velocity: Vector3 = frame.basis.xform_inv(velocity)
			if _has_safe_relative_y and relative_transform.origin.y < _last_safe_relative_y - 0.35 and relative_velocity.y < 0.0:
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
	if airlock.has_method("start_cycle"):
		airlock.start_cycle(_is_moving_outer_to_inner())

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

func _is_player(node: Node) -> bool:
	return is_instance_valid(node) and node.is_in_group("player")

func _update_indicator_lights() -> void:
	var red = get_parent().get_node_or_null("LoadingRedLight") if get_parent() else null
	var green = get_parent().get_node_or_null("ReadyGreenLight") if get_parent() else null

	if red and red is Light:
		red.light_energy = 1.8 if _background_load != null or _stalling else 0.25
	if green and green is Light:
		green.light_energy = 1.6 if _scene_ready else 0.2
