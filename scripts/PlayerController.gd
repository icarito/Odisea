extends KinematicBody

# Placeholder: controlador de Elías basado en PlayerTemplate
# Nota: Se moverá lógica avanzada y referencias de animación conforme al refactor

export (NodePath) var PlayerAnimationTree 
export onready var animation_tree = get_node(PlayerAnimationTree)
onready var playback = animation_tree.get("parameters/playback")

export (NodePath) var PlayerCharacterMesh
export onready var player_mesh = get_node(PlayerCharacterMesh)

const ReplayUtils = preload("res://scripts/replay/ReplayUtils.gd")

export var gravity = 9.8
export var jump_force = 9
export var turn_speed := 2.0
export var dash_power := 12.0

# Velocidad externa aplicada por plataformas/conveyors (legacy, ahora en componente)
var platform_velocity := Vector3.ZERO
var platform_is_static_surface := false
var last_platform_velocity := Vector3.ZERO
export var snap_len := 0.5
var snap_enabled := true

# Components
onready var external_velocity: ExternalVelocity = $ExternalVelocity if has_node("ExternalVelocity") else null
onready var jump_comp: PlayerJump = $PlayerJump if has_node("PlayerJump") else null
onready var movement_comp: PlayerMovement = $PlayerMovement if has_node("PlayerMovement") else null
onready var player_input: Node = $PlayerInput if has_node("PlayerInput") else null

# NEW: Multiplayer support
var player_id := 1

# Legacy variables (some may be moved to components)
var airborne_inherited := Vector3.ZERO
var was_on_floor := false
export var max_platform_up_follow := 5.0
export var inherit_vertical_platform_jump := true
var just_jumped := false
var time_since_jump := 1.0
var time_since_input := 1.0
var mouse_active_timer := 0.0

export var debug_movement := false
export var debug_shadow := false
export var debug_input := false
export var debug_enabled := false # bandera global para desactivar todos los logs por defecto

export var floating_after_jump_delay := 0.25
export var floating_no_input_delay := 0.3
export var floating_vertical_speed_threshold := 0.35 # deprecated: use enter/exit thresholds below
export var floating_enter_vspeed_threshold := 0.4
export var floating_exit_vspeed_threshold := 1.0
export var floating_vspeed_smooth := 0.35
var _vspeed_smoothed := 0.0
export var floating_enter_accel_threshold := 2.0
export var floating_exit_accel_threshold := 3.5
export var floating_accel_smooth := 0.3
var _vaccel_smoothed := 0.0
var _prev_vy := 0.0
export var floating_from_jump_delay := 1.0
var time_in_jump_state := 0.0
export var floating_without_jump_delay := 0.5
export var floating_without_jump_requires_no_input := false
export var floating_move_speed_max := 4.8
export var floating_move_accel := 6.0
export var floating_horizontal_damping := 1.0

var roll_node_name = "Roll"
var idle_node_name = "Idle"
var walk_node_name = "Walk"
var run_node_name = "Run"
var jump_node_name = "Jump"
var attack1_node_name = "Attack1"
var attack2_node_name = "Attack2"
var bigattack_node_name = "BigAttack"

var is_attacking = false
var is_rolling = false

var aim_turn = 0.0
var velocity = Vector3() # Replaces 'movement' and 'vertical_velocity' for move_and_slide
var vertical_velocity = Vector3()
var pre_move_velocity_for_replay = Vector3()

# Touch camera control
export var touch_sensitivity := 0.1

var angular_acceleration = 10
export(float, 0.0, 10.0, 0.1) var tank_turn_speed := 0.3
export(float, 0.0, 10.0, 0.1) var advancing_turn_speed := 0.3
export(float, 0.0, 1.0, 0.01) var analog_turn_multiplier := 1.0
export(float, 0.0, 1.0, 0.01) var sprint_threshold := 0.7
export(float, 0.0, 2000.0, 10.0) var mouse_active_timeout_ms := 500.0
var is_tank_turning = false
export(float, 0.0, 50.0, 0.5) var max_rise_speed := 20.0
export(float, 0.0, 50.0, 0.5) var max_fall_speed := 30.0
export var cam_yaw_offset := 0.0 # radianes para compensar desfase de cámara
export var swap_input_axes := false # intercambia X/Z si el mapeo queda 90° corrido
export var invert_forward := false # invierte el eje Z si el mesh mira -Z
export var mesh_yaw_offset := 0.0 # compensación fija si el mesh tiene un desfase (p.ej. 45°)
export var debug_yaw := false # imprime YawAlign/Dir cada frame para diagnóstico
export(float, 0.0, 2.0, 0.01) var debug_interval := 0.4 # segundos entre trazas (unificado)
var debug_timer = Timer.new()
var debug_ready: bool = true
var _debug_t := 0.0
var _last_debug_ms := 0
var _last_tag_ms := {}
var _last_cam_yaw := -999.0
var _last_dir := Vector3.ZERO
export(float, 0.0, 1.0, 0.01) var debug_yaw_threshold := 0.05 # rad (~3°)
export(float, 0.0, 1.0, 0.01) var debug_dir_threshold := 0.05 # vector length change
export var invert_joy_x := false
export var invert_joy_y := false
var _last_anim_node := ""
var _last_is_floating := false
var has_seen_floor_once := false
var time_since_start := 0.0
export var startup_floating_block_time := 0.6
var _debug_input_last := 0.0

var _touch_camera_connected := false

var direction := Vector3.ZERO
var horizontal_velocity := Vector3.ZERO
var movement_speed := 0.0
var acceleration := 15.0

var is_walking := false
var is_running := false

onready var ground_ray: RayCast = $GroundRay
onready var fake_shadow: MeshInstance = $PilotMesh/FakeShadow

# Override local de gravedad desde zonas (WindZone)
var local_gravity_override := Vector3.ZERO

func set_gravity_override(g: Vector3) -> void:
	local_gravity_override = g

func clear_gravity_override() -> void:
	local_gravity_override = Vector3.ZERO

# Interfaz pública para que plataformas/conveyors transfieran velocidad
func set_external_velocity(v: Vector3) -> void:
	if external_velocity:
		external_velocity.set_external_velocity(v)
	else:
		platform_velocity = v

func _ready():
	# Connect to GameGlobals for debug mode
	if GameGlobals:
		debug_enabled = GameGlobals.debug_mode
		GameGlobals.connect("debug_mode_changed", self, "_on_debug_mode_changed")
		# Set mouse capture immediately
		GameGlobals.mouse_captured = true

	if UIManager:
		UIManager.connect("overlay_shown", self, "_on_UIManager_overlay_shown")
		UIManager.connect("overlay_hidden", self, "_on_UIManager_overlay_hidden")

	# Alinear dirección inicial con el frente del mesh y la cámara
	var yaw_node = get_node_or_null("CameraRig/Yaw")
	var yaw_angle := 0.0
	if yaw_node:
		yaw_angle = yaw_node.global_transform.basis.get_euler().y + cam_yaw_offset
	# Usar frente del mesh para coherencia de animación al inicio
	var initial_direction = Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
	# Si la cámara existe, rotar la dirección por su yaw para entrada relativa a cámara
	initial_direction = initial_direction.rotated(Vector3.UP, yaw_angle)
	if movement_comp:
		movement_comp.direction = initial_direction
	if ground_ray:
		ground_ray.enabled = true
		ground_ray.add_exception(self)

	if debug_movement or debug_shadow:
		debug_timer.wait_time = 0.5
		debug_timer.wait_time = 0.5
		debug_timer.one_shot = false
		debug_timer.connect("timeout", self, "_on_debug_timer_timeout")
		add_child(debug_timer)
		debug_timer.start()

	# Inicializar condiciones del AnimationTree para evitar entrar en Swim al inicio
	if animation_tree:
		animation_tree["parameters/conditions/IsOnFloor"] = true
		animation_tree["parameters/conditions/IsInAir"] = false
		animation_tree["parameters/conditions/IsFloating"] = false
	# Inicialización simple: nada que suavizar del yaw del cuerpo
	

func _connect_touch_camera():
	var current_scene = get_tree().current_scene
	if not is_instance_valid(current_scene):
		return # Scene is not ready, try again next frame.
	var touch_controls = current_scene.find_node("TouchControls", true, false)
	if touch_controls:
		var camera_input = touch_controls.get_node_or_null("CameraInput")
		if camera_input:
			if not camera_input.is_connected("camera_vector_changed", self, "_on_CameraInput_camera_vector_changed"):
				var err = camera_input.connect("camera_vector_changed", self, "_on_CameraInput_camera_vector_changed")
				if err == OK:
					_touch_camera_connected = true

func _on_CameraInput_camera_vector_changed(vector):
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig and cam_rig.has_method("process_camera_rotation"):
		cam_rig.process_camera_rotation(vector * touch_sensitivity)

func _on_debug_mode_changed(enabled: bool):
	debug_enabled = enabled

func set_player_id(id: int) -> void:
	"""Set player ID from outside and propagate to components."""
	player_id = id
	
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig and cam_rig.has_method("set_player_id"):
		cam_rig.set_player_id(id)
	else:
		if id == 2:
			push_warning("CameraRig node not found or it's missing the set_player_id method.")
	
func set_external_source_is_static(is_static: bool) -> void:
	platform_is_static_surface = is_static

var _is_ui_overlay_active := false
func _on_UIManager_overlay_shown():
	_is_ui_overlay_active = true
func _on_UIManager_overlay_hidden():
	_is_ui_overlay_active = false

func _input(event):
	# Capturar movimiento del mouse siempre, incluso durante overlays
	if player_input and player_input.use_mouse_input and event is InputEventMouseMotion:
		# En lugar de pasarlo a una variable 'aim_turn' que no se usa,
		# lo pasamos directamente al componente de input para que lo procese.
		player_input.mouse_motion += event.relative

	# Ignorar otros inputs si hay un overlay de UI activo
	if _is_ui_overlay_active:
		return

	if event.is_action_pressed("aim"):
		# Al entrar en aim, sincronizar cámara con el cuerpo usando el offset
		var cam_rig = get_node_or_null("CameraRig")
		if cam_rig and cam_rig.has_method("sync_to_body_yaw"):
			cam_rig.sync_to_body_yaw(rotation.y, cam_yaw_offset)
		direction = $CameraRig/Yaw.global_transform.basis.z
	if event.is_action_released("aim"):
		# Al salir de aim, asegurar que el mesh y la cámara sigan el cuerpo con sus offsets
		player_mesh.rotation.y = rotation.y + mesh_yaw_offset

func _process(_delta):
	if has_node("FPSLabel"):
		$FPSLabel.text = "FPS: " + str(Engine.get_frames_per_second())

func roll():
	if Input.is_action_just_pressed("roll"):
		if !roll_node_name in playback.get_current_node() and !jump_node_name in playback.get_current_node() and !bigattack_node_name in playback.get_current_node():
			playback.start(roll_node_name)
			horizontal_velocity = direction * dash_power

func attack1():
	if (idle_node_name in playback.get_current_node() or walk_node_name in playback.get_current_node()) and is_on_floor():
		if Input.is_action_just_pressed("attack"):
			if (is_attacking == false):
				playback.travel(attack1_node_name)

func attack2():
	if attack1_node_name in playback.get_current_node():
		if Input.is_action_just_pressed("attack"):
			playback.travel(attack2_node_name)

func attack3():
	if attack1_node_name in playback.get_current_node():
		if Input.is_action_just_pressed("attack"):
			pass

func rollattack():
	if roll_node_name in playback.get_current_node():
		if Input.is_action_just_pressed("attack"):
			playback.travel(bigattack_node_name)

func bigattack():
	if run_node_name in playback.get_current_node():
		if Input.is_action_just_pressed("attack"):
			horizontal_velocity = direction * dash_power
			playback.travel(bigattack_node_name)

func _on_debug_timer_timeout():
	debug_ready = true
	# Debounce de logs

func _can_log() -> bool:
	var now := OS.get_ticks_msec()
	var interval_ms := int(debug_interval * 1000.0)
	if now - _last_debug_ms >= interval_ms:
		_last_debug_ms = now
		return true
	return false

func _can_log_tag(tag: String) -> bool:
	var now := OS.get_ticks_msec()
	var interval_ms := int(debug_interval * 1000.0)
	var last := int(_last_tag_ms.get(tag, 0))
	if now - last >= interval_ms:
		_last_tag_ms[tag] = now
		return true
	return false

func print_debug(msg: String) -> void:
	# Debounce simple y centralizado para cualquier salida de debug
	if not debug_enabled:
		return
	if _can_log():
		print(msg)

func print_debug_tag(tag: String, msg: String) -> void:
	if not debug_enabled:
		return
	if _can_log_tag(tag):
		print(msg)

func _debug_input_snapshot() -> Dictionary:
	return {
		"left": Input.is_action_pressed("left"),
		"right": Input.is_action_pressed("right"),
		"forward": Input.is_action_pressed("forward"),
		"backward": Input.is_action_pressed("backward"),
		"lookleft": Input.is_action_pressed("lookleft"),
		"lookright": Input.is_action_pressed("lookright"),
		"aim": Input.is_action_pressed("aim"),
		"sprint": Input.is_action_pressed("sprint"),
		"jump": Input.is_action_pressed("jump"),
		"attack": Input.is_action_pressed("attack"),
		"roll": Input.is_action_pressed("roll")
	}

func _align_camera_to_body():
	"""
	Called deferred from PlayerManager after spawn to correctly initialize camera yaw.
	"""
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig and cam_rig.has_method("sync_to_body_yaw"):
		var body_yaw = global_transform.basis.get_euler().y
		# Use PI as offset to look from behind, consistent with respawn logic.
		var offset = PI
		cam_rig.sync_to_body_yaw(body_yaw, offset)
		print("[PlayerController] _align_camera_to_body: Synced camera to body yaw ", rad2deg(body_yaw), " with offset ", rad2deg(offset))
	else:
		print("[PlayerController] _align_camera_to_body: CameraRig or sync_to_body_yaw not found.")

var _last_input_state := {}

func _physics_process(delta):
	var has_input := false
	var movement_this_frame := Vector3.ZERO
	var is_replaying = GameGlobals and GameGlobals.is_replaying
	
	if not _touch_camera_connected:
		_connect_touch_camera()

	time_since_jump += delta
	time_since_input += delta
	time_since_start += delta
	
	var on_floor = is_on_floor()

	if not is_replaying:
		# --- NORMAL GAME LOGIC: ALL VELOCITY CALCULATION HAPPENS HERE ---

		# Process attacks and rolls that can affect movement
		rollattack()
		bigattack()
		attack1()
		attack2()
		roll()

		# Medir tiempo en estado Jump del AnimationTree
		var in_jump_state = (playback and (playback.get_current_node() == jump_node_name))
		if in_jump_state:
			time_in_jump_state += delta
		else:
			time_in_jump_state = 0.0

		# Marcar que vimos suelo al menos una vez para habilitar floating post-inicio
		if on_floor:
			has_seen_floor_once = true
		
		# Reset movement parameters
		movement_speed = 0
		angular_acceleration = 10
		acceleration = 15

		# Gravedad efectiva: usar override si existe
		var effective_gravity_vector := local_gravity_override if (local_gravity_override.length() > 0.01) else (Vector3.DOWN * gravity)
		var effective_gravity_mag := effective_gravity_vector.length()
		var effective_gravity_dir := effective_gravity_vector.normalized() if (effective_gravity_mag > 0.01) else Vector3.DOWN
		
		# Apply Gravity
		if not is_on_floor():
			vertical_velocity += effective_gravity_vector * 2 * delta
		else:
			# Si la gravedad efectiva apunta hacia arriba (levanta), despegar del suelo
			if effective_gravity_dir.dot(Vector3.UP) > 0.5:
				snap_enabled = false
				vertical_velocity = effective_gravity_dir * min(effective_gravity_mag, gravity) * 0.5
			else:
				vertical_velocity = -get_floor_normal() * min(effective_gravity_mag, gravity) / 3

		# Clamp de velocidad vertical para evitar picos
		vertical_velocity.y = clamp(vertical_velocity.y, -max_fall_speed, max_rise_speed)

		# Check for attack/roll states that modify acceleration
		if (attack1_node_name in playback.get_current_node()) or (attack2_node_name in playback.get_current_node()) or (bigattack_node_name in playback.get_current_node()):
			is_attacking = true
		else:
			is_attacking = false

		if bigattack_node_name in playback.get_current_node():
			acceleration = 3

		if roll_node_name in playback.get_current_node():
			is_rolling = true
			acceleration = 2
			angular_acceleration = 2
		else:
			is_rolling = false
		
		# Process player input
		var input_vector := Vector2.ZERO
		var mouse_motion := Vector2.ZERO
		var is_sprinting := false
		var jump_pressed := false

		if player_input:
			input_vector = player_input.get_input_vector()
			mouse_motion = player_input.get_mouse_motion()
			is_sprinting = player_input.is_sprint_pressed()
			jump_pressed = player_input.just_jumped()
		else:
			# Fallback to single player input if PlayerInput node is missing
			input_vector = Vector2(Input.get_action_strength("left") - Input.get_action_strength("right"), Input.get_action_strength("forward") - Input.get_action_strength("backward"))
			is_sprinting = Input.is_action_pressed("sprint")
			jump_pressed = Input.is_action_just_pressed("jump")
		
		has_input = input_vector.length() > 0.1
		print("[PlayerController] Raw Inputs: Fwd=%s, Left=%s, Sprint=%s" % [Input.is_action_pressed("forward"), Input.is_action_pressed("left"), is_sprinting])

		# Control de movimiento y rotación
		rotation.y += input_vector.x * turn_speed * delta
		direction = Vector3(0, 0, -input_vector.y).rotated(Vector3.UP, rotation.y)

		# Handle Jump
		if jump_pressed and ((is_attacking != true) and (is_rolling != true)) and is_on_floor():
			if AudioSystem: AudioSystem.play_sfx("res://assets/sfx/jump.wav")
			var pv := platform_velocity
			vertical_velocity = Vector3.UP * jump_force
			if inherit_vertical_platform_jump and pv.y > 0.0:
				vertical_velocity.y += min(pv.y, max_platform_up_follow)
			snap_enabled = false
			airborne_inherited = Vector3(pv.x, 0, pv.z)
			horizontal_velocity += airborne_inherited
			just_jumped = true
			time_since_jump = 0.0

		if has_input:
			time_since_input = 0.0

		# Camera Control
		var cam_rig = get_node_or_null("CameraRig")
		if cam_rig:
			if cam_rig.has_method("process_camera_rotation"):
				cam_rig.process_camera_rotation(mouse_motion)
			if mouse_motion.length() > 0.01: mouse_active_timer = mouse_active_timeout_ms / 1000.0
			mouse_active_timer = max(0.0, mouse_active_timer - delta)
			
			if movement_comp:
				var basis := Basis()
				var yaw_node_local = get_node_or_null("CameraRig/Yaw")
				if yaw_node_local: basis = yaw_node_local.global_transform.basis
				movement_comp.process_input_vector(delta, basis, input_vector, is_sprinting, on_floor)
				var turn_input = input_vector.x
				var effective_tank_speed = tank_turn_speed if not player_input.use_mouse_input else 0
				var yaw_delta = turn_input * effective_tank_speed * delta
				rotation.y += yaw_delta
				if cam_rig.has_method("apply_external_yaw_delta"): cam_rig.apply_external_yaw_delta(yaw_delta)
				direction = movement_comp.direction
				horizontal_velocity = movement_comp.get_horizontal_velocity()
				is_walking = movement_comp.is_walking
				is_running = movement_comp.is_running
			else:
				is_walking = false; is_running = false; direction = Vector3.ZERO; horizontal_velocity = Vector3.ZERO
		
		# Platform velocity logic
		platform_velocity = platform_velocity.linear_interpolate(Vector3.ZERO, 6.0 * delta)
		if is_on_floor():
			last_platform_velocity = platform_velocity
			airborne_inherited = Vector3.ZERO
			if platform_velocity.y > 0.0 and not just_jumped:
				vertical_velocity.y = min(platform_velocity.y, max_platform_up_follow)
		elif was_on_floor:
			airborne_inherited = last_platform_velocity
		
		# Final velocity combination for this frame
		var effective_platform_velocity := (Vector3(platform_velocity.x, 0, platform_velocity.z) if (is_on_floor() and platform_is_static_surface) else airborne_inherited)
		var combined_horizontal = horizontal_velocity + effective_platform_velocity
		movement_this_frame = combined_horizontal + vertical_velocity

	else:
		# --- REPLAY LOGIC ---
		# Velocity is injected by the ReplayPlayback system into the 'velocity' property.
		# Use it directly as the movement vector for this frame.
		movement_this_frame = velocity
		
		# Derive animation states from the injected velocity.
		horizontal_velocity = velocity - Vector3(0, velocity.y, 0)
		if horizontal_velocity.length_squared() > 0.01:
			direction = horizontal_velocity.normalized()
		else:
			direction = Vector3.ZERO
		
		var is_sprinting = Input.is_action_pressed("sprint")
		is_walking = horizontal_velocity.length_squared() > 0.01
		is_running = is_walking and is_sprinting
		if movement_comp:
			movement_comp.is_walking = is_walking
			movement_comp.is_running = is_running
		
		# Update attack/roll states from animation for other logic
		is_attacking = (attack1_node_name in playback.get_current_node()) or (attack2_node_name in playback.get_current_node()) or (bigattack_node_name in playback.get_current_node())
		is_rolling = (roll_node_name in playback.get_current_node())

	# --- LOGIC THAT RUNS IN BOTH MODES ---

	# Rotate mesh towards movement direction
	if direction != Vector3.ZERO:
		var target_y := atan2(direction.x, direction.z) + mesh_yaw_offset
		var parent_y = rotation.y
		var local_target_y = global_target_y - parent_y
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, local_target_y, delta * angular_acceleration)

	var h_rot := 0.0
	var yaw_node2 = get_node_or_null("CameraRig/Yaw")
	if yaw_node2: h_rot = yaw_node2.global_transform.basis.get_euler().y + cam_yaw_offset

	# Detailed logging for replay diagnostics
	if GameGlobals and GameGlobals.replay_debug_mode and is_replaying:
		print("[PlayerController Playback] Pre-move: velocity=", movement_this_frame, " on_floor=", on_floor)
	
	print("[PlayerController] Pre-move: velocity=%s, on_floor=%s" % [movement_this_frame, on_floor])
	pre_move_velocity_for_replay = movement_this_frame
	
	# Snap to ground
	var snap_vec := Vector3.ZERO
	if on_floor and snap_enabled:
		snap_vec = Vector3.DOWN * snap_len
	elif on_floor:
		snap_enabled = true

	# --- THE ACTUAL PHYSICS STEP ---
	velocity = move_and_slide_with_snap(movement_this_frame, snap_vec, Vector3.UP, false)
	# ---

	print("[PlayerController] Post-move Pos (Simulated): %s" % [global_transform.origin])
	print("[PlayerController POST-SLIDE] Velocity: %s" % [velocity])
	
	# Update velocity components from the result for the next frame
	horizontal_velocity = velocity - Vector3(0, velocity.y, 0)
	if movement_comp:
		movement_comp.horizontal_velocity = horizontal_velocity
	vertical_velocity.y = velocity.y
	
	was_on_floor = is_on_floor()
	just_jumped = false # Reset one-frame flag

	# --- FAKE SHADOW & ANIMATIONS ---
	if ground_ray.is_colliding():
		var hit = ground_ray.get_collision_point()
		fake_shadow.global_transform.origin = Vector3(hit.x, hit.y + 0.01, hit.z)
		var dist = global_transform.origin.y - hit.y
		var s = clamp(0.6 + dist * 0.4, 0.5, 2.0)
		fake_shadow.scale = Vector3(s, 1.0, s)
		var mat = fake_shadow.get_surface_material(0)
		if mat: mat.albedo_color.a = clamp(1.0 - dist * 0.4, 0.2, 0.9)
		fake_shadow.visible = true
	else:
		fake_shadow.visible = false

	# Animation Tree Updates
	animation_tree["parameters/conditions/IsOnFloor"] = on_floor
	animation_tree["parameters/conditions/IsInAir"] = !on_floor
	animation_tree["parameters/conditions/IsWalking"] = is_walking
	animation_tree["parameters/conditions/IsNotWalking"] = !is_walking
	animation_tree["parameters/conditions/IsRunning"] = is_running
	animation_tree["parameters/conditions/IsNotRunning"] = !is_running

	# Floating state logic (uses vertical_velocity, which is now post-slide)
	var v_accel = 0.0
	if delta > 0.0: v_accel = (vertical_velocity.y - _prev_vy) / delta
	_prev_vy = vertical_velocity.y
	_vaccel_smoothed = lerp(_vaccel_smoothed, v_accel, floating_accel_smooth)
	var vertical_accel = abs(_vaccel_smoothed)
	var vspeed_raw = abs(vertical_velocity.y)
	_vspeed_smoothed = lerp(_vspeed_smoothed, vspeed_raw, floating_vspeed_smooth)
	var vertical_speed = _vspeed_smoothed

	var in_jump_state = (playback and (playback.get_current_node() == jump_node_name))
	var falling_without_jump = (!on_floor) and (time_since_jump > floating_without_jump_delay)
	var no_input_ok = (not floating_without_jump_requires_no_input) or (time_since_input > floating_no_input_delay)
	var accel_ok = (_last_is_floating and (vertical_accel <= floating_exit_accel_threshold)) or ((not _last_is_floating) and (vertical_accel <= floating_enter_accel_threshold))
	var vspeed_ok = (_last_is_floating and (vertical_speed < floating_exit_vspeed_threshold)) or ((not _last_is_floating) and (vertical_speed < floating_enter_vspeed_threshold))
	var startup_block_clear = has_seen_floor_once or (time_since_start > startup_floating_block_time)
	var should_float = startup_block_clear and (!on_floor) and (accel_ok or (falling_without_jump and vspeed_ok)) and (not is_attacking) and (not is_rolling) and (
		((time_since_jump > floating_after_jump_delay) and (time_since_input > floating_no_input_delay))
		or (time_in_jump_state > floating_from_jump_delay)
		or (falling_without_jump and no_input_ok)
	)
	animation_tree["parameters/conditions/IsFloating"] = should_float
	_last_is_floating = should_float


# Respawn-safe reset of transient movement state
func reset_state_for_respawn(new_transform: Transform) -> void:
	"""
	Resetea completamente el estado del jugador para un respawn.
	Establece la nueva posición/rotación y limpia todas las velocidades,
	estados de acción y inputs residuales.
	"""
	print("[PlayerController] reset_state_for_respawn called with position: ", new_transform.origin, " yaw: ", rad2deg(new_transform.basis.get_euler().y))
	# 1. Establecer nueva posición y orientación
	global_transform = new_transform
	print("[PlayerController] global_transform set to: ", global_transform.origin)

	# 1.5. Resetear rotación del mesh para que mire forward
	print("[PlayerController] player_mesh: ", player_mesh)
	if player_mesh:
		# La rotación del cuerpo (KinematicBody) ya se establece con global_transform.
		# El mesh, al ser un nodo hijo, solo necesita su offset de rotación local.
		player_mesh.rotation.y = mesh_yaw_offset
		print("[PlayerController] player_mesh.rotation.y set to offset: ", player_mesh.rotation.y)

	# 2. Resetear orientación de la cámara
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig:
		# La causa de los problemas es el bucle de suavizado en PlayerSpringCam.gd,
		# que revierte los cambios si no se actualiza su `target_yaw`.
		# La función sync_to_body_yaw() lo hace, pero falla en respawn por razones de estado.
		# La solución es una reimplementación manual y directa aquí.
		var yaw_node = cam_rig.get_node_or_null("Yaw")
		if yaw_node and cam_rig.has_method("set"):
			# El rig de la cámara se alinea con el cuerpo. Se asume que el SpringArm maneja la posición "detrás".
			var final_cam_yaw = new_transform.basis.get_euler().y + PI
			
			# 1. Establecer la rotación del nodo directamente
			yaw_node.rotation.y = final_cam_yaw
			
			# 2. Establecer el OBJETIVO del suavizado para que no revierta el cambio
			cam_rig.set("target_yaw", final_cam_yaw)

			# 3. Resetear el pitch de la misma forma
			var pitch_node = yaw_node.get_node_or_null("Pitch")
			if pitch_node:
				pitch_node.rotation.x = 0.0
				cam_rig.set("target_pitch", 0.0)
			
			print("[PlayerController] Manually reset camera yaw, target_yaw, and pitch.")
		else:
			print("[PlayerController] CameraRig or Yaw node not found, or it's not a script.")

	# 3. Resetear input residual del mouse
	if is_instance_valid(player_input) and player_input.has_method("reset_mouse_motion"):
		player_input.reset_mouse_motion()
		print("[PlayerController] player_input.reset_mouse_motion() called")

	# 4. Resetear velocidades y estado de movimiento
	if has_node("GroundRay"):
		$GroundRay.force_raycast_update()
		print("[PlayerController] GroundRay force_raycast_update called")
	horizontal_velocity = Vector3.ZERO
	vertical_velocity = Vector3.ZERO
	platform_velocity = Vector3.ZERO
	last_platform_velocity = Vector3.ZERO
	airborne_inherited = Vector3.ZERO
	print("[PlayerController] velocities reset to ZERO")
	
	# Resetea la dirección de movimiento para que el personaje no intente moverse.
	# La orientación del cuerpo ya está establecida por global_transform.
	direction = Vector3.ZERO
	print("[PlayerController] direction reset to ZERO")
	if is_instance_valid(movement_comp):
		movement_comp.direction = Vector3.ZERO
		movement_comp.horizontal_velocity = Vector3.ZERO
		print("[PlayerController] movement_comp.direction and horizontal_velocity reset")

	# 5. Limpiar flags de acción
	is_rolling = false
	is_attacking = false
	just_jumped = false
	snap_enabled = true
	print("[PlayerController] action flags reset (is_rolling, is_attacking, just_jumped, snap_enabled)")

func _string_to_vector3(s: String) -> Vector3:
	s = s.trim_prefix("(").trim_suffix(")")
	var parts = s.split(",")
	if parts.size() == 3:
		return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return Vector3.ZERO

func _string_to_transform(s: String) -> Transform:
	s = s.trim_prefix("(").trim_suffix(")")
	var parts = s.split(",")
	if parts.size() == 12:
		var basis_x = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		var basis_y = Vector3(float(parts[3]), float(parts[4]), float(parts[5]))
		var basis_z = Vector3(float(parts[6]), float(parts[7]), float(parts[8]))
		var origin = Vector3(float(parts[9]), float(parts[10]), float(parts[11]))
		return Transform(Basis(basis_x, basis_y, basis_z), origin)
	return Transform.IDENTITY

func get_replay_state() -> Dictionary:
	# This function should return raw Godot types.
	# The ReplayRecorder is responsible for converting them to a JSON-safe format.
		
	var state = {
		"global_transform": ReplayUtils.transform_to_dict(global_transform),
		"player_position": ReplayUtils.vector3_to_dict(global_transform.origin),
		"platform_velocity": ReplayUtils.vector3_to_dict(platform_velocity),
		"airborne_inherited": ReplayUtils.vector3_to_dict(airborne_inherited),
		"just_jumped": just_jumped,
		"time_since_jump": time_since_jump,
		"time_since_input": time_since_input,
		"velocity": ReplayUtils.vector3_to_dict(velocity), # Record the final velocity AFTER move_and_slide
		"pre_move_velocity": ReplayUtils.vector3_to_dict(pre_move_velocity_for_replay),
		"calculated_direction": ReplayUtils.vector3_to_dict(direction),
	}
	if jump_comp:
		state["coyote_timer"] = jump_comp.coyote_timer
		state["jump_buffer_timer"] = jump_comp.jump_buffer_timer
		state["should_jump_buffered"] = jump_comp.should_jump_buffered
	return state

func set_replay_state(state: Dictionary) -> void:
	var deserialized_state = ReplayUtils.from_json_safe(state)

	# Restore state from the replay file
	global_transform = deserialized_state.get("global_transform", global_transform)
	platform_velocity = deserialized_state.get("platform_velocity", platform_velocity)
	airborne_inherited = deserialized_state.get("airborne_inherited", Vector3.ZERO)
	just_jumped = deserialized_state.get("just_jumped", false)
	time_since_jump = deserialized_state.get("time_since_jump", 1.0)
	time_since_input = deserialized_state.get("time_since_input", 1.0)

	# Restore the final velocity from the initial state.
	velocity = deserialized_state.get("velocity", Vector3.ZERO)
	horizontal_velocity = velocity - Vector3(0, velocity.y, 0)
	vertical_velocity.y = velocity.y

	if jump_comp and deserialized_state.has("coyote_timer") and deserialized_state["coyote_timer"] != null:
		jump_comp.coyote_timer = deserialized_state["coyote_timer"]
	if jump_comp and deserialized_state.has("jump_buffer_timer") and deserialized_state["jump_buffer_timer"] != null:
		jump_comp.jump_buffer_timer = deserialized_state["jump_buffer_timer"]
	if jump_comp and deserialized_state.has("should_jump_buffered") and deserialized_state["should_jump_buffered"] != null:
		jump_comp.should_jump_buffered = deserialized_state["should_jump_buffered"]
