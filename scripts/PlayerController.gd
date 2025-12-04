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
export var walk_speed = 1.3
export var run_speed = 5.5
export var dash_power = 12
# --- JOYPAD ANALÓGICO (curvas como en Cursor.gd) ---
export (float, 0.0, 1.0) var joystick_deadzone := 0.12
enum JoystickCurveType { LINEAR, EXPONENTIAL, INVERSE_S }
export (JoystickCurveType) var joystick_curve_type = JoystickCurveType.EXPONENTIAL
export (float, 0.0, 1.0) var analog_run_threshold := 0.7
# Debe ser var para Godot 3.x
var _CURVE_RESOURCES = [
	load("res://data/Curves/Linear.tres"),
	load("res://data/Curves/Exponential.tres"),
	load("res://data/Curves/Inverse_S.tres")
]


# Velocidad externa aplicada por plataformas/conveyors
var platform_velocity := Vector3.ZERO
var platform_is_static_surface := false
export var snap_len := 0.5
var snap_enabled := true
export var debug_movement := false
export var debug_shadow := false
export var debug_input := false
export var debug_enabled := false # bandera global para desactivar todos los logs por defecto
var _debug_accum := 0.0
var last_platform_velocity := Vector3.ZERO
var airborne_inherited := Vector3.ZERO
var was_on_floor := false
export var max_platform_up_follow := 5.0
export var inherit_vertical_platform_jump := true
var just_jumped := false
var time_since_jump := 1.0
var time_since_input := 1.0
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
var is_walking = false
var is_running = false
var is_aiming = false

var direction = Vector3()
var horizontal_velocity = Vector3()
var aim_turn = 0.0
var movement = Vector3()
var vertical_velocity = Vector3()
var movement_speed = 0
var angular_acceleration = 10
var acceleration = 15
export(float, 0.0, 10.0, 0.1) var tank_turn_speed := 0.3
export(float, 0.0, 10.0, 0.1) var advancing_turn_speed := 0.3
export(float, 0.001, 0.1, 0.001) var mouse_aim_sensitivity := 0.015
# --- Suavizado opcional de yaw de cuerpo + sync de cámara periódica ---
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
var _last_anim_node := ""
var _last_is_floating := false
var has_seen_floor_once := false
var time_since_start := 0.0
export var startup_floating_block_time := 0.6

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
	platform_velocity = v

func _ready():
	# Alinear dirección inicial con el frente del mesh y la cámara
	var yaw_node = get_node_or_null("CameraRig/Yaw")
	var yaw_angle := 0.0
	if yaw_node:
		yaw_angle = yaw_node.global_transform.basis.get_euler().y + cam_yaw_offset
	# Usar frente del mesh para coherencia de animación al inicio
	direction = Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
	# ERROR! : direction = Vector3.FORWARD.rotated(Vector3.UP, player_mesh.rotation.y)
	# Si la cámara existe, rotar la dirección por su yaw para entrada relativa a cámara
	direction = direction.rotated(Vector3.UP, yaw_angle)
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
	
	var fps_label = Label.new()
	fps_label.name = "FPSLabel"
	add_child(fps_label)
	
func set_external_source_is_static(is_static: bool) -> void:
	platform_is_static_surface = is_static

func _input(event):
	if event is InputEventMouseMotion:
		aim_turn = -event.relative.x * mouse_aim_sensitivity
	#if event is InputEventJoypadMotion:
	#	print(event)
	#	aim_turn = -event.axis_value * mouse_aim_sensitivity
	if event.is_action_pressed("aim"):
		# Al entrar en aim, sincronizar cámara con el cuerpo usando el offset
		var cam_rig = get_node_or_null("CameraRig")
		if cam_rig and cam_rig.has_method("sync_to_body_yaw"):
			cam_rig.sync_to_body_yaw(rotation.y, cam_yaw_offset)
		direction = $CameraRig/Yaw.global_transform.basis.z
	if event.is_action_released("aim"):
		# Al salir de aim, asegurar que el mesh y la cámara sigan el cuerpo con sus offsets
		player_mesh.rotation.y = rotation.y + mesh_yaw_offset

func _process(delta):
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

	if Input.is_action_just_pressed("jump") and ((is_attacking != true) and (is_rolling != true)) and is_on_floor():
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

	var has_input := (Input.is_action_pressed("forward") || Input.is_action_pressed("backward") || Input.is_action_pressed("left") || Input.is_action_pressed("right") || Input.is_action_pressed("cursor_up") || Input.is_action_pressed("cursor_down") || Input.is_action_pressed("cursor_left") || Input.is_action_pressed("cursor_right"))
	# Estado de aim (mantener mientras se presiona; usar push/release del sistema de Input)
	is_aiming = Input.is_action_pressed("aim")
	if has_input and not is_aiming:
		time_since_input = 0.0
		# Construir vector analógico desde acciones y aplicar deadzone + curva
		var ax := (Input.get_action_strength("left") - Input.get_action_strength("right")) + (Input.get_action_strength("cursor_left") - Input.get_action_strength("cursor_right"))
		var az := (Input.get_action_strength("forward") - Input.get_action_strength("backward")) + (Input.get_action_strength("cursor_down") - Input.get_action_strength("cursor_up"))
		var v2 := Vector2(ax, az)
		var mag := v2.length()
		var processed_mag := 0.0
		var processed_dir := Vector2.ZERO
		if mag > joystick_deadzone:
			processed_dir = v2.normalized()
			var curve: Curve = _CURVE_RESOURCES[joystick_curve_type]
			processed_mag = curve.interpolate(clamp(mag, 0.0, 1.0))
			# Reescalar por fuera de la zona muerta (opcional, simple)
			processed_mag = clamp(processed_mag, 0.0, 1.0)
		# Si no supera deadzone, tratamos como sin input real
		if processed_mag <= 0.0:
			is_walking = false
			is_running = false
			movement_speed = 0.0
			# Evitar acumulación de giro: sin input, no perseguir dirección previa
			direction = Vector3.ZERO
		else:
			# Tank Controls cuando no hay componente de avance/retroceso
			if abs(processed_dir.y) < 0.001 and abs(ax) > joystick_deadzone:
				is_tank_turning = (tank_turn_speed > 0.0)
				if is_tank_turning:
					var delta_yaw = ax * tank_turn_speed * delta  # Use raw ax for analog turn
					# Rotar únicamente el cuerpo; la cámara no debe sumar yaw aquí
					rotation.y += delta_yaw
				# player_mesh.rotation.y = rotation.y + mesh_yaw_offset
				# Sin movimiento en tank turn
				is_walking = false
				is_running = false
				movement_speed = 0.0
				direction = Vector3.ZERO
				# Frenar hv inmediatamente para evitar desplazamiento fantasma
				horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, 120.0 * delta)
			else:
				is_tank_turning = false
				# Movimiento normal: proyectar el input en el espacio de la cámara (Yaw) for digital, tank for analog
				if processed_mag < 1.0:
					# Tank controls for joystick
					var forward_input = processed_dir.y
					var turn_input = ax  # Raw for analog turn speed
					if abs(turn_input) > joystick_deadzone:
						rotation.y += turn_input * tank_turn_speed * delta
					direction = Vector3.FORWARD.rotated(Vector3.UP, rotation.y) * forward_input
					is_walking = abs(forward_input) > 0.0
					if Input.is_action_pressed("sprint") or abs(forward_input) > analog_run_threshold:
						movement_speed = run_speed
						is_running = true
					else:
						movement_speed = walk_speed
						is_running = false
					movement_speed *= abs(forward_input)
				else:
					# Relative to camera for digital (WASD)
					var basis := Basis()
					var yaw_node_local = get_node_or_null("CameraRig/Yaw")
					if yaw_node_local:
						basis = yaw_node_local.global_transform.basis
					var cam_forward := basis.z.normalized()
					var cam_right := basis.x.normalized()
					var forward_input := processed_dir.y
					var right_input := processed_dir.x
					if swap_input_axes:
						var tmp := forward_input
						forward_input = right_input
						right_input = tmp
					if invert_forward:
						forward_input = -forward_input
					var dir3 := (cam_forward * forward_input) + (cam_right * right_input)
					direction = dir3.normalized()
					# Giro adicional al estar avanzando
					if abs(right_input) > 0.0 and abs(forward_input) > 0.0:
						direction = direction.rotated(Vector3.UP, right_input * advancing_turn_speed * delta)
					is_walking = true
					# Sprint/walk SOLO si estamos caminando
					if Input.is_action_pressed("sprint") or (processed_mag > analog_run_threshold and processed_mag < 1.0):
						movement_speed = run_speed
						is_running = true
					else:
						movement_speed = walk_speed
						is_running = false
					# Escalar la velocidad objetivo por la magnitud analógica (0..1)
					movement_speed *= processed_mag
	else:
		is_walking = false
		is_running = false
		is_tank_turning = false
		direction = Vector3.ZERO

	# Sin suavizados ni sincronizaciones periódicas de yaw: mantener determinismo

	# El mesh solo rota hacia la dirección de input relativa a la cámara cuando hay input
	if not is_aiming and direction != Vector3.ZERO:
		# Calcula el ángulo objetivo SOLO respecto al basis de la cámara (Yaw), nunca por cambios automáticos
		var target_y := atan2(direction.x, direction.z) + mesh_yaw_offset
		# Para evitar doble giro, calcula la rotación local necesaria para que la rotación global sea target_y
		var global_target_y = target_y
		var parent_y = rotation.y  # rotación del KinematicBody (padre)
		var local_target_y = global_target_y - parent_y
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, local_target_y, delta * angular_acceleration)
		# ...existing code de debug YawAlign...
	# Si no hay input, NO forzar rotación del mesh (mantiene la última orientación)
	# Interpolación de hv hacia la velocidad objetivo
	if ((is_attacking == true) or (is_rolling == true)):
		horizontal_velocity = horizontal_velocity.linear_interpolate(direction.normalized() * .01 , acceleration * delta)
	else:
		var target_speed = movement_speed
		var target_accel = acceleration
		horizontal_velocity = horizontal_velocity.linear_interpolate(direction.normalized() * target_speed, target_accel * delta)
	# ...existing code...

	# Fricción fuerte: si no hay input o si está en aim (bloqueo movimiento) y estamos en suelo
	if (not has_input or is_aiming) and is_on_floor() and not is_attacking and not is_rolling:
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
func reset_state_for_respawn():
	if has_node("GroundRay"):
		$GroundRay.force_raycast_update()
	# Zero transient velocities and external inputs
	if "horizontal_velocity" in self:
		horizontal_velocity = Vector3.ZERO
	if "vertical_velocity" in self:
		vertical_velocity = Vector3.ZERO
	if "platform_velocity" in self:
		platform_velocity = Vector3.ZERO
	if "last_platform_velocity" in self:
		last_platform_velocity = Vector3.ZERO
	
	# Clear action flags
	if "is_aiming" in self:
		is_aiming = false
	if "is_rolling" in self:
		is_rolling = false
	if "is_attacking" in self:
		is_attacking = false
	""" 
	TODO: CONFIRM UNEEDED?
	# Ensure AnimationTree reflects grounded state next frame
	if has_node("AnimationTree"):
		var at = $PilotMesh/AnimationTree
		
		if at.has_parameter("conditions/IsOnFloor"):
			at.set("parameters/conditions/IsOnFloor", is_on_floor())
		if at.has_parameter("conditions/IsInAir"):
			at.set("parameters/conditions/IsInAir", !is_on_floor())
		if at.has_parameter("conditions/IsFloating"):
			at.set("parameters/conditions/IsFloating", false)
	"""
