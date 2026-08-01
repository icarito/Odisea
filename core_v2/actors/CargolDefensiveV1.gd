extends KinematicBody

# core_v2/actors/CargolDefensiveV1.gd
# Principal script for defensive Cargol companion.

enum State { IDLE, EMP_CHARGING, EMP_FIRING, EMP_COOLDOWN, LURE_DEPLOYED, STUNNED, RETURNING }

var state = State.IDLE
var player_node: Node = null
var velocity := Vector3.ZERO
var target_position := Vector3.ZERO

# Timers and parameters
var cooldown_timer := 0.0
var stun_timer := 0.0
var lure_timer := 0.0
var hold_timer := 0.0
var emp_charging_timer := 0.0
var emp_firing_timer := 0.0

var emp_cooldown := 8.0
var lure_cooldown := 15.0
var emp_radius := 5.0
var lure_duration := 5.0
var stun_duration := 6.0
var follow_distance := 2.0
var max_speed := 10.0
var lure_range := 20.0

var _bob_time := 0.0
var _ability_was_pressed := false

# Audio players & light helper references
onready var status_light: Light = get_node_or_null("StatusLight")
onready var hum_player: AudioStreamPlayer3D = get_node_or_null("HumPlayer")
onready var shockwave_particles: CPUParticles = get_node_or_null("ShockwaveParticles")
onready var hologram: Spatial = get_node_or_null("Hologram")

func _init() -> void:
	add_to_group("replay_sync")
	add_to_group("cargol_defensive")

func _ready() -> void:
	_find_player()
	_update_visuals()

func _find_player() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if not players.empty():
		player_node = players[0]

func _follow_player(delta: float) -> void:
	if not player_node or not is_instance_valid(player_node):
		_find_player()
		return

	var p_origin = player_node.global_transform.origin
	var my_origin = global_transform.origin
	
	# Keep follow height at 1.5m above player (shoulder height)
	var target_y = p_origin.y + 1.5
	
	# Horizontal follow direction
	var to_player_h = Vector3(p_origin.x - my_origin.x, 0, p_origin.z - my_origin.z)
	var dist_h = to_player_h.length()
	
	var target_pos = my_origin
	if dist_h > follow_distance:
		var dir_h = to_player_h.normalized()
		target_pos = p_origin - dir_h * follow_distance
		target_pos.y = target_y
	else:
		target_pos.y = target_y
		
	var to_target = target_pos - my_origin
	var dist_to_target = to_target.length()
	
	if dist_to_target > 0.05:
		var speed = clamp(dist_to_target * 5.0, 1.5, max_speed)
		velocity = to_target.normalized() * speed
	else:
		velocity = Vector3.ZERO
		
	# Apply slight hover bobbing
	_bob_time += delta
	velocity.y += sin(_bob_time * 2.0) * 0.15
	
	velocity = move_and_slide(velocity)

func fire_emp() -> void:
	state = State.EMP_CHARGING
	emp_charging_timer = 0.3
	_play_audio_tone(1.0) # anticipation pitch

func _trigger_emp_blast() -> void:
	state = State.EMP_FIRING
	emp_firing_timer = 0.2
	cooldown_timer = emp_cooldown
	
	# Shockwave particles
	if shockwave_particles:
		shockwave_particles.emitting = true
		
	_play_blast_audio()
	
	# Stun DDC drones in range
	var drones = get_tree().get_nodes_in_group("ddc_drone")
	for drone in drones:
		if is_instance_valid(drone) and "global_transform" in drone:
			var dist = global_transform.origin.distance_to(drone.global_transform.origin)
			if dist <= emp_radius:
				if drone.has_method("stun"):
					drone.stun(3.5)

func deploy_lure(target_pos: Vector3) -> void:
	target_position = target_pos
	state = State.LURE_DEPLOYED
	lure_timer = lure_duration
	cooldown_timer = lure_cooldown
	_play_audio_tone(1.2) # deployment confirmation sound

func enter_stunned() -> void:
	state = State.STUNNED
	stun_timer = stun_duration
	hold_timer = 0.0
	_play_audio_tone(0.5) # powered down/sad sound

func step(dt: float) -> void:
	# Update general cooldown timer
	if cooldown_timer > 0.0:
		cooldown_timer = max(0.0, cooldown_timer - dt)
		if cooldown_timer == 0.0 and state == State.EMP_COOLDOWN:
			state = State.IDLE
			
	# Update hum player pitch scale based on state
	if hum_player:
		if state == State.STUNNED:
			hum_player.pitch_scale = 0.2
		elif state == State.EMP_CHARGING:
			hum_player.pitch_scale = 1.8
		elif state == State.LURE_DEPLOYED:
			hum_player.pitch_scale = 1.4
		else:
			hum_player.pitch_scale = 1.0

	# Process ability inputs from player
	_process_inputs(dt)

	# State logic
	match state:
		State.IDLE:
			_follow_player(dt)
		State.EMP_CHARGING:
			_follow_player(dt)
			emp_charging_timer -= dt
			if emp_charging_timer <= 0.0:
				_trigger_emp_blast()
		State.EMP_FIRING:
			_follow_player(dt)
			emp_firing_timer -= dt
			if emp_firing_timer <= 0.0:
				state = State.EMP_COOLDOWN
		State.EMP_COOLDOWN:
			_follow_player(dt)
		State.LURE_DEPLOYED:
			# Displace rapidly to the target lure position
			var to_target = target_position - global_transform.origin
			if to_target.length() > 0.2:
				velocity = to_target.normalized() * (max_speed * 1.5)
				velocity = move_and_slide(velocity)
			else:
				velocity = Vector3.ZERO
			
			# Check overlapping DDC drones for physical touch (stun Cargol)
			var drones = get_tree().get_nodes_in_group("ddc_drone")
			var touched = false
			for drone in drones:
				if is_instance_valid(drone) and "global_transform" in drone:
					var dist = global_transform.origin.distance_to(drone.global_transform.origin)
					if dist < 1.2:
						touched = true
						break
			
			if touched:
				enter_stunned()
			else:
				lure_timer -= dt
				if lure_timer <= 0.0:
					state = State.RETURNING
		State.STUNNED:
			# Falls to floor under gravity kinematics
			velocity = Vector3.DOWN * 5.0
			velocity = move_and_slide(velocity, Vector3.UP)
			
			stun_timer -= dt
			if stun_timer <= 0.0:
				state = State.RETURNING
		State.RETURNING:
			# Move back to player
			if player_node and is_instance_valid(player_node):
				var target_pos = player_node.global_transform.origin + Vector3.UP * 1.5
				var to_player = target_pos - global_transform.origin
				if to_player.length() > 1.5:
					velocity = to_player.normalized() * (max_speed * 1.2)
					velocity = move_and_slide(velocity)
				else:
					# Returned safely! Return to normal follow
					if cooldown_timer > 0.0:
						state = State.EMP_COOLDOWN
					else:
						state = State.IDLE
			else:
				_find_player()
				state = State.IDLE

	_update_visuals()

func _physics_process(delta: float) -> void:
	step(delta)

func _process_inputs(dt: float) -> void:
	if state != State.IDLE:
		_ability_was_pressed = false
		hold_timer = 0.0
		return

	var pressed = false
	if player_node and "last_input" in player_node and player_node.last_input:
		pressed = player_node.last_input.cargol_ability

	if pressed:
		hold_timer += dt
		if hold_timer > 0.3:
			# Tone rising while charging lure
			var charge_progress = clamp((hold_timer - 0.3) / 0.5, 0.0, 1.0)
			_play_audio_tone(1.0 + charge_progress * 1.5)
			
		if hold_timer > 0.8:
			# Complete Lure charge! Get camera forward raycast point
			var target_pos = global_transform.origin + Vector3.FORWARD * 10.0
			var camera = get_viewport().get_camera() if get_viewport() else null
			if camera:
				var from = camera.global_transform.origin
				var to = from - camera.global_transform.basis.z * 100.0
				var space_state = get_world().direct_space_state
				var exclude = [self]
				if player_node:
					exclude.append(player_node)
				var result = space_state.intersect_ray(from, to, exclude, 1)
				if not result.empty():
					target_pos = result.position
				else:
					target_pos = from - camera.global_transform.basis.z * 15.0
			
			deploy_lure(target_pos)
			hold_timer = 0.0
	else:
		if _ability_was_pressed:
			# Released! Check if it was a Tap
			if hold_timer > 0.0 and hold_timer <= 0.3:
				fire_emp()
			hold_timer = 0.0
		else:
			hold_timer = 0.0

	_ability_was_pressed = pressed

func _update_visuals() -> void:
	_bob_time += get_physics_process_delta_time()
	var color = Color(0.2, 0.4, 1.0) # Default Blue
	match state:
		State.IDLE:
			color = Color(0.2, 0.4, 1.0)
		State.EMP_CHARGING:
			var pulse = (sin(_bob_time * 20.0) + 1.0) * 0.5
			color = Color(1.0, 0.5, 0.0).linear_interpolate(Color(0.2, 0.1, 0.0), pulse)
		State.EMP_FIRING:
			color = Color(1.0, 1.0, 1.0)
		State.EMP_COOLDOWN:
			var blink = int(_bob_time * 2.0) % 2 == 0
			color = Color(1.0, 0.5, 0.0) if blink else Color(0.2, 0.1, 0.0)
		State.LURE_DEPLOYED:
			var pulse = (sin(_bob_time * 10.0) + 1.0) * 0.5
			color = Color(0.2, 1.0, 0.2).linear_interpolate(Color(0.0, 0.2, 0.0), pulse)
		State.STUNNED:
			color = Color(0.3, 0.0, 0.0)
		State.RETURNING:
			color = Color(0.2, 1.0, 1.0)

	_update_led(color)
	
	# Hologram flicker visual
	if hologram and is_instance_valid(hologram):
		if state == State.LURE_DEPLOYED:
			hologram.visible = randf() > 0.15
		else:
			hologram.visible = false

func _update_led(color: Color) -> void:
	var mesh = get_node_or_null("MeshInstance")
	if mesh and mesh is MeshInstance:
		var mat = mesh.get_surface_material(0)
		if not mat or not mat is SpatialMaterial:
			mat = SpatialMaterial.new()
			mat.resource_local_to_scene = true
			mesh.set_surface_material(0, mat)
		if mat is SpatialMaterial:
			mat.albedo_color = color
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy = 1.0

	if status_light and is_instance_valid(status_light):
		status_light.light_color = color

func _play_audio_tone(pitch: float) -> void:
	var player = get_node_or_null("LurePlayer")
	if player and player is AudioStreamPlayer3D:
		if not player.playing:
			player.play()
		player.pitch_scale = pitch

func _play_blast_audio() -> void:
	var player = get_node_or_null("EMPPlayer")
	if player and player is AudioStreamPlayer3D:
		player.play()

# --- REPLAY SYSTEM ---

func get_snapshot() -> Dictionary:
	return {
		"tf_origin": var2str(global_transform.origin),
		"tf_basis": var2str(global_transform.basis),
		"velocity": var2str(velocity),
		"target_position": var2str(target_position),
		"state": state,
		"cooldown_timer": cooldown_timer,
		"stun_timer": stun_timer,
		"lure_timer": lure_timer,
		"hold_timer": hold_timer,
		"emp_charging_timer": emp_charging_timer,
		"emp_firing_timer": emp_firing_timer,
		"bob_time": _bob_time,
		"ability_was_pressed": _ability_was_pressed
	}

func restore_snapshot(data: Dictionary) -> void:
	if data.has("tf_origin") and data.has("tf_basis"):
		var o = str2var(data["tf_origin"])
		var b = str2var(data["tf_basis"])
		global_transform = Transform(b, o)

	velocity = str2var(data.get("velocity", "Vector3(0,0,0)"))
	target_position = str2var(data.get("target_position", "Vector3(0,0,0)"))
	state = int(data.get("state", State.IDLE))
	cooldown_timer = float(data.get("cooldown_timer", 0.0))
	stun_timer = float(data.get("stun_timer", 0.0))
	lure_timer = float(data.get("lure_timer", 0.0))
	hold_timer = float(data.get("hold_timer", 0.0))
	emp_charging_timer = float(data.get("emp_charging_timer", 0.0))
	emp_firing_timer = float(data.get("emp_firing_timer", 0.0))
	_bob_time = float(data.get("bob_time", 0.0))
	_ability_was_pressed = bool(data.get("ability_was_pressed", false))
	_update_visuals()
