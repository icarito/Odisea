tool
extends Area
class_name TransitionPortal

signal transition_requested(target_scene, params)
signal transition_aborted(reason)

const AIRLOCK_WAIT_TIMEOUT_S := 8.0
const PRELOAD_POLL_BUDGET_MS := 4

export(String, FILE, "*.tscn") var target_scene := ""
export(String) var target_spawn_id := ""
export(String, "airlock", "fade", "instant") var transition_style := "airlock"
export(bool) var preserve_player_state := true
export(float, 0.0, 3.0) var fade_out := 0.2
export(float, 0.0, 3.0) var fade_in := 0.2
export(NodePath) var airlock_controller_path
export(Vector3) var required_entry_direction := Vector3.ZERO
export(float, -1.0, 1.0) var min_entry_alignment := 0.25
export(NodePath) var target_airlock_path
export(String, "outer", "inner", "none") var target_airlock_exit_door := "outer"
export(float, 0.0, 1.0) var exit_progress_threshold := 0.78

var _is_activating := false
var _input_restore_state := {}
var _airlock_wait_done := false
var _tracked_player: Node = null
var _preload_loader: ResourceInteractiveLoader = null
var _preloaded_scene: PackedScene = null
var _preload_error := ""
var _preload_started := false

func _ready() -> void:
	if Engine.editor_hint:
		return
	monitoring = true
	if not is_connected("body_entered", self, "_on_body_entered"):
		connect("body_entered", self, "_on_body_entered")
	if not is_in_group("interactable"):
		add_to_group("interactable")
	set_process(true)

func interact(actor: Node = null) -> void:
	var player := actor
	if not _is_player(player):
		player = _find_current_player()
	_begin_preload(player)

func _on_body_entered(body: Node) -> void:
	if _is_player(body) and _passes_entry_direction(body):
		_begin_preload(body)

func _process(_delta: float) -> void:
	if Engine.editor_hint:
		return
	_poll_preload()
	if _preloaded_scene != null and is_instance_valid(_tracked_player) and _is_player_at_exit(_tracked_player):
		var state = _activate(_tracked_player)
		if state is GDScriptFunctionState:
			yield(state, "completed")

func _begin_preload(player: Node = null) -> bool:
	if _is_activating:
		return false
	if target_scene.strip_edges() == "":
		emit_signal("transition_aborted", "missing_target_scene")
		printerr("[TransitionPortal] Missing target_scene on ", name)
		return false
	if not is_instance_valid(player):
		player = _find_current_player()
	if not _is_player(player):
		return false

	_tracked_player = player
	if _preloaded_scene != null:
		return true
	if _preload_started:
		return true

	_preload_loader = ResourceLoader.load_interactive(target_scene)
	if _preload_loader == null:
		_preload_error = "Could not create ResourceInteractiveLoader for %s" % target_scene
		emit_signal("transition_aborted", _preload_error)
		printerr("[TransitionPortal] ", _preload_error)
		return false
	_preload_started = true
	return true

func _poll_preload() -> void:
	if _preload_loader == null:
		return
	var start_ms := OS.get_ticks_msec()
	while _preload_loader != null and OS.get_ticks_msec() - start_ms < PRELOAD_POLL_BUDGET_MS:
		var err = _preload_loader.poll()
		if err == OK:
			continue
		if err == ERR_FILE_EOF:
			var resource = _preload_loader.get_resource()
			if resource and resource is PackedScene:
				_preloaded_scene = resource
			else:
				_preload_error = "Loaded resource is not a PackedScene: %s" % target_scene
				emit_signal("transition_aborted", _preload_error)
				printerr("[TransitionPortal] ", _preload_error)
			_preload_loader = null
			return
		_preload_error = "Loader poll failed (%d) for %s" % [err, target_scene]
		emit_signal("transition_aborted", _preload_error)
		printerr("[TransitionPortal] ", _preload_error)
		_preload_loader = null
		return

func _activate(player: Node = null):
	if Engine.editor_hint:
		return false
	if _is_activating:
		return false
	if target_scene.strip_edges() == "":
		emit_signal("transition_aborted", "missing_target_scene")
		printerr("[TransitionPortal] Missing target_scene on ", name)
		return false

	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager == null or not scene_manager.has_method("goto_scene"):
		emit_signal("transition_aborted", "missing_scene_manager")
		printerr("[TransitionPortal] SceneManager autoload missing")
		return false

	_is_activating = true
	if not is_instance_valid(player):
		player = _find_current_player()

	_capture_and_disable_input(player)

	if transition_style == "airlock":
		var wait_state = _run_airlock_cycle()
		if wait_state is GDScriptFunctionState:
			yield(wait_state, "completed")

	var params := _build_transition_params(player)
	if _preloaded_scene != null:
		params["_preloaded_scene"] = _preloaded_scene
	emit_signal("transition_requested", target_scene, params)
	var state = scene_manager.goto_scene(target_scene, params)
	if state is GDScriptFunctionState:
		var ok = yield(state, "completed")
		if ok == false:
			_restore_input(player)
			_is_activating = false
			return false
	elif state == false:
		_restore_input(player)
		_is_activating = false
		return false
	return true

func _build_transition_params(player: Node) -> Dictionary:
	return {
		"spawn_id": target_spawn_id,
		"target_spawn_id": target_spawn_id,
		"transition": _scene_manager_transition_mode(),
		"transition_style": transition_style,
		"preserve_player_state": preserve_player_state,
		"fade_out": fade_out,
		"fade_in": fade_in,
		"show_loading": transition_style == "fade",
		"state_data": _build_state_data(player),
		"input_restore_state": _input_restore_state.duplicate(true)
	}

func _build_state_data(player: Node) -> Dictionary:
	var state_data := {}
	if preserve_player_state and is_instance_valid(player) and player.has_method("get_full_snapshot"):
		var snapshot = player.get_full_snapshot()
		if typeof(snapshot) == TYPE_DICTIONARY:
			state_data["player_snapshot"] = snapshot.duplicate(true)
			if snapshot.has("gravity_mode"):
				state_data["gravity_mode"] = snapshot["gravity_mode"]
			if snapshot.has("controller_mode"):
				state_data["controller_mode"] = snapshot["controller_mode"]

	if is_instance_valid(player):
		var controller_manager = player.get_node_or_null("ControllerManager")
		if controller_manager and "current_mode" in controller_manager:
			state_data["controller_mode"] = controller_manager.current_mode

	var gravity_world = get_node_or_null("/root/GravityWorld")
	if gravity_world:
		if gravity_world.has_method("get_snapshot"):
			var world_snapshot = gravity_world.get_snapshot()
			if typeof(world_snapshot) == TYPE_DICTIONARY:
				state_data["gravity_world_snapshot"] = world_snapshot.duplicate(true)
		if not state_data.has("gravity_mode") and gravity_world.has_method("get_current_gravity_mode"):
			state_data["gravity_mode"] = gravity_world.get_current_gravity_mode()

	_append_airlock_frame_state(state_data, player)
	return state_data

func _append_airlock_frame_state(state_data: Dictionary, player: Node) -> void:
	if not (is_instance_valid(player) and player is Spatial):
		return
	var source_airlock = _find_airlock_controller()
	if not (is_instance_valid(source_airlock) and source_airlock is Spatial):
		return
	if target_airlock_path.is_empty():
		return

	var source_transform: Transform = (source_airlock as Spatial).global_transform
	var player_transform: Transform = (player as Spatial).global_transform
	state_data["airlock_relative_transform"] = source_transform.affine_inverse() * player_transform
	state_data["target_airlock_path"] = String(target_airlock_path)
	state_data["target_airlock_exit_door"] = target_airlock_exit_door

	if "velocity" in player:
		var velocity: Vector3 = player.velocity
		state_data["airlock_relative_velocity"] = source_transform.basis.xform_inv(velocity)

func _scene_manager_transition_mode() -> String:
	match transition_style:
		"instant":
			return "instant"
		"fade":
			return "fade"
		"airlock":
			return "fade"
	return "fade"

func _passes_entry_direction(body: Node) -> bool:
	if required_entry_direction.length_squared() <= 0.0001:
		return true
	if not is_instance_valid(body):
		return false
	if not ("velocity" in body):
		return false

	var movement: Vector3 = body.velocity
	if movement.length_squared() <= 0.0025:
		return false

	var required_global := global_transform.basis.xform(required_entry_direction).normalized()
	if required_global.length_squared() <= 0.0001:
		return true
	return movement.normalized().dot(required_global) >= min_entry_alignment

func _is_player_at_exit(player: Node) -> bool:
	if not (is_instance_valid(player) and player is Spatial):
		return false
	var source_airlock = _find_airlock_controller()
	if not (is_instance_valid(source_airlock) and source_airlock is Spatial):
		return true

	var direction := required_entry_direction
	if direction.length_squared() <= 0.0001:
		direction = Vector3(0, 0, -1)
	direction = direction.normalized()

	var local_pos: Vector3 = (source_airlock as Spatial).global_transform.affine_inverse().xform((player as Spatial).global_transform.origin)
	var half_length := _get_airlock_half_length(source_airlock, direction)
	if half_length <= 0.001:
		return true

	var projected := local_pos.dot(direction)
	var progress := clamp((projected + half_length) / (half_length * 2.0), 0.0, 1.0)
	return progress >= exit_progress_threshold

func _get_airlock_half_length(source_airlock: Node, direction: Vector3) -> float:
	var zone = null
	if source_airlock is AirlockControllerV2 and "chamber_zone_path" in source_airlock:
		zone = source_airlock.get_node_or_null(source_airlock.chamber_zone_path)
	if zone == null and source_airlock:
		zone = source_airlock.find_node("ChamberZone", true, false)
	if zone:
		var shape_node = zone.get_node_or_null("CollisionShape")
		if shape_node is CollisionShape and shape_node.shape is BoxShape:
			var extents: Vector3 = shape_node.shape.extents
			var abs_dir := Vector3(abs(direction.x), abs(direction.y), abs(direction.z))
			if abs_dir.x >= abs_dir.y and abs_dir.x >= abs_dir.z:
				return extents.x
			if abs_dir.y >= abs_dir.x and abs_dir.y >= abs_dir.z:
				return extents.y
			return extents.z
	return 4.0

func _run_airlock_cycle():
	var airlock = _find_airlock_controller()
	if airlock == null:
		return
	if airlock.has_method("is_airlock_ready") and airlock.is_airlock_ready():
		return

	_airlock_wait_done = false
	if airlock.has_signal("airlock_ready") and not airlock.is_connected("airlock_ready", self, "_on_airlock_wait_done"):
		airlock.connect("airlock_ready", self, "_on_airlock_wait_done", [], CONNECT_ONESHOT)
	if airlock.has_signal("airlock_cycle_completed") and not airlock.is_connected("airlock_cycle_completed", self, "_on_airlock_wait_done"):
		airlock.connect("airlock_cycle_completed", self, "_on_airlock_wait_done", [], CONNECT_ONESHOT)
	if airlock.has_method("start_cycle"):
		airlock.start_cycle(true)
	elif airlock.has_method("interact"):
		airlock.interact()

	var start_ms := OS.get_ticks_msec()
	while not _airlock_wait_done and OS.get_ticks_msec() - start_ms < int(AIRLOCK_WAIT_TIMEOUT_S * 1000.0):
		yield(get_tree(), "physics_frame")

func _on_airlock_wait_done() -> void:
	_airlock_wait_done = true

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

	var scene_root = get_tree().current_scene
	if scene_root:
		return scene_root.find_node("*Airlock*", true, false)
	return null

func _capture_and_disable_input(player: Node) -> void:
	_input_restore_state = {
		"valid": false,
		"hardware_input_enabled": true,
		"is_replay_mode": false
	}
	if not is_instance_valid(player):
		return

	_input_restore_state["valid"] = true
	if "is_replay_mode" in player:
		_input_restore_state["is_replay_mode"] = bool(player.is_replay_mode)
	if "input_provider" in player and is_instance_valid(player.input_provider):
		_input_restore_state["hardware_input_enabled"] = bool(player.input_provider.hardware_input_enabled)
		player.input_provider.hardware_input_enabled = false

func _restore_input(player: Node) -> void:
	if not is_instance_valid(player):
		return
	if not bool(_input_restore_state.get("valid", false)):
		return
	if "is_replay_mode" in player:
		player.is_replay_mode = bool(_input_restore_state.get("is_replay_mode", false))
	if "input_provider" in player and is_instance_valid(player.input_provider):
		player.input_provider.hardware_input_enabled = bool(_input_restore_state.get("hardware_input_enabled", true))

func _find_current_player() -> Node:
	var session = get_node_or_null("/root/SessionManager")
	if session and is_instance_valid(session.player):
		return session.player
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player):
			return player
	return null

func _is_player(node: Node) -> bool:
	return is_instance_valid(node) and node.is_in_group("player")
