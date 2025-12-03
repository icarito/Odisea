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
var debug_timer = Timer.new()
var debug_ready: bool = true
var _last_anim_node := ""
var _last_is_floating := false
var has_seen_floor_once := false
var time_since_start := 0.0
export var startup_floating_block_time := 0.6

onready var ground_ray: RayCast = $GroundRay
onready var fake_shadow: MeshInstance = $Pilot/FakeShadow

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
	direction = Vector3.BACK.rotated(Vector3.UP, $Camroot/h.global_transform.basis.get_euler().y)
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

	
func set_external_source_is_static(is_static: bool) -> void:
	platform_is_static_surface = is_static

func _input(event):
	if event is InputEventMouseMotion:
		aim_turn = -event.relative.x * 0.015
	if event is InputEventJoypadMotion:
		aim_turn = -event.relative.x * 0.015
	if event.is_action_pressed("aim"):
		direction = $Camroot/h.global_transform.basis.z

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
	if debug_movement and debug_ready:
		# no consumir el debounce, solo detectar cambios de on_floor
		if on_floor != was_on_floor:
			print("[Floor] on_floor changed:", on_floor)
	# Marcar que vimos suelo al menos una vez para habilitar floating post-inicio
	if on_floor:
		has_seen_floor_once = true
	var h_rot = $Camroot/h.global_transform.basis.get_euler().y

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

	var has_input := (Input.is_action_pressed("forward") ||  Input.is_action_pressed("backward") ||  Input.is_action_pressed("left") ||  Input.is_action_pressed("right"))
	# Estado de aim (mantener mientras se presiona; usar push/release del sistema de Input)
	is_aiming = Input.is_action_pressed("aim")
	if has_input and not is_aiming:
		time_since_input = 0.0
		# Construir vector analógico desde acciones y aplicar deadzone + curva
		var ax := Input.get_action_strength("left") - Input.get_action_strength("right")
		var az := Input.get_action_strength("forward") - Input.get_action_strength("backward")
		var v2 := Vector2(ax, az)
		var mag := v2.length()
		var processed_mag := 0.0
		var processed_dir := Vector2.ZERO
		if mag > joystick_deadzone:
			processed_dir = v2.normalized()
			var curve: Curve = _CURVE_RESOURCES[int(joystick_curve_type)]
			processed_mag = curve.interpolate(clamp(mag, 0.0, 1.0))
			# Reescalar por fuera de la zona muerta (opcional, simple)
			processed_mag = clamp(processed_mag, 0.0, 1.0)
		# Si no supera deadzone, tratamos como sin input real
		if processed_mag <= 0.0:
			is_walking = false
			is_running = false
		else:
			var dir3 := Vector3(processed_dir.x, 0.0, processed_dir.y)
			direction = dir3.rotated(Vector3.UP, h_rot).normalized()
			is_walking = true

			if (Input.is_action_pressed("sprint")) and (is_walking == true):
				movement_speed = run_speed
				is_running = true
			else:
				movement_speed = walk_speed
				is_running = false

			# Escalar la velocidad objetivo por la magnitud analógica (0..1)
			movement_speed *= processed_mag

		if (Input.is_action_pressed("sprint")) and (is_walking == true):
			movement_speed = run_speed
			is_running = true
		else:
			movement_speed = walk_speed
			is_running = false
	else:
		is_walking = false
		is_running = false

	# Nota: El movimiento con joypad se gestiona vía acciones de Input mapeadas (forward/backward/left/right).
	# Mientras se mantiene aim, se bloquea el movimiento desde estas acciones para que el joypad controle la cámara.

	# Debug de input: detectar cambios y loguear una línea sintetizada
	if debug_input and debug_ready:
		var snap := _debug_input_snapshot()
		if _last_input_state != snap:
			debug_ready = false
			_last_input_state = snap.duplicate(true)
			print("[Input] L=", snap.left, " R=", snap.right, " F=", snap.forward, " B=", snap.backward,
				" Q=", snap.lookleft, " E=", snap.lookright, " AIM=", snap.aim,
				" SPR=", snap.sprint, " JUMP=", snap.jump, " ATK=", snap.attack, " ROLL=", snap.roll)

	if is_aiming:
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, $Camroot/h.rotation.y, delta * angular_acceleration)
		# Bloquear movimiento mientras se mantiene aim
		direction = Vector3.ZERO
		movement_speed = 0
	else:
		# STRAFE: mientras nos movemos, el personaje mira hacia la cámara
		# En lugar de girar hacia la dirección de movimiento (tank motion),
		# alineamos el mesh con la rotación horizontal de la cámara.
		var cam_y = $Camroot/h.rotation.y
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, cam_y, delta * angular_acceleration)

	if ((is_attacking == true) or (is_rolling == true)):
		horizontal_velocity = horizontal_velocity.linear_interpolate(direction.normalized() * .01 , acceleration * delta)
	else:
		var target_speed = movement_speed
		var target_accel = acceleration
		horizontal_velocity = horizontal_velocity.linear_interpolate(direction.normalized() * target_speed, target_accel * delta)

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
		if debug_shadow and debug_ready:
			debug_ready = false
			var mat_alpha := 0.0
			var mat2 = fake_shadow.get_surface_material(0)
			if mat2:
				mat_alpha = mat2.albedo_color.a
			print("[Shadow] hit=", hit, " dist=", String(dist).pad_decimals(2), " alpha=", String(mat_alpha).pad_decimals(2), " collider_name=",
				(collider.name if collider and collider.has_method("get_name") else "?"))
	else:
		fake_shadow.visible = false
		if debug_shadow and debug_ready:
			debug_ready = false
			print("[Shadow] no collision. mask=", ground_ray.collision_mask)

	if debug_movement and debug_ready:
		debug_ready = false
		var eff_pv := (Vector3(platform_velocity.x, 0, platform_velocity.z) if (on_floor and platform_is_static_surface) else airborne_inherited)
		print("[Move] hv=", horizontal_velocity, " pv=", platform_velocity,
			" eff_pv=", eff_pv,
			" combined=", combined_horizontal,
			" airborne_inherited=", airborne_inherited,
			" has_input=", has_input,
			" on_floor=", on_floor,
			" platform_is_static=", platform_is_static_surface)

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
	if debug_movement and (should_float != _last_is_floating):
		print("[Float] is_floating changed:", should_float, " v_accel=", String(vertical_accel).pad_decimals(2),
			" a_enter=", floating_enter_accel_threshold, " a_exit=", floating_exit_accel_threshold,
			" v_speed=", String(vertical_speed).pad_decimals(2), " v_enter=", floating_enter_vspeed_threshold,
			" v_exit=", floating_exit_vspeed_threshold,
			" on_floor=", on_floor)
	_last_is_floating = should_float

	# Debug de estados y condiciones
	if debug_movement:
		var current_node := "?"
		if playback:
			current_node = String(playback.get_current_node())
		if current_node != _last_anim_node:
			_last_anim_node = current_node
			print("[Anim] node=", current_node,
				" on_floor=", on_floor,
				" is_walking=", is_walking,
				" is_running=", is_running,
				" is_attacking=", is_attacking,
				" is_rolling=", is_rolling,
				" is_floating=", should_float,
				" v_accel=", String(vertical_accel).pad_decimals(2),
				" v_speed=", String(vertical_speed).pad_decimals(2),
				" t_jump=", String(time_since_jump).pad_decimals(2),
				" t_input=", String(time_since_input).pad_decimals(2),
				" t_jump_state=", String(time_in_jump_state).pad_decimals(2),
				" fall_no_jump=", falling_without_jump,
				" no_input_ok=", no_input_ok)
