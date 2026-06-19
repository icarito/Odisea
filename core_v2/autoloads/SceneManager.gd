extends Node

signal transition_started(path, params)
signal transition_progress(path, progress)
signal pre_scene_swap(old_scene, new_scene, params)
signal pre_spawn_state(path, scene_root, params)
signal scene_ready(path, scene_root, params)
signal transition_completed(path, scene_root, params)
signal transition_failed(path, reason)

export(int, 1, 20) var poll_budget_ms := 6
export(int, 1, 40) var weak_poll_budget_ms := 10
export(int, 1, 80) var hyper_low_poll_budget_ms := 14
export(float, 0.0, 3.0) var default_fade_out := 0.35
export(float, 0.0, 3.0) var default_fade_in := 0.35
export(float, 0.0, 3.0) var default_audio_fade_out := 0.35
export(float, 0.0, 3.0) var default_audio_fade_in := 0.35
export(float, 3.0, 60.0) var transition_timeout_s := 9.0
export(float, 3.0, 120.0) var weak_transition_timeout_s := 20.0
export(float, 3.0, 180.0) var hyper_low_transition_timeout_s := 35.0
export(bool) var boot_fade_in_enabled := true
export(float, 0.0, 5.0) var boot_fade_in_duration := 0.55
export(int, 0, 10) var boot_fade_in_wait_frames := 1

var _loader = null
var _loaded_scene: PackedScene = null
var _load_error := ""
var _is_loading := false
var _is_transitioning := false
var _next_scene_path := ""
var _transition_params: Dictionary = {}
var _captured_player_state: Dictionary = {}
var _input_restore_state: Dictionary = {}
var _transition_started_ms := 0
var _loader_last_progress_ms := 0
var _loader_last_stage := -1
var _last_transition_abort_reason := ""
var _pending_scene_path := ""
var _pending_transition_params: Dictionary = {}
var _boot_fade_consumed := false
var _preload_loaders: Dictionary = {}
var _preloaded_scenes: Dictionary = {}
var _preload_errors: Dictionary = {}

func _ready() -> void:
	call_deferred("_run_boot_fade_in")

func _process(_delta: float) -> void:
	_poll_loader()
	_poll_scene_preload()
	_check_transition_timeout()
	_drain_pending_transition()

func is_transitioning() -> bool:
	return _is_transitioning

func goto_scene(path: String, params: Dictionary = {}):
	var target_path := String(path).strip_edges()
	if target_path == "":
		printerr("[SceneManager] goto_scene called with empty path")
		return false
	if _is_transitioning:
		_pending_scene_path = target_path
		_pending_transition_params = params.duplicate(true)
		printerr("[SceneManager] Transition already in progress. Queued: ", target_path)
		return false

	_is_transitioning = true
	_transition_started_ms = OS.get_ticks_msec()
	_next_scene_path = target_path
	var supplied_preloaded_scene = params.get("_preloaded_scene", null)
	var sanitized_params = params.duplicate(false)
	sanitized_params.erase("_preloaded_scene")
	_transition_params = sanitized_params.duplicate(true)
	_loaded_scene = null
	_load_error = ""
	_loader = null
	_is_loading = false
	_loader_last_progress_ms = 0
	_loader_last_stage = -1
	_last_transition_abort_reason = ""

	_capture_player_state_for_transition()
	_disable_input_for_transition()
	_fade_audio_out(float(_transition_params.get("audio_fade_out", default_audio_fade_out)))
	emit_signal("transition_started", _next_scene_path, _transition_params)

	var transition_layer = _get_transition_layer()
	var transition_mode := _get_transition_mode()
	var show_loading := _should_show_loading(transition_mode)
	var use_fade := _should_use_fade(transition_mode)
	if transition_layer:
		if show_loading and transition_layer.has_method("show_loading"):
			transition_layer.show_loading(
				String(_transition_params.get("loading_message", "Cargando...")),
				bool(_transition_params.get("show_progress", true))
			)
		if use_fade and transition_layer.has_method("play"):
			var fade_out_duration := max(0.0, float(_transition_params.get("fade_out", default_fade_out)))
			transition_layer.play("fade_out", {
				"duration": fade_out_duration,
				"show_loading": show_loading
			})
			if bool(_transition_params.get("wait_for_fade_out", false)) and fade_out_duration > 0.0:
				yield(get_tree().create_timer(fade_out_duration), "timeout")

	if supplied_preloaded_scene and supplied_preloaded_scene is PackedScene:
		_loaded_scene = supplied_preloaded_scene
		_emit_progress(1.0)
	elif has_preloaded_scene(_next_scene_path):
		_loaded_scene = get_preloaded_scene(_next_scene_path)
		_emit_progress(1.0)
	else:
		while is_scene_preloading(_next_scene_path):
			yield(get_tree(), "idle_frame")
		if has_preloaded_scene(_next_scene_path):
			_loaded_scene = get_preloaded_scene(_next_scene_path)
			_emit_progress(1.0)
		else:
			_start_loader(_next_scene_path)
			while _is_loading:
				yield(get_tree(), "idle_frame")

	if _last_transition_abort_reason != "":
		return false

	if _load_error != "":
		_finalize_failed_transition(_load_error)
		return false

	var set_state = _set_new_scene(_loaded_scene)
	if set_state is GDScriptFunctionState:
		yield(set_state, "completed")
	if _load_error != "":
		_finalize_failed_transition(_load_error)
		return false

	_fade_audio_in(float(_transition_params.get("audio_fade_in", default_audio_fade_in)))

	if transition_layer:
		if use_fade and transition_layer.has_method("play"):
			transition_layer.play("fade_in", {
				"duration": float(_transition_params.get("fade_in", default_fade_in))
			})
		elif show_loading and transition_layer.has_method("hide_loading"):
			transition_layer.hide_loading()

	_restore_input_after_transition()
	emit_signal("transition_completed", _next_scene_path, get_tree().current_scene, _transition_params)

	var completed := true
	_reset_runtime_state()
	return completed

func _start_loader(path: String) -> void:
	_loader = ResourceLoader.load_interactive(path)
	if _loader == null:
		_load_error = "Could not create ResourceInteractiveLoader for %s" % path
		_is_loading = false
		return
	_is_loading = true
	_loader_last_progress_ms = OS.get_ticks_msec()
	_loader_last_stage = -1
	_emit_progress(0.0)

func _poll_loader() -> void:
	if not _is_loading or _loader == null:
		return

	var start_ms := OS.get_ticks_msec()
	var budget_ms := _get_effective_poll_budget_ms()
	while _is_loading and (OS.get_ticks_msec() - start_ms) < budget_ms:
		var err = _loader.poll()
		if err == OK:
			var stage_count = max(1, _loader.get_stage_count())
			var stage = _loader.get_stage()
			if stage != _loader_last_stage:
				_loader_last_stage = stage
				_loader_last_progress_ms = OS.get_ticks_msec()
			_emit_progress(float(stage) / float(stage_count))
		elif err == ERR_FILE_EOF:
			var resource = _loader.get_resource()
			_loader_last_progress_ms = OS.get_ticks_msec()
			if resource and resource is PackedScene:
				_loaded_scene = resource
				_emit_progress(1.0)
			else:
				_load_error = "Loaded resource is not a PackedScene: %s" % _next_scene_path
			_is_loading = false
			_loader = null
		else:
			_load_error = "Loader poll failed (%d) for %s" % [err, _next_scene_path]
			_is_loading = false
			_loader = null

func request_scene_preload(path: String) -> bool:
	var target_path := String(path).strip_edges()
	if target_path == "":
		return false
	if has_preloaded_scene(target_path) or is_scene_preloading(target_path):
		return true
	var loader := ResourceLoader.load_interactive(target_path)
	if loader == null:
		_preload_errors[target_path] = "loader_create_failed"
		return false
	_preload_errors.erase(target_path)
	_preload_loaders[target_path] = loader
	return true

func has_preloaded_scene(path: String) -> bool:
	return _preloaded_scenes.has(String(path).strip_edges())

func get_preloaded_scene(path: String) -> PackedScene:
	var resource = _preloaded_scenes.get(String(path).strip_edges(), null)
	return resource as PackedScene if resource is PackedScene else null

func is_scene_preloading(path: String) -> bool:
	return _preload_loaders.has(String(path).strip_edges())

func get_scene_preload_error(path: String) -> String:
	return String(_preload_errors.get(String(path).strip_edges(), ""))

func _poll_scene_preload() -> void:
	if _is_loading or _preload_loaders.empty():
		return
	var path: String = String(_preload_loaders.keys()[0])
	var loader = _preload_loaders[path]
	var err = loader.poll()
	if err == OK:
		if _is_transitioning and path == _next_scene_path:
			var stage_count: int = int(max(1, loader.get_stage_count()))
			var stage: int = int(loader.get_stage())
			if stage != _loader_last_stage:
				_loader_last_stage = stage
				_loader_last_progress_ms = OS.get_ticks_msec()
			_emit_progress(float(stage) / float(stage_count))
		return
	_preload_loaders.erase(path)
	if err == ERR_FILE_EOF:
		var resource = loader.get_resource()
		if resource and resource is PackedScene:
			_preloaded_scenes[path] = resource
			_preload_errors.erase(path)
			return
		_preload_errors[path] = "loaded_resource_is_not_scene"
		return
	_preload_errors[path] = "loader_poll_failed_%d" % err

func _emit_progress(progress_01: float) -> void:
	var p := clamp(progress_01, 0.0, 1.0)
	emit_signal("transition_progress", _next_scene_path, p)
	var transition_layer = _get_transition_layer()
	if transition_layer and transition_layer.has_method("set_loading_progress"):
		transition_layer.set_loading_progress(p)

func _set_new_scene(resource: PackedScene):
	if resource == null:
		_load_error = "Scene resource is null"
		return

	var new_scene = resource.instance()
	if new_scene == null:
		_load_error = "Could not instance scene %s" % _next_scene_path
		return

	var tree := get_tree()
	var old_scene := tree.current_scene
	var airlock_manager = get_node_or_null("/root/AirlockManager")
	# Capture _seamless_swap BEFORE emitting pre_scene_swap, because the signal handler
	# (_on_pre_scene_swap in AirlockManager) clears the flag after lifting the player.
	var seamless: bool = is_instance_valid(airlock_manager) and bool(airlock_manager.get("_seamless_swap"))

	if is_instance_valid(old_scene) and old_scene != new_scene:
		emit_signal("pre_scene_swap", old_scene, new_scene, _transition_params)
		if seamless:
			# Seamless path: add new scene first so there is never a black frame,
			# then free the old one. The player is held by AirlockManager (in /root)
			# so it survives and the camera keeps rendering throughout.
			tree.root.add_child(new_scene)
			tree.current_scene = new_scene
			old_scene.queue_free()
		else:
			tree.current_scene = null
			old_scene.queue_free()
			# Avoid scene overlap spikes (memory/VRAM) before adding the replacement.
			yield(tree, "idle_frame")
			tree.root.add_child(new_scene)
			tree.current_scene = new_scene
	else:
		tree.root.add_child(new_scene)
		tree.current_scene = new_scene

	yield(tree, "idle_frame")
	if not seamless:
		yield(tree, "idle_frame")

	emit_signal("pre_spawn_state", _next_scene_path, new_scene, _transition_params)

	var prep_state = _apply_spawn_and_state(new_scene)
	if prep_state is GDScriptFunctionState:
		yield(prep_state, "completed")

	emit_signal("scene_ready", _next_scene_path, new_scene, _transition_params)

	# Spread heavy deferred-build nodes (e.g. RadialScatter with dozens of items)
	# across frames so they don't instance everything in the arrival frame — that
	# bulk instancing is the load spike felt as a freeze on scene transition.
	call_deferred("_drive_deferred_builds")

# Generic incremental driver: any node in the "deferred_build" group that exposes
# begin_deferred_build()/deferred_build_step()/has_pending_deferred_items() gets
# its build spread over multiple frames. Decouples scenes from this logic — a node
# just joins the group and the costly instancing is amortized automatically.
func _drive_deferred_builds() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var nodes := tree.get_nodes_in_group("deferred_build")
	var pending := []
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if node.has_method("begin_deferred_build") and node.has_method("deferred_build_step") \
				and node.has_method("has_pending_deferred_items"):
			node.begin_deferred_build()
			pending.append(node)
	# Drive one step per node per frame until all are done.
	while not pending.empty():
		yield(tree, "idle_frame")
		var still_pending := []
		for node in pending:
			if not is_instance_valid(node):
				continue
			node.deferred_build_step()
			if node.has_pending_deferred_items():
				still_pending.append(node)
		pending = still_pending

func _apply_spawn_and_state(scene_root: Node):
	if not is_instance_valid(scene_root):
		return

	var session = get_node_or_null("/root/SessionManager")
	var state_data = _transition_params.get("state_data", {})
	if typeof(state_data) != TYPE_DICTIONARY:
		state_data = {}

	if bool(_transition_params.get("preserve_player_state", true)) and _captured_player_state.size() > 0 and not state_data.has("player_snapshot"):
		state_data["player_snapshot"] = _captured_player_state.duplicate(true)

	_apply_transition_world_state(state_data)

	var target_spawn_id := String(_transition_params.get("target_spawn_id", _transition_params.get("spawn_id", ""))).strip_edges()
	if session and session.has_method("apply_scene_transition_state"):
		# Do not block the transition flow on physics waits from SessionManager.
		# This prevents getting stuck in _is_transitioning when scenes pause the tree.
		session.apply_scene_transition_state(target_spawn_id, state_data)
		return

	var spawn_node = _find_spawn_point(scene_root, target_spawn_id)
	var player = _find_player_in_scene(scene_root)
	if is_instance_valid(player) and state_data.has("player_snapshot") and typeof(state_data["player_snapshot"]) == TYPE_DICTIONARY and player.has_method("restore_snapshot"):
		player.restore_snapshot(state_data["player_snapshot"])
	elif is_instance_valid(player) and state_data.has("controller_mode"):
		var controller_manager = player.get_node_or_null("ControllerManager")
		if controller_manager and controller_manager.has_method("switch_to"):
			controller_manager.switch_to(int(state_data["controller_mode"]))

	var target_airlock = _find_transition_airlock(scene_root, state_data)
	var used_airlock_frame := false
	if is_instance_valid(player) and is_instance_valid(target_airlock) and typeof(state_data.get("airlock_relative_transform", null)) == TYPE_TRANSFORM:
		var relative_transform: Transform = state_data["airlock_relative_transform"]
		var target_transform: Transform = target_airlock.global_transform * relative_transform
		target_transform = _face_airlock_exit(target_airlock, state_data, target_transform)
		_move_player_to_transform(player, target_transform)
		_restore_transition_camera_state(player, state_data, target_transform, target_airlock)
		_snap_transition_visual(player, target_transform)
		_apply_airlock_relative_velocity(player, target_airlock, state_data)
		_open_transition_airlock_exit(target_airlock, state_data)
		used_airlock_frame = true

	if not used_airlock_frame and is_instance_valid(player) and is_instance_valid(spawn_node):
		_move_player_to_transform(player, spawn_node.global_transform)
		_restore_transition_camera_state(player, state_data, spawn_node.global_transform, null)
		_snap_transition_visual(player, spawn_node.global_transform)
	if session and is_instance_valid(player):
		session.player = player

func _apply_transition_world_state(state_data: Dictionary) -> void:
	var gravity_world = get_node_or_null("/root/GravityWorld")
	if gravity_world == null:
		return
	if state_data.has("gravity_world_snapshot") and typeof(state_data["gravity_world_snapshot"]) == TYPE_DICTIONARY and gravity_world.has_method("restore_snapshot"):
		gravity_world.restore_snapshot(state_data["gravity_world_snapshot"])
	elif state_data.has("gravity_mode") and gravity_world.has_method("set_gravity_mode"):
		gravity_world.set_gravity_mode(int(state_data["gravity_mode"]))

func _find_spawn_point(scene_root: Node, spawn_id: String) -> Position3D:
	if not is_instance_valid(scene_root):
		return null

	var fallback: Position3D = null
	var pending: Array = [scene_root]
	while not pending.empty():
		var node = pending.pop_front()
		if not is_instance_valid(node):
			continue
		if node is Position3D and "spawn_id" in node:
			var spawn_node := node as Position3D
			if fallback == null:
				fallback = spawn_node
			if spawn_id == "" or String(node.get("spawn_id")) == spawn_id:
				return spawn_node
		for child in node.get_children():
			pending.push_back(child)

	if spawn_id == "":
		return fallback
	return null

func _find_transition_airlock(scene_root: Node, state_data: Dictionary) -> Spatial:
	if not is_instance_valid(scene_root) or typeof(state_data) != TYPE_DICTIONARY:
		return null
	var target_path := String(state_data.get("target_airlock_path", "")).strip_edges()
	if target_path != "":
		var by_path = scene_root.get_node_or_null(NodePath(target_path))
		if is_instance_valid(by_path) and by_path is Spatial:
			return by_path
		var by_name = scene_root.find_node(target_path, true, false)
		if is_instance_valid(by_name) and by_name is Spatial:
			return by_name
	var fallback = scene_root.find_node("*Airlock*", true, false)
	if is_instance_valid(fallback) and fallback is Spatial:
		return fallback
	return null

func _apply_airlock_relative_velocity(player: Node, target_airlock: Spatial, state_data: Dictionary) -> void:
	if not is_instance_valid(player):
		return
	if not ("velocity" in player):
		return
	if typeof(state_data.get("airlock_relative_velocity", null)) != TYPE_VECTOR3:
		return
	var local_velocity: Vector3 = state_data["airlock_relative_velocity"]
	player.velocity = target_airlock.global_transform.basis.xform(local_velocity)

func _open_transition_airlock_exit(target_airlock: Spatial, state_data: Dictionary) -> void:
	if not is_instance_valid(target_airlock):
		return
	var exit_door := String(state_data.get("target_airlock_exit_door", "outer")).strip_edges().to_lower()
	if exit_door == "" or exit_door == "none":
		return
	if target_airlock.has_method("open_exit_door"):
		target_airlock.open_exit_door(exit_door, true, true)

func _face_airlock_exit(target_airlock: Spatial, state_data: Dictionary, target_transform: Transform) -> Transform:
	if not is_instance_valid(target_airlock):
		return target_transform
	var exit_door := String(state_data.get("target_airlock_exit_door", "outer")).strip_edges().to_lower()
	var local_exit_dir := Vector3.BACK
	if exit_door == "inner":
		local_exit_dir = Vector3.FORWARD
	elif exit_door == "none":
		return target_transform
	var exit_dir: Vector3 = target_airlock.global_transform.basis.xform(local_exit_dir)
	exit_dir.y = 0.0
	if exit_dir.length_squared() <= 0.0001:
		return target_transform
	exit_dir = exit_dir.normalized()
	var yaw := atan2(-exit_dir.x, -exit_dir.z)
	var out := target_transform
	out.basis = Basis(Vector3.UP, yaw)
	return out

func _find_player_in_scene(scene_root: Node) -> Node:
	if not is_instance_valid(scene_root):
		return null

	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if is_instance_valid(p) and scene_root.is_a_parent_of(p):
			return p

	var pilot = scene_root.find_node("Pilot", true, false)
	if is_instance_valid(pilot):
		return pilot
	return null

func _move_player_to_transform(player: Node, target_transform: Transform) -> void:
	if not is_instance_valid(player):
		return
	if player.has_method("teleport_to"):
		player.teleport_to(target_transform)
		return
	if player is Spatial:
		(player as Spatial).global_transform = target_transform

func _restore_transition_camera_state(player: Node, state_data: Dictionary, target_transform: Transform, target_airlock: Spatial = null) -> void:
	if not is_instance_valid(player):
		return
	if state_data.has("camera_yaw") and "yaw" in player:
		if is_instance_valid(target_airlock) and typeof(state_data.get("camera_relative_forward", null)) == TYPE_VECTOR3:
			var camera_forward: Vector3 = target_airlock.global_transform.basis.xform(state_data["camera_relative_forward"])
			camera_forward.y = 0.0
			if camera_forward.length_squared() > 0.0001:
				camera_forward = camera_forward.normalized()
				player.yaw = atan2(-camera_forward.x, -camera_forward.z)
			else:
				player.yaw = target_transform.basis.get_euler().y
		elif state_data.has("camera_body_yaw_offset"):
			player.yaw = target_transform.basis.get_euler().y + float(state_data["camera_body_yaw_offset"])
		else:
			player.yaw = float(state_data["camera_yaw"])
		if "yaw_deg" in player:
			player.yaw_deg = rad2deg(player.yaw)
	if state_data.has("camera_pitch") and "pitch" in player:
		player.pitch = float(state_data["camera_pitch"])
		if "pitch_deg" in player:
			player.pitch_deg = rad2deg(player.pitch)
	if "camera_rig" in player and is_instance_valid(player.camera_rig) and "yaw" in player and "pitch" in player:
		player.camera_rig.transform.basis = Basis(Vector3.UP, player.yaw) * Basis(Vector3.RIGHT, player.pitch)
		player.camera_rig.force_update_transform()
	if state_data.has("camera_restore_spring_length"):
		var restore_len := float(state_data["camera_restore_spring_length"])
		if restore_len > 0.0:
			player.set_meta("airlock_restore_spring_length", restore_len)
	if state_data.has("camera_arm_spring_length"):
		var arm_len := float(state_data["camera_arm_spring_length"])
		var arm = player.get("_cached_spring_arm") if "_cached_spring_arm" in player else null
		if is_instance_valid(arm):
			if "spring_length" in arm:
				arm.spring_length = arm_len
			if "current_length" in arm:
				arm.current_length = arm_len
		if "current_spring_length" in player:
			player.current_spring_length = arm_len
		if "base_spring_length_3d" in player:
			player.base_spring_length_3d = arm_len
		return
	if player.has_method("snap_camera_to_current_state"):
		player.snap_camera_to_current_state()

func _snap_transition_visual(player: Node, target_transform: Transform) -> void:
	if not is_instance_valid(player):
		return
	var animator = player.get("animator") if "animator" in player else null
	if is_instance_valid(animator) and animator.has_method("snap_visual_to_direction"):
		animator.snap_visual_to_direction(-target_transform.basis.z)

func _capture_player_state_for_transition() -> void:
	_captured_player_state.clear()
	if not bool(_transition_params.get("preserve_player_state", true)):
		return

	var session = get_node_or_null("/root/SessionManager")
	if session and session.has_method("capture_scene_transition_state"):
		var state = session.capture_scene_transition_state()
		if typeof(state) == TYPE_DICTIONARY and state.has("player_snapshot") and typeof(state["player_snapshot"]) == TYPE_DICTIONARY:
			_captured_player_state = state["player_snapshot"].duplicate(true)
			return

	var player = _find_current_player()
	if player and player.has_method("get_full_snapshot"):
		var snapshot = player.get_full_snapshot()
		if typeof(snapshot) == TYPE_DICTIONARY:
			_captured_player_state = snapshot.duplicate(true)

func _disable_input_for_transition() -> void:
	_input_restore_state = {
		"valid": false,
		"hardware_input_enabled": true,
		"is_replay_mode": false
	}

	if _transition_params.has("input_restore_state") and typeof(_transition_params["input_restore_state"]) == TYPE_DICTIONARY:
		var supplied_state: Dictionary = _transition_params["input_restore_state"]
		_input_restore_state["valid"] = bool(supplied_state.get("valid", false))
		_input_restore_state["hardware_input_enabled"] = bool(supplied_state.get("hardware_input_enabled", true))
		_input_restore_state["is_replay_mode"] = bool(supplied_state.get("is_replay_mode", false))

	var player = _find_current_player()
	if not is_instance_valid(player):
		return

	if not bool(_input_restore_state.get("valid", false)):
		_input_restore_state["valid"] = true
		if "is_replay_mode" in player:
			_input_restore_state["is_replay_mode"] = bool(player.is_replay_mode)
		if "input_provider" in player and is_instance_valid(player.input_provider):
			_input_restore_state["hardware_input_enabled"] = bool(player.input_provider.hardware_input_enabled)

	if "input_provider" in player and is_instance_valid(player.input_provider):
		player.input_provider.hardware_input_enabled = false

func _restore_input_after_transition() -> void:
	var player = _find_current_player()
	if not is_instance_valid(player):
		return

	var restore_replay_mode := false
	var restore_hardware := true
	if bool(_input_restore_state.get("valid", false)):
		restore_replay_mode = bool(_input_restore_state.get("is_replay_mode", false))
		restore_hardware = bool(_input_restore_state.get("hardware_input_enabled", true))

	if "is_replay_mode" in player:
		player.is_replay_mode = restore_replay_mode
	if "input_provider" in player and is_instance_valid(player.input_provider):
		player.input_provider.hardware_input_enabled = restore_hardware

func _find_current_player() -> Node:
	var session = get_node_or_null("/root/SessionManager")
	if session and is_instance_valid(session.player):
		return session.player

	var tree = get_tree()
	if not tree:
		return null
	var scene_root = tree.current_scene
	if not is_instance_valid(scene_root):
		return null
	return _find_player_in_scene(scene_root)

func _fade_audio_out(duration: float) -> void:
	var audio = get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("fade_out_current_bgm"):
		audio.fade_out_current_bgm(max(0.0, duration))

func _fade_audio_in(duration: float) -> void:
	var audio = get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("refresh_bgm_from_zones"):
		audio.refresh_bgm_from_zones(max(0.0, duration))

func _finalize_failed_transition(reason: String) -> void:
	printerr("[SceneManager] Transition failed: ", reason)
	emit_signal("transition_failed", _next_scene_path, reason)

	var transition_layer = _get_transition_layer()
	var transition_mode := _get_transition_mode()
	var show_loading := _should_show_loading(transition_mode)
	if transition_layer:
		if _should_use_fade(transition_mode) and transition_layer.has_method("play"):
			transition_layer.play("fade_in", {
				"duration": float(_transition_params.get("fade_in", default_fade_in))
			})
		elif show_loading and transition_layer.has_method("hide_loading"):
			transition_layer.hide_loading()

	_restore_input_after_transition()
	_reset_runtime_state()

func _reset_runtime_state() -> void:
	_loader = null
	_loaded_scene = null
	_load_error = ""
	_is_loading = false
	_is_transitioning = false
	_transition_started_ms = 0
	_loader_last_progress_ms = 0
	_loader_last_stage = -1
	_next_scene_path = ""
	_transition_params.clear()
	_captured_player_state.clear()
	_input_restore_state.clear()

func _get_effective_poll_budget_ms() -> int:
	return int(poll_budget_ms)

func _get_effective_transition_timeout_ms() -> int:
	var timeout_s := max(3.0, transition_timeout_s)
	return int(timeout_s * 1000.0)

func _get_transition_layer() -> Node:
	return get_node_or_null("/root/TransitionLayer")

func _get_transition_mode() -> String:
	var mode := String(_transition_params.get("transition", "fade")).strip_edges().to_lower()
	match mode:
		"fade", "loading", "none":
			return mode
		"instant":
			return "none"
		_:
			return "fade"

func _should_use_fade(mode: String) -> bool:
	return mode != "none"

func _should_show_loading(mode: String) -> bool:
	if _transition_params.has("show_loading"):
		return bool(_transition_params.get("show_loading", false))
	return mode == "loading"

func _check_transition_timeout() -> void:
	if not _is_transitioning:
		return
	var timeout_ms = _get_effective_transition_timeout_ms()
	if _transition_started_ms <= 0:
		_transition_started_ms = OS.get_ticks_msec()
		return
	var reference_ms := _loader_last_progress_ms if _loader_last_progress_ms > 0 else _transition_started_ms
	if OS.get_ticks_msec() - reference_ms < timeout_ms:
		return
	_force_reset_stuck_transition("timeout")

func _force_reset_stuck_transition(reason: String) -> void:
	printerr("[SceneManager] Transition watchdog reset: ", reason, " path=", _next_scene_path)
	_last_transition_abort_reason = "watchdog_" + reason
	emit_signal("transition_failed", _next_scene_path, "watchdog_" + reason)
	var transition_layer = _get_transition_layer()
	if transition_layer:
		if transition_layer.has_method("hide_loading"):
			transition_layer.hide_loading()
		if transition_layer.has_method("play"):
			transition_layer.play("fade_in", {"duration": 0.0})
	_restore_input_after_transition()
	_reset_runtime_state()

func _drain_pending_transition() -> void:
	if _is_transitioning:
		return
	if _pending_scene_path == "":
		return
	var next_path = _pending_scene_path
	var next_params = _pending_transition_params.duplicate(true)
	_pending_scene_path = ""
	_pending_transition_params.clear()
	goto_scene(next_path, next_params)

func _run_boot_fade_in() -> void:
	if _boot_fade_consumed or not boot_fade_in_enabled:
		return
	_boot_fade_consumed = true
	if _is_transitioning:
		return
	var tree := get_tree()
	if not tree:
		return

	var transition_layer = _get_transition_layer()
	if not transition_layer or not transition_layer.has_method("play"):
		return

	transition_layer.play("fade_out", {
		"duration": 0.0,
		"show_loading": false
	})

	for _i in range(max(0, boot_fade_in_wait_frames)):
		yield(tree, "idle_frame")

	var max_wait_frames := 90
	while max_wait_frames > 0 and not is_instance_valid(tree.current_scene):
		yield(tree, "idle_frame")
		max_wait_frames -= 1

	if _is_transitioning:
		return

	if not is_instance_valid(tree.current_scene):
		transition_layer.play("fade_in", {"duration": 0.0})
		return

	yield(tree, "idle_frame")
	transition_layer.play("fade_in", {"duration": max(0.0, boot_fade_in_duration)})
