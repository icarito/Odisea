extends Node

class_name AnnaInterface

# Configuration
const PROTOCOL_VERSION = "anna.v1"
const SENSOR_RAY_COUNT = 8
const SENSOR_RANGE = 20.0
const PROXIMITY_RADIUS = 10.0
const BUFFER_MAX_ENTRIES = 50
const MAX_LOOK_DELTA = 250.0
const MAX_ONCE_IDS = 256

export(bool) var allow_human_heuristic_override := true
export(NodePath) var ai_controller_path := NodePath("")
export(bool) var allow_command_injection := true
export(bool) var allow_oys_integration := true
export(bool) var allow_olcs_integration := true
export(NodePath) var olcs_manager_path := NodePath("")
export(int) var olcs_snapshot_limit := 32

# State
var _raycast_root: Spatial
var _rays := []
var _accepted_once_ids := {}

# RL PoC State
var _last_dist := -1.0
var _initial_player_transform: Transform
var _initial_target_transform: Transform
var _has_stored_initial_transforms := false

func _ready():
	_setup_sensors()

func _setup_sensors():
	if is_instance_valid(_raycast_root):
		return

	_raycast_root = Spatial.new()
	_raycast_root.name = "AnnaSensors"
	add_child(_raycast_root)

	for i in range(SENSOR_RAY_COUNT):
		var ray = RayCast.new()
		ray.enabled = true
		ray.cast_to = Vector3(0, 0, -SENSOR_RANGE)
		ray.rotation_degrees.y = (360.0 / SENSOR_RAY_COUNT) * i
		_raycast_root.add_child(ray)
		_rays.append(ray)

func get_observation() -> Dictionary:
	var target_data = _get_target_data()
	var raycasts = _get_collisions()
	var rewards_and_done = _calculate_rewards_and_done(raycasts, target_data)

	return {
		"proximity": _get_proximity(),
		"buffer": _get_buffer(),
		"metrics": _get_metrics(),
		"raycasts": raycasts,
		"target": target_data,
		"reward": rewards_and_done.reward,
		"done": rewards_and_done.done,
		"olcs": _get_olcs_observation(),
		"anna": _get_anna_metadata()
	}

func _get_proximity() -> Array:
	var player = _get_player()
	if not is_instance_valid(player):
		return []
	if not player is Spatial:
		return []

	var nearby = []
	var candidates = get_tree().get_nodes_in_group("interactable")
	var p_pos = player.global_transform.origin

	for node in candidates:
		if not is_instance_valid(node): continue
		if not node is Spatial: continue
		var dist = p_pos.distance_to(node.global_transform.origin)
		if dist < PROXIMITY_RADIUS:
			var node_type = String(node.filename)
			if node_type == "":
				node_type = node.get_class()
			nearby.append({
				"name": node.name,
				"type": node_type,
				"pos": [node.global_transform.origin.x, node.global_transform.origin.y, node.global_transform.origin.z],
				"dist": dist
			})
	return nearby

func _get_buffer() -> Array:
	if not is_inside_tree():
		return []
	var console = get_tree().root.get_node_or_null("OYS_Console")
	if console and console.has_method("get_logs"):
		var logs = console.get_logs()
		if typeof(logs) != TYPE_ARRAY:
			return []
		if logs.size() <= BUFFER_MAX_ENTRIES:
			return logs

		var trimmed := []
		var start = max(0, logs.size() - BUFFER_MAX_ENTRIES)
		for i in range(start, logs.size()):
			trimmed.append(logs[i])
		return trimmed
	return []

func _get_metrics() -> Dictionary:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"mem_static": OS.get_static_memory_usage(),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT)
	}

func _get_collisions() -> Array:
	if not is_instance_valid(_raycast_root):
		_setup_sensors()

	var player = _get_player()
	if not is_instance_valid(player):
		# Return max range if no player
		var fallback = []
		for i in range(SENSOR_RAY_COUNT): fallback.append(SENSOR_RANGE)
		return fallback
	if not player is Spatial:
		var fallback = []
		for i in range(SENSOR_RAY_COUNT): fallback.append(SENSOR_RANGE)
		return fallback

	# Teleport sensor to player eye level
	# Note: If this node is not in the tree, rays won't work.
	# Since AnnaInterface is likely a child of AnnaBridge which is in the tree, this works.
	# We use global coordinates to position the sensor ring.
	_raycast_root.global_transform.origin = player.global_transform.origin + Vector3(0, 1.0, 0)

	# Force update to get immediate results
	for ray in _rays:
		ray.clear_exceptions()
		ray.add_exception(player)
		ray.force_raycast_update()

	var data = []
	for ray in _rays:
		if ray.is_colliding():
			var col_point = ray.get_collision_point()
			var dist = ray.global_transform.origin.distance_to(col_point)
			data.append(dist)
		else:
			data.append(SENSOR_RANGE)
	return data

func apply_action(action: Dictionary):
	# print("[AnnaInterface] Applying action: ", action.keys())
	var sm = get_node_or_null("/root/SessionManager")
	if not sm: return

	# Movement
	var has_input = action.has("move") or action.has("look") or action.has("jump") or action.has("interact") or action.has("sprint") or action.has("crouch")
	if has_input:
		var move_data = action.get("move", [0.0, 0.0]) # [x, y]
		var jump = action.get("jump", false)
		var interact = action.get("interact", false)
		var sprint = action.get("sprint", false)
		var crouch = action.get("crouch", false)

		# Ensure types
		var vx = 0.0
		var vy = 0.0
		if typeof(move_data) == TYPE_ARRAY and move_data.size() >= 2:
			vx = float(move_data[0])
			vy = float(move_data[1])
		vx = clamp(vx, -1.0, 1.0)
		vy = clamp(vy, -1.0, 1.0)

		# Look / Rotation
		var look_data = action.get("look", [0.0, 0.0])
		var lx = 0.0
		var ly = 0.0
		if typeof(look_data) == TYPE_ARRAY and look_data.size() >= 2:
			lx = float(look_data[0])
			ly = float(look_data[1])
		lx = clamp(lx, -MAX_LOOK_DELTA, MAX_LOOK_DELTA)
		ly = clamp(ly, -MAX_LOOK_DELTA, MAX_LOOK_DELTA)

		var move_vec = Vector2(vx, vy)
		if _is_human_heuristic_active():
			var human_move = _read_human_move_axis()
			if human_move.length_squared() > 0.0001:
				move_vec = human_move

		var input_dict = {
			"move_vec": move_vec,
			"jump": bool(jump),
			"interact": bool(interact),
			"sprint": bool(sprint),
			"crouch": bool(crouch),
			"mouse_delta": Vector2(lx, ly),
			"zoom_delta": 0.0,
			"fov_override": -1.0
		}

		# Override SessionManager input if recording, otherwise inject directly to player
		if sm.is_recording:
			sm._oys_input_override = input_dict
		else:
			var player = _get_player()
			if is_instance_valid(player) and player.has_method("inject_input"):
				player.inject_input(input_dict)

	# Command Injection
	if action.has("command") and allow_command_injection:
		var cmd = str(action["command"])

		# Intercept RESET_EPISODE
		if cmd == "RESET_EPISODE":
			_reset_episode()
		else:
			var console = _resolve_console()
			if console and console.has_method("enqueue_command"):
				console.enqueue_command(cmd)

	# Structured OYS integration for ANNA clients
	if action.has("oys"):
		_apply_oys_action(action["oys"])

	# OLCS/OCLS alias accepted to avoid client-side naming mismatch
	if action.has("olcs"):
		_apply_olcs_action(action["olcs"])
	elif action.has("ocls"):
		_apply_olcs_action(action["ocls"])

func _get_player() -> Node:
	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.player:
		return sm.player
	return null

func _get_anna_metadata() -> Dictionary:
	var sm = get_node_or_null("/root/SessionManager")
	return {
		"protocol": PROTOCOL_VERSION,
		"physics_frame": Engine.get_physics_frames(),
		"recording": bool(sm and sm.is_recording),
		"heuristic_human": _is_human_heuristic_active(),
		"integrations": {
			"oys": allow_oys_integration,
			"olcs": allow_olcs_integration
		}
	}

func _resolve_ai_controller() -> Node:
	if not is_inside_tree():
		return null

	if String(ai_controller_path) != "":
		var configured = get_node_or_null(ai_controller_path)
		if configured:
			return configured

	var current_scene = get_tree().current_scene
	if is_instance_valid(current_scene):
		var named = current_scene.get_node_or_null("AIController")
		if named:
			return named

	var group_nodes = get_tree().get_nodes_in_group("ai_controller")
	for node in group_nodes:
		if is_instance_valid(node):
			return node
	return null

func _is_human_heuristic_active() -> bool:
	if not allow_human_heuristic_override:
		return false
	var controller = _resolve_ai_controller()
	if controller == null:
		return false
	var heuristic = str(controller.get("heuristic")).to_lower()
	return heuristic == "human"

func _read_human_move_axis() -> Vector2:
	var human_move = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	)
	human_move.x = clamp(human_move.x, -1.0, 1.0)
	human_move.y = clamp(human_move.y, -1.0, 1.0)
	return human_move

func _resolve_console() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("OYS_Console")

func _should_process_once(payload: Dictionary, domain: String) -> bool:
	if not payload.has("once_id"):
		return true
	var key = "%s:%s" % [domain, str(payload["once_id"])]
	if _accepted_once_ids.has(key):
		return false
	if _accepted_once_ids.size() >= MAX_ONCE_IDS:
		_accepted_once_ids.clear()
	_accepted_once_ids[key] = true
	return true

func _apply_oys_action(payload) -> void:
	if not allow_oys_integration:
		return
	var console = _resolve_console()
	if console == null or not console.has_method("enqueue_command"):
		return

	if typeof(payload) == TYPE_STRING:
		console.enqueue_command(str(payload))
		return
	if typeof(payload) != TYPE_DICTIONARY:
		return
	if not _should_process_once(payload, "oys"):
		return

	if payload.has("command"):
		console.enqueue_command(str(payload["command"]))

	if payload.has("run"):
		var run_path = str(payload["run"]).strip_edges()
		if run_path != "":
			console.enqueue_command("run %s" % run_path)

	if payload.has("exec"):
		var cfg_path = str(payload["exec"]).strip_edges()
		if cfg_path != "":
			console.enqueue_command("exec %s" % cfg_path)

func _resolve_olcs_manager(preferred = "") -> Node:
	if not is_inside_tree():
		return null

	if String(olcs_manager_path) != "":
		var configured = get_node_or_null(olcs_manager_path)
		if configured:
			return configured

	var preferred_name = str(preferred).strip_edges()
	if preferred_name != "":
		var from_scene = null
		var current_scene = get_tree().current_scene
		if is_instance_valid(current_scene):
			from_scene = current_scene.get_node_or_null(preferred_name)
		if from_scene:
			return from_scene
		var from_root = get_tree().root.get_node_or_null(preferred_name)
		if from_root:
			return from_root

	var scene = get_tree().current_scene
	if is_instance_valid(scene):
		var named = scene.get_node_or_null("LogicCircuitManager")
		if named:
			return named

	var managers = get_tree().get_nodes_in_group("olcs_manager")
	for node in managers:
		if is_instance_valid(node):
			return node

	return null

func _get_olcs_observation() -> Dictionary:
	if not allow_olcs_integration:
		return {"available": false}

	var manager = _resolve_olcs_manager()
	if manager == null:
		return {"available": false}

	if manager.has_method("anna_get_snapshot"):
		var snapshot = manager.call("anna_get_snapshot", olcs_snapshot_limit)
		if typeof(snapshot) == TYPE_DICTIONARY:
			if not snapshot.has("available"):
				snapshot["available"] = true
			return snapshot

	return {
		"available": true,
		"manager": manager.name
	}

func _apply_olcs_action(payload) -> void:
	if not allow_olcs_integration:
		return
	if typeof(payload) != TYPE_DICTIONARY:
		return
	if not _should_process_once(payload, "olcs"):
		return

	var manager = _resolve_olcs_manager(payload.get("manager", ""))
	if manager == null:
		return

	if payload.has("rebuild_cables") and bool(payload["rebuild_cables"]):
		if manager.has_method("anna_rebuild_cables"):
			manager.call("anna_rebuild_cables")
		elif manager.has_method("generate_cables"):
			manager.call("generate_cables")

	if payload.has("inject"):
		var inject = payload["inject"]
		if typeof(inject) == TYPE_DICTIONARY and manager.has_method("anna_inject_input"):
			var target = str(inject.get("target", ""))
			var input_id = str(inject.get("input", ""))
			var value = bool(inject.get("value", false))
			if target != "" and input_id != "":
				manager.call("anna_inject_input", target, input_id, value)

	if payload.has("set_output"):
		var set_output = payload["set_output"]
		if typeof(set_output) == TYPE_DICTIONARY and manager.has_method("anna_set_output"):
			var source = str(set_output.get("source", ""))
			var value = bool(set_output.get("value", false))
			if source != "":
				manager.call("anna_set_output", source, value)

# --- RL PoC Helpers ---

func _get_target() -> Spatial:
	var nodes = get_tree().get_nodes_in_group("anna_target")
	if nodes.size() > 0 and nodes[0] is Spatial:
		return nodes[0]
	return null

func _get_target_data() -> Dictionary:
	var player = _get_player()
	var target = _get_target()

	if not is_instance_valid(player) or not is_instance_valid(target) or not (player is Spatial):
		return {"distance": 100.0, "angle": 0.0}

	var p_pos = player.global_transform.origin
	var t_pos = target.global_transform.origin
	var dist = p_pos.distance_to(t_pos)

	# Angle relative to forward (-Z)
	var forward = -player.global_transform.basis.z
	var to_target = (t_pos - p_pos).normalized()

	# Project to 2D (XZ plane) for navigation angle
	var forward_2d = Vector2(forward.x, forward.z).normalized()
	var to_target_2d = Vector2(to_target.x, to_target.z).normalized()

	var angle = forward_2d.angle_to(to_target_2d) / PI # Normalize to -1.0 to 1.0

	return {"distance": dist, "angle": angle}

func _calculate_rewards_and_done(raycasts: Array, target_data: Dictionary) -> Dictionary:
	var reward = -0.01 # Time penalty
	var done = false

	# 1. Collision Check
	var min_ray = 999.0
	for r in raycasts:
		if r < min_ray: min_ray = r

	if min_ray < 0.8: # Collision threshold (slightly higher than 0 to be safe)
		reward -= 5.0
		done = true

	# 2. Target Check
	var dist = target_data.distance
	if dist < 2.0: # Reached target
		reward += 10.0
		done = true

	# 3. Progress Reward
	if _last_dist >= 0.0:
		if dist < _last_dist:
			reward += 0.1

	_last_dist = dist

	return {"reward": reward, "done": done}

func _reset_episode():
	var player = _get_player()
	var target = _get_target()

	# Store initial transforms once
	if not _has_stored_initial_transforms:
		if is_instance_valid(player) and player is Spatial:
			_initial_player_transform = player.global_transform
		if is_instance_valid(target):
			_initial_target_transform = target.global_transform
		_has_stored_initial_transforms = true

	if is_instance_valid(player) and player is Spatial:
		if _has_stored_initial_transforms:
			player.global_transform = _initial_player_transform
		else:
			player.global_transform.origin = Vector3(0, 1, 0)

		player.rotation = Vector3.ZERO
		player.set("velocity", Vector3.ZERO)
		player.set("external_velocity", Vector3.ZERO)

	if is_instance_valid(target) and _has_stored_initial_transforms:
		target.global_transform = _initial_target_transform

	_last_dist = -1.0
