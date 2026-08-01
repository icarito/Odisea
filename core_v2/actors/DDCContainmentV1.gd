extends "res://core_v2/actors/AgentBase.gd"

# DDCContainmentV1.gd
# Kinetic pursuit containment drone.

# --- SIGNALS ---
signal player_contained

# --- ENUMS ---
# Using ContainmentState to avoid conflict with AgentBase's State enum.
enum ContainmentState { CHARGING, INTERCEPT, STUNNED, CONTAINING }

# --- EXPORTED CONFIGURATION ---
export(NodePath) var target_node_path
export(float) var charging_duration := 0.8
export(float) var stun_duration := 3.5
export(float) var flight_height := 1.5
export(float) var player_capture_distance := 1.2
export(float) var containing_duration := 0.5
export(float) var turn_rate := 3.5 # rad/s, limits turn speed
export(float) var charging_speed := 6.3 # 70% of 9.0
export(float) var intercept_speed := 8.55 # 95% of 9.0
export(float) var lure_detection_range := 20.0

# --- STATE VARIABLES ---
var state: int = ContainmentState.CHARGING setget set_containment_state
var state_timer := 0.0
var _player_ref: Node = null
var _pulse_time := 0.0

var _is_spawning := false
var _spawn_anim_timer := 0.0

func _init() -> void:
	# Add to any relevant groups
	add_to_group("ddc_containment")
	# Also join "ddc_drone": CargolDefensiveV1's EMP/lure logic queries this
	# group name (shared with the older DDCDroneV2) to find nearby drones to stun.
	add_to_group("ddc_drone")

func _ready() -> void:
	if target_node_path:
		_player_ref = get_node_or_null(target_node_path)
	if not _player_ref:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player_ref = players[0]
			
	_setup_materials()
	_update_visuals()

# Returns the Cargol companion to chase instead of the player, if one is
# nearby and currently deploying its lure hologram (Cargol tap/hold ability).
func _get_lure_distraction() -> Node:
	for cargol in get_tree().get_nodes_in_group("cargol_defensive"):
		if is_instance_valid(cargol) and cargol.has_method("is_luring") and cargol.is_luring():
			if global_transform.origin.distance_to(cargol.global_transform.origin) <= lure_detection_range:
				return cargol
	return null

func _get_pursuit_target() -> Node:
	var lure = _get_lure_distraction()
	if lure:
		return lure
	return _player_ref

func _setup_materials() -> void:
	var mesh = get_node_or_null("MeshInstance")
	if mesh and mesh is MeshInstance:
		var mat = SpatialMaterial.new()
		mat.albedo_color = Color(0.1, 0.1, 0.15) # Dark metallic dark blue
		mat.metallic = 1.0
		mat.roughness = 0.3
		mat.emission_enabled = true
		mat.emission = Color.black
		mat.emission_energy = 1.0
		mesh.set_surface_material(0, mat)

func set_containment_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	state_timer = 0.0
	
	if state == ContainmentState.STUNNED:
		velocity = Vector3.ZERO
	elif state == ContainmentState.CONTAINING:
		velocity = Vector3.ZERO
		emit_signal("player_contained")
		
	_on_state_changed(state)

func stun(duration: float = 3.5) -> void:
	if state == ContainmentState.CONTAINING:
		return # Cannot stun while capturing the player
	stun_duration = duration
	set_containment_state(ContainmentState.STUNNED)

func play_spawn_animation() -> void:
	_is_spawning = true
	_spawn_anim_timer = 1.0
	scale = Vector3.ZERO

func _process_spawn_animation(dt: float) -> void:
	if not _is_spawning:
		return
	_spawn_anim_timer -= dt
	if _spawn_anim_timer <= 0.0:
		_is_spawning = false
		scale = Vector3.ONE
	else:
		var t = 1.0 - _spawn_anim_timer
		scale = Vector3.ONE * lerp(0.0, 1.0, t)

func step(dt: float) -> void:
	_process_spawn_animation(dt)
	
	# Increment timer
	state_timer += dt
	_pulse_time += dt
	
	# Handle state-specific timers and state-machine transitions
	if _player_ref and is_instance_valid(_player_ref):
		var my_pos = global_transform.origin
		var player_pos = _player_ref.global_transform.origin
		var dist_to_player = my_pos.distance_to(player_pos)
		
		match state:
			ContainmentState.CHARGING:
				if dist_to_player <= player_capture_distance:
					set_containment_state(ContainmentState.CONTAINING)
				elif state_timer >= charging_duration:
					set_containment_state(ContainmentState.INTERCEPT)
					
			ContainmentState.INTERCEPT:
				if dist_to_player <= player_capture_distance:
					set_containment_state(ContainmentState.CONTAINING)
					
			ContainmentState.STUNNED:
				if state_timer >= stun_duration:
					set_containment_state(ContainmentState.CHARGING)
					
			ContainmentState.CONTAINING:
				# Capture phase is delegated to FD-246, but we can have a fallback/complete
				pass
	else:
		# Fallback if player doesn't exist or was freed
		if state == ContainmentState.STUNNED and state_timer >= stun_duration:
			set_containment_state(ContainmentState.CHARGING)

	_update_visuals()

	# NOTE: Intentionally does NOT call .step(dt) (AgentBase). AgentBase.step()
	# auto-disables physics_process when its own current_state == IDLE, which
	# DDCContainmentV1 never sets (it drives motion via ContainmentState instead),
	# causing the drone to freeze permanently after the first frame.
	if _perf_monitor and _perf_monitor.has_method("measure_start"):
		_perf_monitor.measure_start(self, "step")

	var wish_velocity := _calculate_wish_velocity(dt)
	var lerp_weight = clamp(acceleration * dt * 0.1, 0.05, 1.0)
	velocity = velocity.linear_interpolate(wish_velocity, lerp_weight)

	if _perf_monitor and _perf_monitor.has_method("measure_end"):
		_perf_monitor.measure_end(self, "step")

	_canonical_velocity = velocity

	_apply_movement_and_rotation(dt)

# Override _calculate_wish_velocity to handle kinetics, prediction and turn limit
func _calculate_wish_velocity(dt: float) -> Vector3:
	if state == ContainmentState.STUNNED or state == ContainmentState.CONTAINING:
		return Vector3.ZERO

	var pursuit_target = _get_pursuit_target()
	if not pursuit_target or not is_instance_valid(pursuit_target):
		return Vector3.ZERO

	var target_pos = pursuit_target.global_transform.origin

	# Trayectoria de colisión calculada (INTERCEPT predice hacia dónde va el objetivo)
	if state == ContainmentState.INTERCEPT:
		var target_vel = Vector3.ZERO
		if "velocity" in pursuit_target:
			target_vel = pursuit_target.velocity
		elif "linear_velocity" in pursuit_target:
			target_vel = pursuit_target.linear_velocity

		var dist = global_transform.origin.distance_to(target_pos)
		var look_ahead = clamp(dist / max(intercept_speed, 1.0), 0.1, 1.5)
		target_pos += target_vel * look_ahead

	# Flight height adjustment (~1.5m from ground underneath, or match target elevation)
	var floor_y = global_transform.origin.y - flight_height
	var space_state = get_world().direct_space_state
	var result = space_state.intersect_ray(global_transform.origin + Vector3.UP * 0.5, global_transform.origin + Vector3.DOWN * 5.0, [self], 1)
	if not result.empty():
		floor_y = result.position.y
	var target_y = clamp(floor_y + flight_height, pursuit_target.global_transform.origin.y - 1.0, pursuit_target.global_transform.origin.y + 2.0)
	
	var final_target = Vector3(target_pos.x, target_y, target_pos.z)
	var target_dir = final_target - global_transform.origin
	var dist_to_target = target_dir.length()
	
	if dist_to_target > 0.001:
		target_dir = target_dir.normalized()
	else:
		target_dir = -global_transform.basis.z
		
	# Rotate basis slowly towards target_dir to respect turn rate limits (inertia)
	var current_dir = -global_transform.basis.z
	var angle_diff = current_dir.angle_to(target_dir)
	if angle_diff > 0.001:
		var rotation_angle = min(angle_diff, turn_rate * dt)
		var axis = current_dir.cross(target_dir)
		if axis.length_squared() > 0.0001:
			axis = axis.normalized()
			global_transform.basis = global_transform.basis.rotated(axis, rotation_angle)
			global_transform.basis = global_transform.basis.orthonormalized()
			
	# Return wish velocity along the new forward direction
	var current_speed := 0.0
	if state == ContainmentState.CHARGING:
		var t = clamp(state_timer / max(charging_duration, 0.01), 0.0, 1.0)
		current_speed = lerp(0.0, charging_speed, t)
	elif state == ContainmentState.INTERCEPT:
		current_speed = intercept_speed
		
	return -global_transform.basis.z * current_speed

# Override AgentBase's default rotation to preserve our custom limited-turn basis
func _apply_movement_and_rotation(_dt: float) -> void:
	if velocity.length() > 0.001:
		velocity = move_and_slide(velocity, Vector3.UP)

		for i in range(get_slide_count()):
			var collision = get_slide_collision(i)
			if collision.collider is StaticBody or collision.collider is CSGShape:
				emit_signal("obstacle_detected", collision.normal, global_transform.origin.distance_to(collision.position))

func _update_visuals() -> void:
	match state:
		ContainmentState.CHARGING:
			var t = clamp(state_timer / max(charging_duration, 0.01), 0.0, 1.0)
			var blue_color = Color(0.2, 0.4, 1.0) # azul tenue
			var amber_color = Color(1.0, 0.6, 0.0) # ámbar
			var color = blue_color.linear_interpolate(amber_color, t)
			_update_led(color)
			_set_hum_pitch(0.8 + t * 0.4)
		ContainmentState.INTERCEPT:
			var pulse = (sin(_pulse_time * 10.0) + 1.0) * 0.5
			var color = Color(1.0, 0.0, 0.0).linear_interpolate(Color(0.2, 0.0, 0.0), pulse)
			_update_led(color)
			_set_hum_pitch(1.5)
		ContainmentState.STUNNED:
			_update_led(Color(0.05, 0.05, 0.05)) # apagada / muy tenue
			_set_hum_pitch(0.4)
		ContainmentState.CONTAINING:
			_update_led(Color(0.0, 1.0, 1.0)) # stasis bright cyan
			_set_hum_pitch(1.0)

# Explicitly define visual and audio helpers to satisfy static analysers and reviews
func _update_led(color: Color) -> void:
	._update_led(color)

func _set_hum_pitch(pitch: float) -> void:
	._set_hum_pitch(pitch)

# --- REPLAY SNAPSHOTS ---
func get_snapshot() -> Dictionary:
	var snapshot = .get_snapshot()
	snapshot["containment_state"] = state
	snapshot["state_timer"] = state_timer
	snapshot["stun_duration"] = stun_duration
	return snapshot

func restore_snapshot(data: Dictionary) -> void:
	.restore_snapshot(data)
	if data.has("containment_state"):
		state = int(data["containment_state"])
	state_timer = data.get("state_timer", 0.0)
	stun_duration = data.get("stun_duration", stun_duration)
	_update_visuals()
