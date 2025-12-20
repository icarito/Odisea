extends KinematicBody

var playback_target_pos = null # Nueva variable para el objetivo
var _replay_rotation_initialized := false
const CORRECTION_STRENGTH = 2.0 # Fuerza del imán (ajustable: 1.0 es suave, 5.0 es fuerte)

var FRICTION_FIXED = FixedPoint.to_fixed(0.85)
var STOP_THRESHOLD = FixedPoint.to_fixed(0.1)

const FixedVec3 = preload("res://scripts/utils/FVec3.gd")

# Fixed delta for deterministic simulation
const FIXED_DELTA = 1.0 / 60.0

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


# Velocidad externa aplicada por plataformas/conveyors (ahora en punto fijo)
var platform_is_static_surface := false
export var snap_len := 0.5 # TODO: migrar a fixed si es relevante
var snap_enabled := true

export(float, 0.0, 1.0, 0.01) var strafe_mode_influence := 1.0 # 1.0 = full strafe preferred, 0.0 = full tank turn

var strafe_cooldown := 0.0 # Prevents sudden turn after strafe ends


# Components
onready var external_velocity: ExternalVelocity = $ExternalVelocity if has_node("ExternalVelocity") else null
onready var jump_comp: PlayerJump = $PlayerJump if has_node("PlayerJump") else null
onready var movement_comp: PlayerMovement = $PlayerMovement if has_node("PlayerMovement") else null
# Usar InputState global como fuente de input
var InputState
onready var player_input = $PlayerInput if has_node("PlayerInput") else null

# --- REPLAY/STRAFE ---
var strafe_mode_active := false

# NEW: Multiplayer support
var player_id := 1

# Legacy variables (some may be moved to components)
var was_on_floor := false
export var max_platform_up_follow := 5.0
export var inherit_vertical_platform_jump := true
var just_jumped := false
var time_since_jump := 1.0
var time_since_input := 1.0

export var debug_movement := true
export var debug_shadow := false
export var debug_input := false
export var debug_enabled := true # bandera global para desactivar todos los logs por defecto

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
## (Eliminada declaración duplicada de velocity_fixed)

# Touch camera control
export var touch_sensitivity := 0.1

var angular_acceleration = 10
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
## Eliminadas variables de inversión de joystick físico
var _last_anim_node := ""
var _last_is_floating := false
var has_seen_floor_once := false
var time_since_start := 0.0
export var startup_floating_block_time := 0.6
var _debug_input_last := 0.0



var direction_fixed: Dictionary = FixedVec3.zero()
var horizontal_velocity_fixed: Dictionary = FixedVec3.zero()
var velocity_fixed: Dictionary = FixedVec3.zero()
var pre_move_velocity_for_replay_fixed: Dictionary = FixedVec3.zero()
var platform_velocity_fixed: Dictionary = FixedVec3.zero()
var airborne_inherited_fixed: Dictionary = FixedVec3.zero()
var last_platform_velocity_fixed: Dictionary = FixedVec3.zero()
var vertical_velocity_fixed: Dictionary = FixedVec3.zero()
var yaw_angle_fixed: int = 0
var movement_speed := 0.0
var acceleration := 15.0

var is_walking := false
var is_running := false
## [MIGRACIÓN]: Las variables Vector3 para simulación interna han sido eliminadas. Usar solo *_fixed para la lógica de movimiento.

onready var ground_ray: RayCast = $GroundRay
onready var fake_shadow: MeshInstance = $PilotMesh/FakeShadow

# Override local de gravedad desde zonas (WindZone)
var local_gravity_override := Vector3.ZERO

func set_gravity_override(g: Vector3) -> void:
	local_gravity_override = g

func clear_gravity_override() -> void:
	local_gravity_override = Vector3.ZERO

# Interfaz pública para que plataformas/conveyors transfieran velocidad (ahora en punto fijo)
func set_external_velocity_fixed(v: Dictionary) -> void:
	if external_velocity:
		external_velocity.set_external_velocity(FixedVec3.to_vec3(v))
	else:
		platform_velocity_fixed = v

func _ready():
	InputState = get_node("/root/InputState")
	add_to_group("replay_track")
	# Connect to GameGlobals for debug mode
	if GameGlobals:
		debug_enabled = GameGlobals.debug_mode
		GameGlobals.connect("debug_mode_changed", self, "_on_debug_mode_changed")
		# Set mouse capture immediately
		MouseCapture.set_capture(true)

	if UIManager:
		UIManager.connect("overlay_shown", self, "_on_UIManager_overlay_shown")
		UIManager.connect("overlay_hidden", self, "_on_UIManager_overlay_hidden")

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

var _is_ui_overlay_active := false
func _on_UIManager_overlay_shown():
	_is_ui_overlay_active = true
func _on_UIManager_overlay_hidden():
	_is_ui_overlay_active = false

func _input(event):
	# InputState gestiona el input globalmente. Aquí solo overlays y sincronización de cámara.
	if _is_ui_overlay_active:
		return
	if event.is_action_pressed("aim"):
		var cam_rig = get_node_or_null("CameraRig")
		if cam_rig and cam_rig.has_method("sync_to_body_yaw"):
			cam_rig.sync_to_body_yaw(rotation.y, cam_yaw_offset)
		direction_fixed = FixedVec3.from_vec3($CameraRig/Yaw.global_transform.basis.z)
	if event.is_action_released("aim"):
		player_mesh.rotation.y = rotation.y + mesh_yaw_offset

func _process(_delta):
	if has_node("FPSLabel"):
		$FPSLabel.text = "FPS: " + str(Engine.get_frames_per_second())

func roll():
	if InputState and InputState.is_action_pressed("roll") and playback:
		if !roll_node_name in playback.get_current_node() and !jump_node_name in playback.get_current_node() and !bigattack_node_name in playback.get_current_node():
			playback.start(roll_node_name)
			horizontal_velocity_fixed = FixedVec3.mul_scalar(direction_fixed, FixedPoint.to_fixed(dash_power))

func attack1():
	if playback and (idle_node_name in playback.get_current_node() or walk_node_name in playback.get_current_node()) and is_on_floor():
		if InputState and InputState.is_action_pressed("attack"):
			if (is_attacking == false):
				playback.travel(attack1_node_name)

func attack2():
	if playback and attack1_node_name in playback.get_current_node():
		if InputState and InputState.is_action_pressed("attack"):
			playback.travel(attack2_node_name)

func attack3():
	if attack1_node_name in playback.get_current_node():
		if InputState.is_action_pressed("attack"):
			pass

func rollattack():
	if playback and roll_node_name in playback.get_current_node():
		if InputState and InputState.is_action_pressed("attack"):
			playback.travel(bigattack_node_name)

func bigattack():
	if playback and run_node_name in playback.get_current_node():
		if InputState and InputState.is_action_pressed("attack"):
			horizontal_velocity_fixed = direction_fixed * FixedPoint.to_fixed(dash_power)

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
	if not InputState:
		return { "move_x": 0.0, "move_y": 0.0, "run": false, "jump": false }
	return {
		"move_x": InputState.get_axis("move_x"),
		"move_y": InputState.get_axis("move_y"),
		"run": InputState.is_action_pressed("run"),
		"jump": InputState.is_action_pressed("jump")
	}

func _finish_spawn():
	# Alinear dirección inicial con el frente del mesh y la cámara
	var yaw_node = get_node_or_null("CameraRig/Yaw")
	var yaw_angle := 0.0
	if yaw_node:
		yaw_angle = yaw_node.global_transform.basis.get_euler().y + cam_yaw_offset
	# Usar frente del mesh para coherencia de animación al inicio
	var initial_direction = Vector3.FORWARD.rotated(Vector3.UP, rotation.y + PI)
	# Si la cámara existe, rotar la dirección por su yaw para entrada relativa a cámara (comentado, ya que usamos rotation.y + PI)
	# initial_direction = initial_direction.rotated(Vector3.UP, yaw_angle)
	if movement_comp:
		movement_comp.direction = initial_direction

	# Resetear velocidades al spawn para evitar velocidad residual
	horizontal_velocity_fixed = FixedVec3.zero()
	vertical_velocity_fixed = {"x": 0, "y": 0, "z": 0}
	platform_velocity_fixed = FixedVec3.zero()
	if external_velocity:
		external_velocity.velocity = Vector3.ZERO
	
	# Dar un pequeño empujón hacia adelante para estabilizar el spawn
	horizontal_velocity_fixed.z = FixedPoint.to_fixed(0.1)

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
	print("[PlayerController] _physics_process running")
	var has_input := false
	var movement_this_frame_fixed := FixedVec3.zero()
	var movement_this_frame_vec := Vector3.ZERO
	time_since_jump += FIXED_DELTA
	time_since_input += FIXED_DELTA
	time_since_start += FIXED_DELTA

	var on_floor = is_on_floor()

	print("is_on_floor: ", on_floor)
	if on_floor:
		var col = get_slide_collision(0)
		if col:
			print("Colisionando con: ", col.collider.name)

	# Declarar variables de input
	var input_vector := Vector2.ZERO
	var mouse_motion = null
	var is_sprinting = false
	var jump_pressed = false

	# Siempre usar InputState para obtener input y mouse delta, tanto en vivo como en replay
	if InputState:
		var move_x = InputState.get_axis("move_x") if InputState.get_axis("move_x") != null else 0.0
		var move_y = InputState.get_axis("move_y") if InputState.get_axis("move_y") != null else 0.0
		input_vector = Vector2(-move_x, move_y)
		mouse_motion = InputState.get_mouse_delta()
		if not (mouse_motion is Vector2):
			mouse_motion = Vector2.ZERO
		is_sprinting = InputState.is_action_pressed("run")
		jump_pressed = InputState.is_action_pressed("jump")
	has_input = input_vector.length() > 0.1

	# Resetear strafe_cooldown si hay input, solo decrementar si NO hay input
	if input_vector.length() > 0.1:
		strafe_cooldown = 0.0
	else:
		strafe_cooldown = max(0.0, strafe_cooldown - FIXED_DELTA)

	# --- MOVEMENT LOGIC: RUNS FOR BOTH NORMAL AND REPLAY ---

	# Process attacks and rolls that can affect movement
	rollattack()
	bigattack()
	attack1()
	attack2()
	roll()

	# Medir tiempo en estado Jump del AnimationTree
	var in_jump_state = (playback and (playback.get_current_node() == jump_node_name))
	if in_jump_state:
		time_in_jump_state += FIXED_DELTA
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

	# Apply Gravity (fixed-point)
	if not is_on_floor():
		var gravity_fixed = FixedVec3.from_vec3(effective_gravity_vector)
		var delta_fixed = FixedPoint.to_fixed(FIXED_DELTA)
		var multiplier_fixed = FixedPoint.fixed_mul(FixedPoint.to_fixed(2), delta_fixed)
		var gravity_delta_fixed = FixedVec3.mul_scalar(gravity_fixed, multiplier_fixed)
		vertical_velocity_fixed = FixedVec3.add(vertical_velocity_fixed, gravity_delta_fixed)
	else:
		# Si la gravedad efectiva apunta hacia arriba (levanta), despegar del suelo
		if effective_gravity_dir.dot(Vector3.UP) > 0.5:
			snap_enabled = false
			var gravity_dir_fixed = FixedVec3.from_vec3(effective_gravity_dir)
			var min_gravity_fixed = FixedPoint.to_fixed(min(effective_gravity_mag, gravity))
			var half_gravity_fixed = FixedPoint.fixed_mul(min_gravity_fixed, FixedPoint.to_fixed(0.5))
			vertical_velocity_fixed = FixedVec3.mul_scalar(gravity_dir_fixed, half_gravity_fixed)
		else:
			var floor_normal_fixed = FixedVec3.from_vec3(-get_floor_normal())
			var min_gravity_fixed = FixedPoint.to_fixed(min(effective_gravity_mag, gravity))
			var third_gravity_fixed = FixedPoint.fixed_div(min_gravity_fixed, FixedPoint.to_fixed(3))
			vertical_velocity_fixed = FixedVec3.mul_scalar(floor_normal_fixed, third_gravity_fixed)

		# Clamp de velocidad vertical para evitar picos (fixed-point)
		var max_fall_fixed = FixedPoint.to_fixed(-max_fall_speed)
		var max_rise_fixed = FixedPoint.to_fixed(max_rise_speed)
		var clamped_y_fixed = FixedPoint.fixed_clamp(vertical_velocity_fixed.y, max_fall_fixed, max_rise_fixed)
		vertical_velocity_fixed = {"x": vertical_velocity_fixed.x, "y": clamped_y_fixed, "z": vertical_velocity_fixed.z}

		# Check for attack/roll states that modify acceleration
		if playback and ((attack1_node_name in playback.get_current_node()) or (attack2_node_name in playback.get_current_node()) or (bigattack_node_name in playback.get_current_node())):
			is_attacking = true
		else:
			is_attacking = false

		if playback and bigattack_node_name in playback.get_current_node():
			acceleration = 3

		if playback and roll_node_name in playback.get_current_node():
			is_rolling = true
			acceleration = 2
			angular_acceleration = 2
		else:
			is_rolling = false

		# Handle Jump (fixed-point)
		if jump_pressed and ((is_attacking != true) and (is_rolling != true)) and is_on_floor():
			if AudioSystem: AudioSystem.play_sfx("res://assets/sfx/jump.wav")
			var pv_fixed := platform_velocity_fixed
			var jump_force_fixed = FixedPoint.to_fixed(jump_force)
			vertical_velocity_fixed = {"x": 0, "y": jump_force_fixed, "z": 0}
			if inherit_vertical_platform_jump and FixedVec3.to_vec3(pv_fixed).y > 0.0:
				var min_pv_fixed = FixedPoint.to_fixed(min(FixedVec3.to_vec3(pv_fixed).y, max_platform_up_follow))
				var new_y_fixed = FixedPoint.fixed_add(vertical_velocity_fixed.y, min_pv_fixed)
				vertical_velocity_fixed = {"x": vertical_velocity_fixed.x, "y": new_y_fixed, "z": vertical_velocity_fixed.z}
			snap_enabled = false
			airborne_inherited_fixed = {"x": pv_fixed.x, "y": 0, "z": pv_fixed.z}
			horizontal_velocity_fixed = FixedVec3.add(horizontal_velocity_fixed, airborne_inherited_fixed)
			just_jumped = true
			time_since_jump = 0.0

		if has_input:
			time_since_input = 0.0
		else:
			# Aplicar fricción si no hay input
			if on_floor:
				horizontal_velocity_fixed.x = FixedPoint.fixed_mul(horizontal_velocity_fixed.x, FRICTION_FIXED)
				horizontal_velocity_fixed.z = FixedPoint.fixed_mul(horizontal_velocity_fixed.z, FRICTION_FIXED)
				
				if abs(horizontal_velocity_fixed.x) < STOP_THRESHOLD:
					horizontal_velocity_fixed.x = 0
				if abs(horizontal_velocity_fixed.z) < STOP_THRESHOLD:
					horizontal_velocity_fixed.z = 0



	# Camera Control (runs for both normal and replay)
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig:
		if cam_rig.has_method("process_camera_rotation"):
			if mouse_motion != null:
				# cam_rig.process_camera_rotation(mouse_motion) # Desactivado: la cámara gestiona su propio input en _physics_process
				pass
		# Removed mouse_active_timer logic, now handled in InputState

		if movement_comp:
			# --- Strafe Mode Logic ---
			# The strafing state is now managed centrally by InputState.gd
			if InputState.mode == InputState.Mode.LIVE or InputState.mode == InputState.Mode.RECORD:
				if InputState.mouse_delta.length() > 0.0:
					InputState.is_strafing_mode_active = true
					InputState.strafing_timer = 5.0
				if InputState.is_strafing_mode_active:
					if input_vector.length() > 0.1:
						InputState.strafing_timer = 5.0  # Reset timer while moving
					else:
						InputState.strafing_timer -= delta
						if InputState.strafing_timer <= 0.0:
							InputState.is_strafing_mode_active = false
							strafe_cooldown = 0.5 # Prevent sudden turn after strafe

			var strafe_mode_active = InputState.is_strafing_mode_active
			# --- Sincronización explícita durante replay ---
			if GameGlobals and GameGlobals.is_replaying:
				strafe_mode_active = InputState.is_strafing_mode_active
				# (Opcional) También sincroniza el timer si es relevante:

			# --- ROTACIÓN DEL CUERPO CON EL MOUSE (SOLO LIVE) ---
			# En modo REPLAY, la rotación la fuerza el sistema de replay (SNAP/corrección), no el mouse_delta
			if not strafe_mode_active and mouse_motion != null:
				var yaw_sens := 2.0 # Ajusta según lo que uses en cámara
				if GameGlobals and GameGlobals.is_replaying:
					# No modificar rotation.y aquí, la rotación será corregida por ReplayPlayback.gd
					pass
				else:
					rotation.y -= mouse_motion.x * yaw_sens / 1000.0
			# strafing_timer = InputState.strafing_timer
			
			# Set strafe mode in movement component
			if movement_comp:
				movement_comp.strafe_mode = strafe_mode_active
			
			var turn_input_val = input_vector.x
			var movement_input_vec = input_vector
			var yaw_delta = 0.0
			if strafe_mode_active:
				# En modo strafe, bloquear rotación del cuerpo (Yaw): NO modificar rotation.y
				turn_input_val = 0.0
				yaw_delta = 0.0
			else:
				# En modo tank, permitir giro normal
				turn_input_val = input_vector.x
				movement_input_vec.x = 0.0
				yaw_delta = turn_input_val * movement_comp.tank_turn_speed * delta
				yaw_angle_fixed += FixedPoint.to_fixed(yaw_delta)
				rotation.y = FixedPoint.from_fixed(yaw_angle_fixed)
				if cam_rig.has_method("apply_external_yaw_delta"):
					cam_rig.apply_external_yaw_delta(yaw_delta)
			# Prevent sudden turn after strafe ends
			if strafe_cooldown > 0.0:
				# Bloquea giro durante cooldown
				yaw_delta = 0.0

			# 2. Process movement with the modified input vector
			var basis := Basis()
			var yaw_node_local = get_node_or_null("CameraRig/Yaw")
			if yaw_node_local:
				basis = yaw_node_local.global_transform.basis
				movement_comp.process_input_vector(delta, basis, movement_input_vec, is_sprinting if is_sprinting != null else false, on_floor if on_floor != null else false)

			print("[PlayerController] input_vector=", input_vector, " movement_input_vec=", movement_input_vec)
			# Sincronizar velocidad horizontal fija y dirección fija desde el componente de movimiento
			if movement_comp and has_input:
				horizontal_velocity_fixed = movement_comp.horizontal_velocity_fixed
				direction_fixed = FixedVec3.from_vec3(movement_comp.direction)

			# 3. Get results from movement component
			# direction (Vector3) eliminado: solo usar direction_fixed para lógica determinista
			# horizontal_velocity (Vector3) eliminado: solo usar horizontal_velocity_fixed y su conversión si es necesario
			is_walking = movement_comp.is_walking
			is_running = movement_comp.is_running
		else:
			is_walking = false; is_running = false

	
	# Platform velocity logic (fixed-point)
	var zero_fixed = FixedVec3.zero()
	var lerp_factor_fixed = FixedPoint.fixed_mul(FixedPoint.to_fixed(6.0), FixedPoint.to_fixed(delta))
	platform_velocity_fixed = FixedVec3.lerp(platform_velocity_fixed, zero_fixed, lerp_factor_fixed)
	if is_on_floor():
		last_platform_velocity_fixed = platform_velocity_fixed
		airborne_inherited_fixed = FixedVec3.zero()
		if FixedVec3.to_vec3(platform_velocity_fixed).y > 0.0 and not just_jumped:
			var min_pv_fixed = FixedPoint.to_fixed(min(FixedVec3.to_vec3(platform_velocity_fixed).y, max_platform_up_follow))
			vertical_velocity_fixed = {"x": vertical_velocity_fixed.x, "y": min_pv_fixed, "z": vertical_velocity_fixed.z}
	elif was_on_floor:
		airborne_inherited_fixed = last_platform_velocity_fixed
	
	# Final velocity combination for this frame (fixed-point)
	var effective_platform_velocity_fixed := (platform_velocity_fixed if (is_on_floor() and platform_is_static_surface) else airborne_inherited_fixed)
	var combined_horizontal_fixed = FixedVec3.add(horizontal_velocity_fixed, effective_platform_velocity_fixed)
	movement_this_frame_fixed = FixedVec3.add(combined_horizontal_fixed, vertical_velocity_fixed)
	movement_this_frame_vec = FixedVec3.to_vec3(movement_this_frame_fixed)

	print("[PlayerController] movement_this_frame_vec=", movement_this_frame_vec)

	# [NUEVO] APLICAR SOFT SYNC (MANO INVISIBLE)
	# Hacemos esto JUSTO ANTES de move_and_slide
	if GameGlobals.is_replaying and playback_target_pos != null and not (GameGlobals.determinism_test):
		var current_pos = global_transform.origin
		# Vector desde donde estoy hacia donde debería estar
		var error_vector = playback_target_pos - current_pos
		# Opción más robusta: Separar horizontal y vertical
		movement_this_frame_vec.x += error_vector.x * CORRECTION_STRENGTH
		movement_this_frame_vec.z += error_vector.z * CORRECTION_STRENGTH
		# Si el error es muy grande (> 1 metro), hacemos un SNAP de emergencia
		if error_vector.length() > 1.0:
			global_transform.origin = playback_target_pos

	# --- LOGIC THAT RUNS IN BOTH MODES ---

	# Rotate mesh towards movement direction
	if direction_fixed != FixedVec3.zero():
		var dir_vec3 := FixedVec3.to_vec3(direction_fixed)
		var target_y := atan2(dir_vec3.x, dir_vec3.z) + mesh_yaw_offset
		var parent_y = rotation.y
		var local_target_y = target_y - parent_y
		player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, local_target_y, delta * angular_acceleration)

	var h_rot := 0.0
	var yaw_node2 = get_node_or_null("CameraRig/Yaw")
	if yaw_node2: h_rot = yaw_node2.global_transform.basis.get_euler().y + cam_yaw_offset

	# 💥 LOG CRÍTICO PARA DETERMINISMO 💥
	# Usar SIEMPRE el valor de strafe desde InputState
	strafe_mode_active = InputState.is_strafing_mode_active
	if movement_comp:
		movement_comp.strafe_mode = strafe_mode_active
		if GameGlobals and GameGlobals.replay_debug_mode and GameGlobals.is_replaying:
			print(
				"[PlayerController DETAILED STATE] Frame:", Engine.get_physics_frames(),
				" | Pos:", ReplayUtils.fixed_dict_to_vector3(ReplayUtils.vector3_to_fixed_dict(global_transform.origin)),
				" | Rot:", rotation.y,
				" | Vel_fixed:", velocity_fixed,
				" | Dir_fixed:", movement_this_frame_fixed,
				" | Strafe:", strafe_mode_active
			)

		# print("[PlayerController] Pre-move: velocity=%s, on_floor=%s" % [movement_this_frame, on_floor])
		pre_move_velocity_for_replay_fixed = movement_this_frame_fixed
	
		# Snap to ground
		var snap_vec := Vector3.ZERO
		if on_floor and snap_enabled:
			snap_vec = Vector3.DOWN * snap_len
		elif on_floor:
			snap_enabled = true

		# --- THE ACTUAL PHYSICS STEP ---
		var velocity_vec = move_and_slide_with_snap(movement_this_frame_vec, snap_vec, Vector3.UP, false)
		velocity_fixed = FixedVec3.from_vec3(velocity_vec)

	# print("[PlayerController] Post-move Pos (Simulated): %s" % [global_transform.origin])
	# print("[PlayerController POST-SLIDE] Velocity: %s" % [velocity])
	
	# Update velocity components from the result for the next frame
	# Calcular horizontal_velocity_fixed solo con punto fijo
	horizontal_velocity_fixed = {"x": velocity_fixed.x, "y": 0, "z": velocity_fixed.z}
	if movement_comp:
		movement_comp.horizontal_velocity = FixedVec3.to_vec3(horizontal_velocity_fixed)
	vertical_velocity_fixed = {"x": 0, "y": velocity_fixed.y, "z": 0}
	
	# Snapping to zero to prevent numerical drift (solo punto fijo)
	if is_on_floor() and FixedVec3.length_squared(horizontal_velocity_fixed) < 0.0001:
		horizontal_velocity_fixed = FixedVec3.zero()
		if movement_comp:
			movement_comp.horizontal_velocity = Vector3.ZERO
		horizontal_velocity_fixed = FixedVec3.zero()
		velocity_fixed.x = 0
		velocity_fixed.z = 0
		if movement_comp:
			movement_comp.horizontal_velocity = Vector3.ZERO
	
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

	# Floating state logic (uses vertical_velocity_fixed, which is now post-slide)
	var replay_manager = null
	if has_node("/root/ReplayManager"):
		replay_manager = get_node("/root/ReplayManager")
	var vertical_velocity_y_float = FixedPoint.from_fixed(vertical_velocity_fixed.y)
	var should_float = false
	if !on_floor and abs(vertical_velocity_y_float) < floating_enter_vspeed_threshold:
		should_float = true
	var state = {
		# Solo punto fijo para replay determinista
		"player_position_fixed": ReplayUtils.vector3_to_fixed_dict(global_transform.origin),
		"platform_velocity_fixed": platform_velocity_fixed,
		"airborne_inherited_fixed": airborne_inherited_fixed,
		"just_jumped": just_jumped,
		"time_since_jump": time_since_jump,
		"time_since_input": time_since_input,
		"was_on_floor": was_on_floor,
		"snap_enabled": snap_enabled,
		"rotation_fixed": ReplayUtils.vector3_to_fixed_dict(rotation),
		"basis_fixed": ReplayUtils.basis_to_fixed_dict(global_transform.basis),
		"velocity_fixed": velocity_fixed,
		"pre_move_velocity_fixed": pre_move_velocity_for_replay_fixed,
		"direction_fixed": direction_fixed
	}
	_last_is_floating = should_float
	state["coyote_timer"] = jump_comp.coyote_timer
	state["jump_buffer_timer"] = jump_comp.jump_buffer_timer
	state["should_jump_buffered"] = jump_comp.should_jump_buffered
	if GameGlobals.is_replaying and replay_manager.current_camera_mode == replay_manager.CameraMode.FOLLOW_REPLAY:
		# This script just used the replayed yaw value. Clean it so it's not used elsewhere.
		InputState.clean_mouse_delta_x()


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

	# 3. Resetear input residual del mouse (si aplica, delegar a InputState o cámara)
	if InputState.has_method("reset_mouse_motion"):
		InputState.reset_mouse_motion()
	print("[PlayerController] InputState.reset_mouse_motion() called")

	# 4. Resetear velocidades y estado de movimiento
	if has_node("GroundRay"):
		$GroundRay.force_raycast_update()
		print("[PlayerController] GroundRay force_raycast_update called")
	# horizontal_velocity (Vector3) eliminado: solo usar horizontal_velocity_fixed
	horizontal_velocity_fixed = FixedVec3.zero()
	vertical_velocity_fixed = FixedVec3.zero()
	platform_velocity_fixed = FixedVec3.zero()
	# last_platform_velocity (Vector3) eliminado: solo usar last_platform_velocity_fixed
	# airborne_inherited (Vector3) eliminado: solo usar airborne_inherited_fixed
	print("[PlayerController] velocities reset to ZERO")
	
	# Resetea la dirección de movimiento para que el personaje no intente moverse.
	# La orientación del cuerpo ya está establecida por global_transform.
	direction_fixed = FixedVec3.zero()
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

func dump_state() -> Dictionary:
	var state = {
			"global_transform_origin_fixed": ReplayUtils.vector3_to_fixed_dict(global_transform.origin),
			"velocity_fixed": velocity_fixed,
			"is_on_floor": is_on_floor(),
			"just_jumped": just_jumped,
			"airborne_inherited_fixed": airborne_inherited_fixed,
			"platform_velocity_fixed": platform_velocity_fixed,
			"rotation_fixed": ReplayUtils.vector3_to_fixed_dict(rotation),
			"basis_fixed": ReplayUtils.basis_to_fixed_dict(global_transform.basis),
			"horizontal_velocity_fixed": horizontal_velocity_fixed,
			"vertical_velocity_fixed": vertical_velocity_fixed,
			"direction_fixed": direction_fixed,
			"time_since_jump": time_since_jump,
			"time_since_input": time_since_input,
			"was_on_floor": was_on_floor,
			"snap_enabled": snap_enabled,
			"collisions": []
		}
	
	# Dump all slide collisions
	for i in range(get_slide_count()):
		var collision = get_slide_collision(i)
		state["collisions"].append({
			"collider": collision.collider.name if collision.collider else "null",
			"normal": collision.normal,
			"position": collision.position,
			"remainder": collision.remainder
		})
	
	return state

func get_replay_state() -> Dictionary:
	# This function should return raw Godot types.
	# The ReplayRecorder is responsible for converting them to a JSON-safe format.
	var state = {
		"global_transform": ReplayUtils.transform_to_dict(global_transform),
		"player_position_fixed": ReplayUtils.vector3_to_fixed_dict(global_transform.origin),
		"pilot_pos": global_transform.origin,
		"pilot_rot": rotation.y,
		"platform_velocity_fixed": platform_velocity_fixed,
		"airborne_inherited_fixed": airborne_inherited_fixed,
		"just_jumped": just_jumped,
		"time_since_jump": time_since_jump,
		"time_since_input": time_since_input,
		"was_on_floor": was_on_floor,
		"snap_enabled": snap_enabled,
		"rotation_fixed": ReplayUtils.vector3_to_fixed_dict(rotation),
		"basis_fixed": ReplayUtils.basis_to_fixed_dict(global_transform.basis),
		"velocity_fixed": velocity_fixed,
		"pre_move_velocity_fixed": pre_move_velocity_for_replay_fixed,
		"direction_fixed": direction_fixed
	}
	if jump_comp:
		state["coyote_timer"] = jump_comp.coyote_timer
		state["jump_buffer_timer"] = jump_comp.jump_buffer_timer
		state["should_jump_buffered"] = jump_comp.should_jump_buffered
	return state

func set_replay_state(state: Dictionary) -> void:

	# Resetear la bandera al inicio de cada replay (cuando se recibe un nuevo estado inicial)
	if state.has("player_position_fixed"):
		_replay_rotation_initialized = false

	var deserialized_state = ReplayUtils.from_json_safe(state)
	var is_replaying = GameGlobals and GameGlobals.is_replaying
	var replay_manager = get_node("/root/ReplayManager")

	# Restore state from the replay file - USE FIXED-POINT DATA FOR DETERMINISTIC PLAYBACK
	if state.has("player_position_fixed"):
		var pos_fixed = state["player_position_fixed"]
		if pos_fixed is Dictionary:
			global_transform.origin = ReplayUtils.fixed_dict_to_vector3(pos_fixed)
		else:
			global_transform.origin = deserialized_state.get("player_position", global_transform.origin)
	else:
		global_transform.origin = deserialized_state.get("player_position", global_transform.origin)
	
	if state.has("basis_fixed"):
		var basis_fixed = state["basis_fixed"]
		if basis_fixed is Dictionary:
			global_transform.basis = ReplayUtils.fixed_dict_to_basis(basis_fixed)
	elif deserialized_state.has("basis"):
		var basis_dict = deserialized_state["basis"]
		if basis_dict is Dictionary and basis_dict.has("x") and basis_dict.has("y") and basis_dict.has("z"):
			var basis_x = basis_dict["x"]
			var basis_y = basis_dict["y"]
			var basis_z = basis_dict["z"]
			if basis_x is Vector3 and basis_y is Vector3 and basis_z is Vector3:
				global_transform.basis = Basis(basis_x, basis_y, basis_z)
	
	var platform_velocity_vec = deserialized_state.get("platform_velocity_fixed", FixedVec3.to_vec3(platform_velocity_fixed))
	platform_velocity_fixed = FixedVec3.from_vec3(platform_velocity_vec)
	just_jumped = deserialized_state.get("just_jumped", false)
	time_since_jump = deserialized_state.get("time_since_jump", 1.0)
	time_since_input = deserialized_state.get("time_since_input", 1.0)
	was_on_floor = deserialized_state.get("was_on_floor", false)
	snap_enabled = deserialized_state.get("snap_enabled", true)

	# Solo restaurar la rotación en el primer frame del replay (usando una variable miembro booleana)
	if not _replay_rotation_initialized:
		if deserialized_state.has("rotation"):
			rotation = deserialized_state["rotation"]
		_replay_rotation_initialized = true

	# Restore velocity from fixed-point data for deterministic playback
	if state.has("velocity_fixed"):
		var vel_fixed = state["velocity_fixed"]
		if vel_fixed is Dictionary:
			velocity_fixed = vel_fixed
		else:
			velocity_fixed = FixedVec3.from_vec3(deserialized_state.get("velocity", Vector3.ZERO))
	else:
		velocity_fixed = FixedVec3.from_vec3(deserialized_state.get("velocity", Vector3.ZERO))
	
	var velocity_vec3 = FixedVec3.to_vec3(velocity_fixed)
	horizontal_velocity_fixed = FixedVec3.from_vec3(velocity_vec3 - Vector3(0, velocity_vec3.y, 0))
	vertical_velocity_fixed = FixedVec3.from_vec3(Vector3(0, velocity_vec3.y, 0))

	if jump_comp and deserialized_state.has("coyote_timer") and deserialized_state["coyote_timer"] != null:
		jump_comp.coyote_timer = deserialized_state["coyote_timer"]
	if jump_comp and deserialized_state.has("jump_buffer_timer") and deserialized_state["jump_buffer_timer"] != null:
		jump_comp.jump_buffer_timer = deserialized_state["jump_buffer_timer"]
	if jump_comp and deserialized_state.has("should_jump_buffered") and deserialized_state["should_jump_buffered"] != null:
		jump_comp.should_jump_buffered = deserialized_state["should_jump_buffered"]


func playback_process(frame_data_state: Dictionary, _delta: float) -> void:
		   # En modo PLAYBACK, procesar los inputs grabados igual que en LIVE/RECORD
		   # 1. Inyectar input_vector, mouse_delta y strafe grabados en InputState
		   if frame_data_state.has("input_vector"):
			   var iv = frame_data_state["input_vector"]
			   if iv is Dictionary:
				   InputState.input_vector = ReplayUtils.dict_to_vector2(iv)
			   else:
				   InputState.input_vector = Vector2.ZERO
		   if frame_data_state.has("mouse_delta"):
			   var md = frame_data_state["mouse_delta"]
			   if md is Dictionary:
				   InputState.mouse_delta = ReplayUtils.dict_to_vector2(md)
			   else:
				   InputState.mouse_delta = Vector2.ZERO
		   if frame_data_state.has("strafing_active"):
			   InputState.is_strafing_mode_active = frame_data_state["strafing_active"]
		   else:
			   InputState.is_strafing_mode_active = false
		   # 2. Procesar el movimiento normalmente (igual que LIVE/RECORD)
		   # Esto ocurre en _physics_process, así que aquí no se debe modificar velocity ni horizontal_velocity

		   # 3. Solo usar la inyección de estado (velocidad, posición) para corrección de deriva (drift correction), no en el ciclo normal

		   # 4. SNAP de rotación al mesh si el cuerpo fue corregido (esto debe ser llamado desde ReplayPlayback.gd, pero aquí lo forzamos si hay diferencia grande)
		   if is_instance_valid(player_mesh):
			   var mesh_snap_threshold = 0.01
			   var mesh_rot_diff = abs(fmod(player_mesh.rotation.y, PI * 2.0))
			   if mesh_rot_diff > mesh_snap_threshold:
				   player_mesh.rotation.y = 0.0 # El mesh debe alinearse al cuerpo tras SNAP

			   # --- ANTI-PATINAJE: Rotación visual del mesh igual que en _physics_process ---
			   var horizontal_speed = FixedVec3.to_vec3(horizontal_velocity_fixed).length()
			   print("[REPLAY][ANTI-PATINAJE] Frame:", Engine.get_frames_drawn(),
				   " | horizontal_velocity:", horizontal_velocity_fixed,
				   " | horizontal_speed:", horizontal_speed,
				   " | player_mesh.rotation.y:", player_mesh.rotation.y,
				   " | cuerpo.rotation.y:", rotation.y)
			   if horizontal_speed > 0.05:
				   var movement_dir = FixedVec3.to_vec3(horizontal_velocity_fixed).normalized()
				   var target_angle_global = atan2(movement_dir.x, movement_dir.z)
				   var relative_rotation = target_angle_global - rotation.y
				   var turn_rate = turn_speed * 10.0 * _delta
				   player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, relative_rotation, turn_rate)
			   else:
				   player_mesh.rotation.y = lerp_angle(player_mesh.rotation.y, 0.0, _delta * 10.0)

## --- INYECCIÓN DE INPUT DE REPLAY ---
# Este método permite que el sistema de replay fuerce la rotación y anule el strafe.
func inject_replay_input(mouse_delta: Vector2) -> void:
	# 1. Anular strafe para permitir rotación por mouse_delta.x
	var strafe_mode_active = false
	# 2. Aplicar rotación Yaw (horizontal) al cuerpo
	var yaw_sens := 2.0 # Debe coincidir con el usado en _physics_process
	if mouse_delta != null:
		rotation.y -= mouse_delta.x * yaw_sens / 1000.0
	# 3. Aplicar Pitch (vertical) a la cámara si existe
	var cam_rig = get_node_or_null("CameraRig")
	if cam_rig and cam_rig.has_method("apply_replay_rotation"):
		cam_rig.apply_replay_rotation(mouse_delta)
	# 4. (Opcional) Sincronizar strafe en el movement_comp si es necesario
	if movement_comp:
		movement_comp.strafe_mode = strafe_mode_active
