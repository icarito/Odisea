extends Node

class_name AnnaInterface

# Configuration
const PROTOCOL_VERSION = "anna.v1"
const SENSOR_RAY_COUNT = 32 # Legacy/Visual
const RL_SENSOR_RAY_COUNT = 8 # RL PoC
const SENSOR_RANGE = 20.0
const PROXIMITY_RADIUS = 10.0
const BUFFER_MAX_ENTRIES = 50
const MAX_LOOK_DELTA = 250.0
const MAX_ONCE_IDS = 256

# RL Config
const RL_TARGET_GROUP = "anna_target"
const RL_MAX_VELOCITY = 20.0
const RL_REWARD_SUCCESS = 100.0
const RL_REWARD_FAILURE = -100.0
const RL_REWARD_TIME_PENALTY = -0.1
const RL_PROGRESS_SCALE = 10.0
const RL_SUCCESS_DIST = 1.5
const RL_SPEED_REWARD_SCALE = 0.03 # Favors staying fast on ground.
const RL_SPRINT_REWARD_SCALE = 0.02 # Extra reward when explicit sprint action is used.
const RL_JUMP_ACTION_PENALTY = 0.05 # Discourage jump-spam.
const RL_AIRBORNE_PENALTY = 0.015 # Grounded running is generally faster/more stable.
const RL_COLLISION_PENALTY_THRESHOLD = 0.6 # If ray < 0.6m ~ collision
const RL_FLOOR_NORMAL_Y_THRESHOLD = 0.6 # Upward-facing collisions are treated as floor/support.
const RL_HAZARD_CONTACT_GRACE_FRAMES = 8 # Allow brief wall brushes before failing.
const RL_FALL_DISTANCE = 3.5 # Episode fails if player falls this much below episode start height.

export(bool) var allow_human_heuristic_override := true
export(NodePath) var ai_controller_path := NodePath("")
export(bool) var allow_command_injection := true
export(bool) var allow_oys_integration := true
export(bool) var allow_olcs_integration := true
export(NodePath) var olcs_manager_path := NodePath("")
export(int) var olcs_snapshot_limit := 32

# State
var _raycast_root: Spatial
var _rl_raycast_root: Spatial
var _rays := []
var _rl_rays := []
var _accepted_once_ids := {}

# RL State
var _last_dist_to_target := -1.0
var _episode_start_time := 0
var _episode_start_height := 2.0
var _hazard_contact_frames := 0
var _killzone_triggered := false
var _last_action_jump := false
var _last_action_sprint := false

func _ready():
	_setup_sensors()
	_setup_rl_sensors()
	_bind_killzones()
	var tree = get_tree()
	if tree and not tree.is_connected("node_added", self, "_on_tree_node_added"):
		tree.connect("node_added", self, "_on_tree_node_added")

func _exit_tree():
	var tree = get_tree()
	if tree and tree.is_connected("node_added", self, "_on_tree_node_added"):
		tree.disconnect("node_added", self, "_on_tree_node_added")

func _on_tree_node_added(node: Node) -> void:
	_try_bind_killzone(node)

func _bind_killzones() -> void:
	if not is_inside_tree():
		return
	var zones = get_tree().get_nodes_in_group("KillZoneV2")
	for zone in zones:
		_try_bind_killzone(zone)

func _try_bind_killzone(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if not node.is_in_group("KillZoneV2"):
		return
	if not node.has_signal("player_killed"):
		return
	if not node.is_connected("player_killed", self, "_on_killzone_player_killed"):
		node.connect("player_killed", self, "_on_killzone_player_killed")

func _on_killzone_player_killed() -> void:
	_killzone_triggered = true

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

func _setup_rl_sensors():
	if is_instance_valid(_rl_raycast_root):
		return

	_rl_raycast_root = Spatial.new()
	_rl_raycast_root.name = "AnnaRLSensors"
	add_child(_rl_raycast_root)

	for i in range(RL_SENSOR_RAY_COUNT):
		var ray = RayCast.new()
		ray.enabled = true
		ray.cast_to = Vector3(0, 0, -SENSOR_RANGE)
		# 8 rays distributed around 360 degrees
		ray.rotation_degrees.y = (360.0 / float(RL_SENSOR_RAY_COUNT)) * i
		_rl_raycast_root.add_child(ray)
		_rl_rays.append(ray)

# --- STANDARD API ---

func get_observation() -> Dictionary:
	return {
		"proximity": _get_proximity(),
		"buffer": _get_buffer(),
		"metrics": _get_metrics(),
		"collisions": _get_collisions(),
		"olcs": _get_olcs_observation(),
		"anna": _get_anna_metadata()
	}

# --- RL API ---

func get_rl_observation() -> Dictionary:
	var player = _get_player()
	var obs_vector = []
	var reward = 0.0
	var done = false
	var dist_to_target = 0.0
	var angle_to_target = 0.0

	if not is_instance_valid(player) or not player is Spatial:
		# Fallback/Fail state
		for i in range(12): obs_vector.append(0.0)
		return {"obs": obs_vector, "reward": 0.0, "done": true}

	# 1. Update Sensors
	# Move sensors to player position
	_rl_raycast_root.global_transform.origin = player.global_transform.origin + Vector3(0, 1.0, 0)
	# Align sensors with player rotation (so Ray 0 is always "Forward")
	_rl_raycast_root.global_transform.basis = player.global_transform.basis

	# Rays 0-7
	var min_ray_dist = SENSOR_RANGE
	for ray in _rl_rays:
		ray.clear_exceptions()
		ray.add_exception(player)
		ray.force_raycast_update()
		var d = SENSOR_RANGE
		if ray.is_colliding():
			d = ray.global_transform.origin.distance_to(ray.get_collision_point())

		if d < min_ray_dist: min_ray_dist = d

		# Normalize: 0.0 (Collision) to 1.0 (Clear)
		obs_vector.append(clamp(d / SENSOR_RANGE, 0.0, 1.0))

	# Target Info
	var target = _get_rl_target()
	if target:
		dist_to_target = player.global_transform.origin.distance_to(target.global_transform.origin)

		# Angle
		var to_target = (target.global_transform.origin - player.global_transform.origin)
		to_target.y = 0
		to_target = to_target.normalized()
		var forward = -player.global_transform.basis.z
		forward.y = 0
		forward = forward.normalized()

		var angle = forward.angle_to(to_target) # Returns 0 to PI
		# Determine sign
		if forward.cross(to_target).y < 0:
			angle = -angle

		angle_to_target = angle / PI # Normalize -1 to 1
	else:
		dist_to_target = SENSOR_RANGE

	# Sensor 8: Distancia normalizada
	obs_vector.append(clamp(dist_to_target / 50.0, 0.0, 1.0))

	# Sensor 9: Angulo relativo
	obs_vector.append(angle_to_target)

	# Sensor 10, 11: Velocity (normalized)
	var vel = Vector3.ZERO
	if "velocity" in player:
		vel = player.velocity

	# Normalize relative to player orientation?
	var local_vel = player.global_transform.basis.xform_inv(vel)
	obs_vector.append(clamp(local_vel.x / RL_MAX_VELOCITY, -1.0, 1.0)) # Right/Left
	obs_vector.append(clamp(local_vel.z / RL_MAX_VELOCITY, -1.0, 1.0)) # Backward/Forward (-Z is forward)

	# --- REWARD CALCULATION ---

	# 1. Time Penalty
	reward += RL_REWARD_TIME_PENALTY

	# 1b. Reward speed (prefer fast locomotion over stationary/jump spam)
	var horizontal_speed = Vector2(local_vel.x, local_vel.z).length()
	reward += horizontal_speed * RL_SPEED_REWARD_SCALE
	if _last_action_sprint and horizontal_speed > 0.1:
		reward += horizontal_speed * RL_SPRINT_REWARD_SCALE
	if _last_action_jump:
		reward -= RL_JUMP_ACTION_PENALTY
	if player.has_method("is_on_floor") and not player.is_on_floor():
		reward -= RL_AIRBORNE_PENALTY

	# 2. Progress
	if _last_dist_to_target >= 0.0:
		var diff = _last_dist_to_target - dist_to_target
		reward += diff * RL_PROGRESS_SCALE
	_last_dist_to_target = dist_to_target

	# 3. Success
	if dist_to_target < RL_SUCCESS_DIST:
		reward += RL_REWARD_SUCCESS
		done = true

	# 4. Failure (KillZone / Fall / Prolonged hazard contact)
	if not done and _killzone_triggered:
		reward += RL_REWARD_FAILURE
		done = true

	if not done and player.global_transform.origin.y < (_episode_start_height - RL_FALL_DISTANCE):
		reward += RL_REWARD_FAILURE
		done = true

	if not done:
		var hazard_contact := false
		if min_ray_dist < RL_COLLISION_PENALTY_THRESHOLD:
			hazard_contact = true

		if player.has_method("get_slide_count"):
			for i in range(player.get_slide_count()):
				var col = player.get_slide_collision(i)
				if col == null or not is_instance_valid(col.collider):
					continue
				if col.collider.is_in_group("anna_target"):
					continue
				if col.collider is StaticBody:
					# Ground contact is expected and should not end the episode.
					if col.normal.y >= RL_FLOOR_NORMAL_Y_THRESHOLD:
						continue
					# Ceiling contact should not end the episode either.
					if col.normal.y <= -RL_FLOOR_NORMAL_Y_THRESHOLD:
						continue
					hazard_contact = true
					break

		if hazard_contact:
			_hazard_contact_frames += 1
		else:
			_hazard_contact_frames = 0

		if _hazard_contact_frames >= RL_HAZARD_CONTACT_GRACE_FRAMES:
			reward += RL_REWARD_FAILURE
			done = true

	return {
		"obs": obs_vector,
		"reward": reward,
		"done": done
	}

func reset_simulation() -> void:
	var player = _get_player()
	if player and player.has_method("teleport_to"):
		var t = Transform()
		t.origin = Vector3(0, 2, 0) # Start pos
		# Random rotation?
		var rand_yaw = rand_range(-PI, PI)
		t.basis = Basis(Vector3.UP, rand_yaw)
		player.teleport_to(t)
		_episode_start_height = t.origin.y

	# Reset Target
	var target = _get_rl_target()
	if target:
		var tx = rand_range(-20, 20)
		var tz = rand_range(-20, 20)
		while Vector2(tx, tz).length() < 5.0:
			tx = rand_range(-20, 20)
			tz = rand_range(-20, 20)
		target.transform.origin = Vector3(tx, 1.0, tz)

	# Reset internal state
	_last_dist_to_target = -1.0
	_hazard_contact_frames = 0
	_killzone_triggered = false
	_last_action_jump = false
	_last_action_sprint = false
	# Force initial distance update
	if target and player:
		_last_dist_to_target = player.global_transform.origin.distance_to(target.global_transform.origin)

func apply_rl_action(action_idx: int) -> void:
	# Action Space:
	# 0=Idle, 1=Forward, 2=Back, 3=Left, 4=Right, 5=Jump,
	# 6=SprintForward, 7=SprintBack, 8=SprintLeft, 9=SprintRight
	var move_vec = Vector2.ZERO
	var jump_pressed := false
	var sprint_pressed := false

	match action_idx:
		1: move_vec.y = 1.0  # Forward
		2: move_vec.y = -1.0 # Backward
		3: move_vec.x = -1.0 # Left
		4: move_vec.x = 1.0  # Right
		5: jump_pressed = true
		6:
			move_vec.y = 1.0
			sprint_pressed = true
		7:
			move_vec.y = -1.0
			sprint_pressed = true
		8:
			move_vec.x = -1.0
			sprint_pressed = true
		9:
			move_vec.x = 1.0
			sprint_pressed = true

	_last_action_jump = jump_pressed
	_last_action_sprint = sprint_pressed

	var input_dict = {
		"move_vec": move_vec,
		"jump": jump_pressed,
		"interact": false,
		"sprint": sprint_pressed,
		"crouch": false,
		"mouse_delta": Vector2.ZERO,
		"zoom_delta": 0.0,
		"fov_override": -1.0
	}

	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.is_recording:
		sm._oys_input_override = input_dict
	else:
		var player = _get_player()
		if player and player.has_method("inject_input"):
			player.inject_input(input_dict)


func _get_rl_target() -> Spatial:
	var targets = get_tree().get_nodes_in_group(RL_TARGET_GROUP)
	if targets.size() > 0:
		var t = targets[0]
		if t is Spatial: return t
	return null

# --- EXISTING HELPERS ---

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
	# If no SessionManager, try direct injection (for minimal test scenes)

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

		if sm and sm.is_recording:
			sm._oys_input_override = input_dict
		else:
			var player = _get_player()
			if is_instance_valid(player) and player.has_method("inject_input"):
				player.inject_input(input_dict)

	# Command Injection
	if action.has("command") and allow_command_injection:
		var cmd = str(action["command"])
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
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		return players[0]
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
