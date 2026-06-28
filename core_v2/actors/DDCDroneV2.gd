extends "res://core_v2/actors/AgentBase.gd"

# DDCDroneV2.gd
# Patrol drone with detection and alert states.

# --- EXPORTED CONFIGURATION ---
export(float) var detection_radius := 10.0
export(float) var alert_detection_radius := 15.0
export(float) var vision_angle := 45.0 # Degrees
export(float) var search_time := 5.0
export(float) var waypoint_pause_time := 2.0
export(float) var alert_speed_multiplier := 1.5

# --- SIGNALS ---
signal player_detected

# --- STATE VARIABLES ---
var _patrol_points := []
var _current_waypoint_idx := 0
var _search_timer := 0.0
var _pause_timer := 0.0
var _last_seen_player_pos := Vector3.ZERO
var _player_ref: Node = null
var _pulse_time := 0.0
var _cone_fade := 0.0

func _init():
	add_to_group("ddc_drone")

func _ready():
	_player_ref = get_tree().get_nodes_in_group("player")[0] if get_tree().get_nodes_in_group("player").size() > 0 else null
	_discover_patrol_points()
	_setup_materials()
	_update_visuals()

func _setup_materials():
	var mesh = get_node_or_null("MeshInstance")
	if mesh and mesh is MeshInstance:
		var mat = SpatialMaterial.new()
		mat.albedo_color = Color(0.1, 0.1, 0.1) # Dark metallic
		mat.metallic = 1.0
		mat.roughness = 0.4
		mat.emission_enabled = true
		mat.emission = Color.black
		mat.emission_energy = 1.0
		mesh.set_surface_material(0, mat)

func _discover_patrol_points():
	_patrol_points.clear()
	for child in get_children():
		if child is Position3D and child.name.begins_with("Waypoint"):
			_patrol_points.append(child.global_transform.origin)
	
	if _patrol_points.size() > 0:
		move_to(_patrol_points[0])

func _on_state_changed(new_state):
	match new_state:
		State.PATROL, State.IDLE:
			max_speed = 5.0
			_set_hum_pitch(0.9)
			_set_alarm_light_visible(false)
		State.ALERT:
			max_speed = 5.0 * alert_speed_multiplier
			_set_hum_pitch(1.5)
			_set_alarm_light_visible(true)
			emit_signal("player_detected")
		State.SEARCH:
			_search_timer = search_time
			# pitch oscillation in step
			_set_alarm_light_visible(false)
		State.RETURN_HOME:
			max_speed = 5.0
			_set_hum_pitch(1.0)
			_set_alarm_light_visible(false)

func _set_alarm_light_visible(v: bool):
	var rig = get_node_or_null("AlarmLightRig")
	if rig: rig.visible = v

func step(dt: float) -> void:
	# Detection logic
	_check_detection(dt)
	
	_pulse_time += dt

	# Visual effects based on state
	match current_state:
		State.PATROL, State.IDLE:
			var pulse = (sin(_pulse_time * 2.0) + 1.0) * 0.5
			_update_led(Color.red.linear_interpolate(Color(0.2, 0, 0), pulse))
			_cone_fade = max(_cone_fade - dt * 4.0, 0.0)
		State.ALERT:
			var pulse = (sin(_pulse_time * 10.0) + 1.0) * 0.5
			_update_led(Color.red.linear_interpolate(Color.white, pulse * 0.5))
			_cone_fade = min(_cone_fade + dt * 2.0, 1.0)
			var rig = get_node_or_null("AlarmLightRig")
			if rig: rig.rotate_y(dt * 10.0)
		State.SEARCH:
			var blink = int(_pulse_time * 4.0) % 2 == 0
			_update_led(Color.yellow if blink else Color.black)
			_cone_fade = max(_cone_fade - dt * 4.0, 0.0)
			_set_hum_pitch(1.0 + (sin(_pulse_time * 3.0) + 1.0) * 0.5 * 0.3)
		_:
			_cone_fade = max(_cone_fade - dt * 4.0, 0.0)

	var cone = get_node_or_null("VisionCone")
	if cone:
		cone.visible = _cone_fade > 0.01
		var target_scale = 1.5 if current_state == State.ALERT else 1.0
		var s = target_scale * _cone_fade
		cone.scale = Vector3(s, s, s)

	# State-specific logic
	match current_state:
		State.IDLE:
			if _patrol_points.size() > 0:
				self.current_state = State.PATROL
		State.PATROL:
			if _pause_timer > 0:
				_pause_timer -= dt
				if _pause_timer <= 0:
					_current_waypoint_idx = (_current_waypoint_idx + 1) % _patrol_points.size()
					move_to(_patrol_points[_current_waypoint_idx])
			elif global_transform.origin.distance_to(target_position) < 0.5:
				_pause_timer = waypoint_pause_time
		State.SEARCH:
			_search_timer -= dt
			if _search_timer <= 0:
				if _patrol_points.size() > 0:
					move_to(_patrol_points[_current_waypoint_idx])
					self.current_state = State.PATROL
				else:
					self.current_state = State.IDLE

	.step(dt)

func _check_detection(_dt: float):
	if not _player_ref or not is_instance_valid(_player_ref):
		return
		
	var player_pos = _player_ref.global_transform.origin + Vector3.UP * 1.0 # Target chest
	var my_pos = global_transform.origin
	var to_player = player_pos - my_pos
	var dist = to_player.length()
	
	var current_radius = detection_radius
	if current_state == State.ALERT:
		current_radius = alert_detection_radius
		
	var stealth = _player_ref.get_node_or_null("Logic/Stealth")
	if stealth:
		current_radius *= stealth.get_visibility_score()

	if dist > current_radius:
		if current_state == State.ALERT:
			self.current_state = State.SEARCH
		return

	var forward = -global_transform.basis.z
	var angle = rad2deg(forward.angle_to(to_player))
	
	if angle < vision_angle:
		var space_state = get_world().direct_space_state
		# Raycast checking for player specifically
		var result = space_state.intersect_ray(my_pos, player_pos, [self], 1 | 2) # Layer 1: Env, Layer 2: Player
		
		if not result.empty() and result.collider == _player_ref:
			_last_seen_player_pos = player_pos
			if current_state != State.ALERT:
				self.current_state = State.ALERT
		else:
			if current_state == State.ALERT:
				self.current_state = State.SEARCH
	else:
		if current_state == State.ALERT:
			self.current_state = State.SEARCH


func get_snapshot() -> Dictionary:
	var data = .get_snapshot()
	data["last_player_pos"] = var2str(_last_seen_player_pos)
	data["search_timer"] = _search_timer
	data["pause_timer"] = _pause_timer
	data["waypoint_idx"] = _current_waypoint_idx
	return data

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	_last_seen_player_pos = str2var(data.get("last_player_pos", "Vector3(0,0,0)"))
	_search_timer = data.get("search_timer", 0.0)
	_pause_timer = data.get("pause_timer", 0.0)
	_current_waypoint_idx = data.get("waypoint_idx", 0)
