extends Node

class_name AnnaInterface

# Configuration
const SENSOR_RAY_COUNT = 32
const SENSOR_RANGE = 20.0
const PROXIMITY_RADIUS = 10.0

# State
var _raycast_root: Spatial
var _rays := []

func _ready():
	_setup_sensors()

func _setup_sensors():
	_raycast_root = Spatial.new()
	_raycast_root.name = "AnnaSensors"
	# We don't add_child(_raycast_root) here because it needs to be in the scene tree
	# but independent or attached to player. We'll handle attachment in get_collisions.
	add_child(_raycast_root)

	for i in range(SENSOR_RAY_COUNT):
		var ray = RayCast.new()
		ray.enabled = true
		ray.cast_to = Vector3(0, 0, -SENSOR_RANGE)
		ray.rotation_degrees.y = (360.0 / SENSOR_RAY_COUNT) * i
		_raycast_root.add_child(ray)
		_rays.append(ray)

func get_observation() -> Dictionary:
	return {
		"proximity": _get_proximity(),
		"buffer": _get_buffer(),
		"metrics": _get_metrics(),
		"collisions": _get_collisions()
	}

func _get_proximity() -> Array:
	var player = _get_player()
	if not is_instance_valid(player): return []

	var nearby = []
	var candidates = get_tree().get_nodes_in_group("interactable")
	var p_pos = player.global_transform.origin

	for node in candidates:
		if not is_instance_valid(node): continue
		if not node is Spatial: continue
		var dist = p_pos.distance_to(node.global_transform.origin)
		if dist < PROXIMITY_RADIUS:
			nearby.append({
				"name": node.name,
				"type": node.filename if "filename" in node else "Unknown",
				"pos": [node.global_transform.origin.x, node.global_transform.origin.y, node.global_transform.origin.z],
				"dist": dist
			})
	return nearby

func _get_buffer() -> Array:
	var console = get_tree().root.get_node_or_null("OYS_Console")
	if console and console.has_method("get_logs"):
		return console.get_logs()
	return []

func _get_metrics() -> Dictionary:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"mem_static": OS.get_static_memory_usage(),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT)
	}

func _get_collisions() -> Array:
	var player = _get_player()
	if not is_instance_valid(player):
		# Return max range if no player
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
	if action.has("move"):
		var move_data = action["move"] # [x, y]
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

		var input_dict = {
			"move_vec": Vector2(vx, vy),
			"jump": bool(jump),
			"interact": bool(interact),
			"sprint": bool(sprint),
			"crouch": bool(crouch),
			"mouse_delta": Vector2.ZERO,
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
	if action.has("command"):
		var cmd = str(action["command"])
		var console = get_tree().root.get_node_or_null("OYS_Console")
		if console and console.has_method("enqueue_command"):
			console.enqueue_command(cmd)

func _get_player() -> Node:
	var sm = get_node_or_null("/root/SessionManager")
	if sm and sm.player:
		return sm.player
	return null
