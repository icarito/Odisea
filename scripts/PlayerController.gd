extends KinematicBody

# Placeholder: controlador de Elías basado en PlayerTemplate
# Nota: Se moverá lógica avanzada y referencias de animación conforme al refactor

export (NodePath) var PlayerAnimationTree 
export onready var animation_tree = get_node(PlayerAnimationTree)
onready var playback = animation_tree.get("parameters/playback")

export (NodePath) var PlayerCharacterMesh
export onready var player_mesh = get_node(PlayerCharacterMesh)

export var gravity = 9.8
export var jump_force = 9
export var dash_power = 12

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
var movement = Vector3()
var vertical_velocity = Vector3()

var angular_acceleration = 10
export(float, 0.0, 10.0, 0.1) var tank_turn_speed := 0.3
export(float, 0.0, 10.0, 0.1) var advancing_turn_speed := 0.3
export(float, 0.0, 1.0, 0.01) var analog_turn_multiplier := 1.0
export(float, 0.0, 1.0, 0.01) var sprint_threshold := 0.7
export(float, 0.001, 0.1, 0.001) var mouse_aim_sensitivity := 0.015
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
	# If this scene is being run directly, switch to the test scene
	# This check is to allow testing the player scene directly.
	# It changes to a test scene only if the player's scene file is the one being run.
	if owner and owner == get_tree().current_scene:
		get_tree().change_scene("res://players/TestScene.tscn")
		return # Stop further execution of _ready


	# Connect to GameGlobals for debug mode
	if GameGlobals:
		debug_enabled = GameGlobals.debug_mode
		GameGlobals.connect("debug_mode_changed", self, "_on_debug_mode_changed")

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

func _input(event):
	# Capturar movimiento del mouse solo si el PlayerInput de este jugador está configurado para usarlo.
	if player_input and player_input.use_mouse_input and event is InputEventMouseMotion:
		# En lugar de pasarlo a una variable 'aim_turn' que no se usa,
		# lo pasamos directamente al componente de input para que lo procese.
		player_input.mouse_motion += event.relative

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

var _last_input_state := {}

func _physics_process(delta):
	rollattack()
	bigattack()
	attack1()
	attack2()
	roll()

	# Timers de gracia
	time_since_jump += delta
	time_since_input += delta
	time_since_start += delta

	# Medir tiempo en estado Jump del AnimationTree
	var in_jump_state = (playback and (playback.get_current_node() == jump_node_name))
	if in_jump_state:
		time_in_jump_state += delta
	else:
		time_in_jump_state = 0.0

	var on_floor = is_on_floor()
	# Debug de cambios de estado de suelo
	if debug_enabled and debug_movement and debug_ready:
		# no consumir el debounce, solo detectar cambios de on_floor
		if on_floor != was_on_floor:
			print_debug_tag("Floor", "[Floor] on_floor changed: " + String(on_floor))
	# Marcar que vimos suelo al menos una vez para habilitar floating post-inicio
	if on_floor:
		has_seen_floor_once = true
	var h_rot := 0.0
	var yaw_node2 = get_node_or_null("CameraRig/Yaw")
	if yaw_node2:
		h_rot = yaw_node2.global_transform.basis.get_euler().y + cam_yaw_offset

	movement_speed = 0
	angular_acceleration = 10
	acceleration = 15

	# Gravedad efectiva: usar override si existe
	var effective_gravity_vector := local_gravity_override if (local_gravity_override.length() > 0.01) else (Vector3.DOWN * gravity)
	var effective_gravity_mag := effective_gravity_vector.length()
	var effective_gravity_dir := effective_gravity_vector.normalized() if (effective_gravity_mag > 0.01) else Vector3.DOWN

	if not is_on_floor():
		vertical_velocity += effective_gravity_vector * 2 * delta
	else:
		# Si la gravedad efectiva apunta hacia arriba (levanta), despegar del suelo
		if effective_gravity_dir.dot(Vector3.UP) > 0.5:
			# Deshabilitar snap un frame para permitir despegue
			snap_enabled = false
			# Aplicar leve impulso en dirección de la "levitación" para separar del suelo
			vertical_velocity = effective_gravity_dir * min(effective_gravity_mag, gravity) * 0.5
		else:
			vertical_velocity = -get_floor_normal() * min(effective_gravity_mag, gravity) / 3

	# Clamp de velocidad vertical para evitar picos (como antes)
	vertical_velocity.y = clamp(vertical_velocity.y, -max_fall_speed, max_rise_speed)

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

	var input_vector := Vector2.ZERO
	var mouse_motion := Vector2.ZERO
	var is_sprinting := false
	var jump_pressed := false
	var has_input := false

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
		# Note: Mouse motion is not handled in this fallback, it relies on PlayerInput node.
	
	has_input = input_vector.length() > 0.1

	if jump_pressed and ((is_attacking != true) and (is_rolling != true)) and is_on_floor():
		# Play jump sound
		if AudioSystem:
			# NOTE: Path to jump sound is a placeholder.
			AudioSystem.play_sfx("res://assets/sfx/jump.wav")

		# Capturamos velocidad actual de plataforma justo en el momento del salto (antes de posible decaimiento)
		var pv := platform_velocity
		# Fuerza de salto base
		vertical_velocity = Vector3.UP * jump_force
		# Opcional: añadir componente vertical de la plataforma si está moviéndose hacia arriba
		if inherit_vertical_platform_jump and pv.y > 0.0:
			vertical_velocity.y += min(pv.y, max_platform_up_follow)
		# Al saltar, no usamos snap este frame
		snap_enabled = false
		# Heredar inercia horizontal de la plataforma (X,Z) para conservar momentum relativo
		airborne_inherited = Vector3(pv.x, 0, pv.z)
		# Aplicar inmediatamente para que el primer frame en aire no pierda empuje
		horizontal_velocity += airborne_inherited
		# Marcar frame de salto para evitar que seguimiento vertical de plataforma lo anule
		just_jumped = true
		time_since_jump = 0.0

	if has_input:
		time_since_input = 0.0

	# --- Control de Cámara ---
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig:
		if cam_rig.has_method("process_camera_rotation"):
			cam_rig.process_camera_rotation(mouse_motion)
			if debug_yaw and mouse_motion.length_squared() > 0:
				print_debug_tag("Yaw", "[Controller] Passing mouse_motion to cam: %s" % mouse_motion)
		
		# --- Tank Turn y Sincronización de Cámara ---
		# Procesar movimiento con componente
		if movement_comp:
			var basis := Basis()
			var yaw_node_local = get_node_or_null("CameraRig/Yaw")
			if yaw_node_local:
				basis = yaw_node_local.global_transform.basis

			movement_comp.process_input_vector(delta, basis, input_vector, is_sprinting)
			
			# Aplicar giro tank (restaurado)
			var turn_input = movement_comp.get_turn_input_from_vector(input_vector)
			var yaw_delta = turn_input * tank_turn_speed * delta
			rotation.y += yaw_delta
			
			# Sincronizar cámara con el giro del player
			if cam_rig.has_method("apply_external_yaw_delta"):
				cam_rig.apply_external_yaw_delta(yaw_delta)
	
			# Obtener valores del componente
			direction = movement_comp.direction
			horizontal_velocity = movement_comp.get_horizontal_velocity()
			is_walking = movement_comp.is_walking
			is_running = movement_comp.is_running
		else:
			is_walking = false
			is_running = false
			direction = Vector3.ZERO
			horizontal_velocity = Vector3.ZERO


	# Sin suavizados ni sincronizaciones periódicas de yaw: mantener determinismo

	# El mesh rota hacia la dirección de movimiento cuando hay input
	if direction != Vector3.ZERO:
		# Calcula el ángulo objetivo respecto al basis de la cámara
		var target_y := atan2(direction.x, direction.z) + mesh_yaw_offset
		# Para evitar doble giro, calcula la rotación local necesaria
		var global_target_y = target_y
		var parent_y = rotation.y  # rotación del KinematicBody (padre)
		var local_target_y = global_target_y - parent_y
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, local_target_y, delta * angular_acceleration)
	# Interpolación de hv hacia la velocidad objetivo
	horizontal_velocity = movement_comp.horizontal_velocity
	# ...existing code...

	# Fricción fuerte: si no hay input y estamos en suelo
	if not has_input and is_on_floor() and not is_attacking and not is_rolling:
		horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, 60.0 * delta)

	# Decaimiento de la velocidad de plataforma cuando no se actualiza
	platform_velocity = platform_velocity.linear_interpolate(Vector3.ZERO, 6.0 * delta)

	# Capturar velocidad de plataforma SOLO mientras estamos en suelo para heredar al saltar / caer
	if is_on_floor():
		last_platform_velocity = platform_velocity
		airborne_inherited = Vector3.ZERO
		# Ajuste vertical: seguir plataforma si sube para evitar empuje por colisión
		if platform_velocity.y > 0.0 and not just_jumped:
			vertical_velocity.y = min(platform_velocity.y, max_platform_up_follow)
	else:
		# Primera frame en aire: hereda última velocidad de plataforma
		if was_on_floor:
			airborne_inherited = last_platform_velocity

	# Combinar velocidad propia con la transferida por la plataforma
	# En suelo: sumar componente horizontal de platform_velocity (requerido para conveyors)
	# En aire: usar la última velocidad capturada para conservar inercia
	var effective_platform_velocity := (Vector3(platform_velocity.x, 0, platform_velocity.z) if (is_on_floor() and platform_is_static_surface) else airborne_inherited)
	var combined_horizontal = horizontal_velocity + effective_platform_velocity
	movement.z = combined_horizontal.z + vertical_velocity.z
	movement.x = combined_horizontal.x + vertical_velocity.x
	movement.y = vertical_velocity.y

	if debug_enabled and (debug_movement or debug_yaw):
		var dir_change2 = (direction - _last_dir).length()
		if dir_change2 > debug_dir_threshold:
			_last_dir = direction
			print_debug_tag("Dir", "[Dir] dir=" + String(direction) +
		" cam_yaw=" + String(h_rot).pad_decimals(3) +
		" hv=" + String(horizontal_velocity) +
		" eff_pv=" + String(effective_platform_velocity) +
		" combined=" + String(combined_horizontal))

	# Snap al suelo para estabilidad en plataformas
	var snap_vec := Vector3.ZERO
	if is_on_floor() and snap_enabled:
		snap_vec = Vector3.DOWN * snap_len
	else:
		snap_vec = Vector3.ZERO
		# Rehabilitar snap cuando volvamos a tocar suelo
		if is_on_floor():
			snap_enabled = true

	move_and_slide_with_snap(movement, snap_vec, Vector3.UP, false)
	was_on_floor = is_on_floor()
	# Resetear bandera tras aplicar movimiento (un solo frame de protección)
	just_jumped = false

	# --- Sombra falsa ---
	if ground_ray.is_colliding():
		var hit = ground_ray.get_collision_point()
		var collider = ground_ray.get_collider()
		var dist = global_transform.origin.y - hit.y
		# Posición
		fake_shadow.global_transform.origin = Vector3(hit.x, hit.y + 0.01, hit.z)
		# Escala dependiente de distancia al suelo (clamp para prototipo)
		var s = clamp(0.6 + dist * 0.4, 0.5, 2.0)
		fake_shadow.scale = Vector3(s, 1.0, s)
		# Opacidad simple: más transparente si está alto
		var mat = fake_shadow.get_surface_material(0)
		if mat:
			var alpha = clamp(1.0 - dist * 0.4, 0.2, 0.9)
			mat.albedo_color.a = alpha
		fake_shadow.visible = true
		if debug_enabled and debug_shadow and debug_ready:
			var mat_alpha := 0.0
			var mat2 = fake_shadow.get_surface_material(0)
			if mat2:
				mat_alpha = mat2.albedo_color.a
			var cname = (collider.name if collider and collider.has_method("get_name") else "?")
			print_debug_tag("Shadow", "[Shadow] hit=" + String(hit) + " dist=" + String(dist).pad_decimals(2) +
				" alpha=" + String(mat_alpha).pad_decimals(2) + " collider_name=" + cname)
	else:
		fake_shadow.visible = false
		if debug_enabled and debug_shadow and debug_ready:
			print_debug_tag("Shadow", "[Shadow] no collision. mask=" + String(ground_ray.collision_mask))

	if debug_enabled and debug_movement and debug_ready:
		var eff_pv := (Vector3(platform_velocity.x, 0, platform_velocity.z) if (on_floor and platform_is_static_surface) else airborne_inherited)
		print_debug_tag("Move", "[Move] hv=" + String(horizontal_velocity) + " pv=" + String(platform_velocity) +
			" eff_pv=" + String(eff_pv) + " combined=" + String(combined_horizontal) +
			" airborne_inherited=" + String(airborne_inherited) + " has_input=" + String(has_input) +
			" on_floor=" + String(on_floor) + " platform_is_static=" + String(platform_is_static_surface))

	animation_tree["parameters/conditions/IsOnFloor"] = on_floor
	animation_tree["parameters/conditions/IsInAir"] = !on_floor
	animation_tree["parameters/conditions/IsWalking"] = is_walking
	animation_tree["parameters/conditions/IsNotWalking"] = !is_walking
	animation_tree["parameters/conditions/IsRunning"] = is_running
	animation_tree["parameters/conditions/IsNotRunning"] = !is_running

	# Estado de flotación: condición para "Swim_Idle_Loop" gestionada por el State Machine
	# Suavizado de aceleración vertical para decisión de flotación
	var v_accel := 0.0
	if delta > 0.0:
		v_accel = (vertical_velocity.y - _prev_vy) / delta
	_prev_vy = vertical_velocity.y
	_vaccel_smoothed = lerp(_vaccel_smoothed, v_accel, clamp(floating_accel_smooth, 0.0, 1.0))
	var vertical_accel := abs(_vaccel_smoothed)
	var falling_without_jump = (!on_floor) and (time_since_jump > floating_without_jump_delay)
	var no_input_ok := (not floating_without_jump_requires_no_input) or (time_since_input > floating_no_input_delay)
	# Histeresis basada en aceleración vertical: entrada/salida separadas
	var accel_ok_enter := vertical_accel <= floating_enter_accel_threshold
	var accel_ok_exit := vertical_accel <= floating_exit_accel_threshold
	var accel_ok := (_last_is_floating and accel_ok_exit) or ((not _last_is_floating) and accel_ok_enter)

	# Fallback específico para "caer sin salto": si la aceleración es alta por gravedad constante,
	# permitimos flotación cuando la velocidad vertical es baja (p.ej., cerca del apogeo o en corrientes suaves)
	var vertical_speed_raw := abs(vertical_velocity.y)
	_vspeed_smoothed = lerp(_vspeed_smoothed, vertical_speed_raw, clamp(floating_vspeed_smooth, 0.0, 1.0))
	var vertical_speed := _vspeed_smoothed
	var vspeed_ok_enter := vertical_speed < floating_enter_vspeed_threshold
	var vspeed_ok_exit := vertical_speed < floating_exit_vspeed_threshold
	var vspeed_ok := (_last_is_floating and vspeed_ok_exit) or ((not _last_is_floating) and vspeed_ok_enter)
	# Bloqueo de floating en inicio hasta ver suelo o pasar un tiempo
	var startup_block_clear := has_seen_floor_once or (time_since_start > startup_floating_block_time)
	var should_float = startup_block_clear and (!on_floor) and (accel_ok or (falling_without_jump and vspeed_ok)) and (not is_attacking) and (not is_rolling) and (
		((time_since_jump > floating_after_jump_delay) and (time_since_input > floating_no_input_delay))
		or (time_in_jump_state > floating_from_jump_delay)
		or (falling_without_jump and no_input_ok)
	)
	animation_tree["parameters/conditions/IsFloating"] = should_float

	# Log de flotar solo en cambios
	if debug_enabled and debug_movement and (should_float != _last_is_floating):
		print_debug_tag("Float", "[Float] is_floating changed: " + String(should_float) +
			" v_accel=" + String(vertical_accel).pad_decimals(2) +
			" a_enter=" + String(floating_enter_accel_threshold) +
			" a_exit=" + String(floating_exit_accel_threshold) +
			" v_speed=" + String(vertical_speed).pad_decimals(2) +
			" v_enter=" + String(floating_enter_vspeed_threshold) +
			" v_exit=" + String(floating_exit_vspeed_threshold) +
			" on_floor=" + String(on_floor))
	_last_is_floating = should_float

	# Debug de estados y condiciones
	if debug_enabled and debug_movement:
		var current_node := "?"
		if playback:
			current_node = String(playback.get_current_node())
		if current_node != _last_anim_node:
			_last_anim_node = current_node
			print_debug_tag("Anim", "[Anim] node=" + current_node +
				" on_floor=" + String(on_floor) +
				" is_walking=" + String(is_walking) +
				" is_running=" + String(is_running) +
				" is_attacking=" + String(is_attacking) +
				" is_rolling=" + String(is_rolling) +
				" is_floating=" + String(should_float) +
				" v_accel=" + String(vertical_accel).pad_decimals(2) +
				" v_speed=" + String(vertical_speed).pad_decimals(2) +
				" t_jump=" + String(time_since_jump).pad_decimals(2) +
				" t_input=" + String(time_since_input).pad_decimals(2) +
				" t_jump_state=" + String(time_in_jump_state).pad_decimals(2) +
				" fall_no_jump=" + String(falling_without_jump) +
				" no_input_ok=" + String(no_input_ok))

# Respawn-safe reset of transient movement state
func reset_state_for_respawn(new_transform: Transform) -> void:
	"""
	Resetea completamente el estado del jugador para un respawn.
	Establece la nueva posición/rotación y limpia todas las velocidades,
	estados de acción y inputs residuales.
	"""
	print("PlayerController: Resetting state for respawn, position: ", new_transform.origin, " yaw: ", rad2deg(new_transform.basis.get_euler().y))
	# 1. Establecer nueva posición y orientación
	global_transform = new_transform

	# 1.5. Resetear rotación del mesh para que mire forward
	print (player_mesh)
	if player_mesh:
		player_mesh.rotation = Vector3.ZERO

	# 2. Resetear orientación de la cámara
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig and cam_rig.has_method("sync_to_body_yaw"):
		# El yaw de la cámara debe alinearse con la nueva rotación del cuerpo
		cam_rig.sync_to_body_yaw(new_transform.basis.get_euler().y, cam_rig.cam_yaw_offset)
		print("PlayerController: Synced camera yaw to: ", rad2deg(new_transform.basis.get_euler().y))

	# 3. Resetear input residual del mouse
	if is_instance_valid(player_input) and player_input.has_method("reset_mouse_motion"):
		player_input.reset_mouse_motion()

	# 4. Resetear velocidades y estado de movimiento
	if has_node("GroundRay"):
		$GroundRay.force_raycast_update()
	horizontal_velocity = Vector3.ZERO
	vertical_velocity = Vector3.ZERO
	platform_velocity = Vector3.ZERO
	last_platform_velocity = Vector3.ZERO
	airborne_inherited = Vector3.ZERO

	# 5. Limpiar flags de acción
	is_rolling = false
	is_attacking = false
	just_jumped = false
	snap_enabled = true
