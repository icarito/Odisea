extends Spatial

class_name PilotAnimatorV2

# --- PARAMETER PATHS (CACHED STRINGS) ---
const PARAM_PLAYBACK = "parameters/playback"
const PARAM_CONDITIONS_ON_FLOOR = "parameters/conditions/on_floor"
const PARAM_CONDITIONS_NOT_ON_FLOOR = "parameters/conditions/!on_floor"
const PARAM_CONDITIONS_IS_FALLING = "parameters/conditions/is_falling"
const PARAM_CONDITIONS_IS_JUMPING = "parameters/conditions/is_jumping"
const PARAM_CONDITIONS_IS_FLOATING = "parameters/conditions/is_floating"
const PARAM_CONDITIONS_IS_FALLING_FAST = "parameters/conditions/is_falling_fast"
const PARAM_CONDITIONS_HIT_HEAD = "parameters/conditions/hit_head"
const PARAM_CONDITIONS_LAND_SOFT = "parameters/conditions/land_soft"
const PARAM_CONDITIONS_LAND_HARD = "parameters/conditions/land_hard"
const PARAM_CONDITIONS_USE_JUMP_LOOP = "parameters/conditions/use_jump_loop"
const PARAM_GROUNDED_BLEND_POSITION = "parameters/Grounded/blend_position"
const PARAM_CROUCHED_BLEND_POSITION = "parameters/Crouched/blend_position"
const PARAM_GROUNDED_JUMP_ACTIVE = "parameters/Grounded/Jump/active"
const PARAM_LAND_TRANSITION_CURRENT = "parameters/Land/Transition/current"
const PARAM_JUMP_TRANSITION_CURRENT = "parameters/Jump/Transition/current"
const PARAM_PLAYBACK_ACTIVE = "parameters/playback/active"
const PARAM_CONDITIONS_IS_ACROBATIC = "parameters/conditions/is_acrobatic"
const PARAM_CONDITIONS_IS_PUSHING = "parameters/conditions/is_pushing"
const PARAM_CONDITIONS_NOT_PUSHING = "parameters/conditions/!is_pushing"
const PARAM_CONDITIONS_IS_CROUCHED = "parameters/conditions/is_crouched"
const PARAM_CONDITIONS_NOT_CROUCHED = "parameters/conditions/!is_crouched"
const PARAM_CONDITIONS_IS_HANGING = "parameters/conditions/is_hanging"
const PARAM_CONDITIONS_IS_CLIMBING = "parameters/conditions/is_climbing"
const PARAM_CONDITIONS_NOT_CLIMBING = "parameters/conditions/!is_climbing"
const PARAM_CONDITIONS_CLIMB_EXIT_AIR = "parameters/conditions/climb_exit_air"
const PARAM_CLIMBING_TIMESCALE = "parameters/Climbing/TimeScale/scale"
const PARAM_CLIMBING_DIRECTION_BLEND = "parameters/Climbing/Direction/blend_amount"
const CLIMB_UP_ANIM_NAME = "Climb_Loop_70"
const CLIMB_DOWN_ANIM_NAME = "Climb_Loop_Down_70"
const CLIMB_UP_ANIM_PATH = "res://models/Pilot/Climb_Loop_70.anim"

# --- EXPORTS ---
# Velocidad de suavizado para la velocidad usada en el AnimationTree.
export var velocity_lerp_speed: float = 5.0
# Velocidad de suavizado para la rotación visual del personaje.
# Velocidad de suavizado para la rotación visual del personaje.
export var rotation_lerp_speed: float = 10.0

# --- Variables de Calibración de Empuje ---
export(float) var push_arm_length_offset = 0.0 # Standard reach (0.9m) matches 0.9m offset.
export(float) var push_start_delay = 0.2
export(float) var push_lerp_speed = 10.0
export(float) var climb_idle_motion_threshold = 0.12
export(float) var climb_idle_playback_scale = 0.0
export(float) var climb_motion_playback_scale = 1.9
export(float) var climb_playback_lerp_speed = 8.0
export(float) var climb_visual_wall_offset = 0.24
export(float) var climb_visual_lateral_offset = -0.12
export(float) var climb_visual_vertical_offset = 0.0
export(float) var climb_visual_offset_lerp_speed = 10.0
export(float) var climb_visual_pitch_deg = -4.0
export(float) var climb_pose_correction_lerp_speed = 4.0
export(float) var climb_spine_pitch_deg_1 = -1.5
export(float) var climb_spine_pitch_deg_2 = -3.5
export(float) var climb_spine_pitch_deg_3 = -4.5
export(float) var climb_thigh_pitch_deg = -7.0
export(float) var climb_shin_pitch_deg = -5.0
export(float) var climb_clavicle_out_deg_left = 1.0
export(float) var climb_clavicle_out_deg_right = 0.0
export(float) var climb_upper_arm_out_deg_left = 0.0
export(float) var climb_upper_arm_out_deg_right = 0.0
export(float) var climb_upper_arm_back_deg = 0.0
export(float) var climb_hand_target_half_width = 0.32
export(float) var climb_hand_height_offset = 1.1
export(float) var climb_hand_target_lerp_speed = 3.0
export(float) var climb_hand_ik_upper_arm_weight = 0.0
export(float) var climb_hand_ik_forearm_weight = 0.18
export(float) var climb_hand_ik_max_step_deg = 4.0
export(bool) var enable_climbing_ik = false
# Duración en segundos durante la cual consideramos que el salto acaba de iniciarse (buffer)
export var jump_buffer_duration: float = 0.18
export var debug_push_gizmo: bool = false
export var stair_air_time_threshold: float = 0.25
export var debug_stair_blend: bool = false
export var debug_animation_events: bool = false

# --- NODES ---
var controller: Node = null
onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree")
var anim_player: AnimationPlayer = null
var _debug_sphere: MeshInstance = null
var _hand_l_gizmo: MeshInstance = null
var _hand_r_gizmo: MeshInstance = null
var _skeleton: Skeleton = null
var _skeleton_base_translation := Vector3.ZERO
var _skeleton_base_basis := Basis()
onready var jump_sfx: SFXComponentV2 = get_node_or_null("JumpSFX")
onready var footstep_detector: FootstepDetector = get_node_or_null("FootstepDetector")
var _footstep_sounds: Array = []

# --- IK TARGETS ---
var left_hand_target := Vector3.ZERO
var right_hand_target := Vector3.ZERO
var left_foot_target := Vector3.ZERO
var right_foot_target := Vector3.ZERO
var _left_hand_target_smoothed := Vector3.ZERO
var _right_hand_target_smoothed := Vector3.ZERO
var _hand_targets_initialized := false

# --- STATE ---
# Almacena la velocidad suavizada para el blend tree de animación.
var visual_velocity: Vector3 = Vector3.ZERO
var was_on_floor_last_frame: bool = true
var time_since_jump: float = 0.0
var last_air_vertical_speed: float = 0.0 # Guarda la velocidad vertical del último frame en el aire
var airborne_time: float = 0.0
var jumped_buffer_time: float = 0.0
var acrobatic_trigger_active: bool = false # Latch para garantizar que la SM vea el trigger
var acrobatic_trigger_frames_left: int = 0 # Hold trigger to survive frame ordering between controller and animator.
var is_rotation_locked: bool = false # Impide que el personaje rote durante maniobras (backflip)
var hit_head_active: bool = false
var current_push_time: float = 0.0
var _override_sequence_id: int = 0
var _transition_freeze_frames: int = 0  # inhibit all animation updates during scene transitions
var _transition_freeze_until_grounded: bool = false

# --- FOOTSTEPS ---
var _distance_accumulator: float = 0.0
var _last_world_pos: Vector3 = Vector3.ZERO
var _has_last_world_pos: bool = false
var _footstep_stop_grace_left := 0.0
var _manual_animtree_step_enabled := false
var _manual_animtree_step_accum := 0.0
var _anim_tree_param_cache := {}
var _climb_playback_scale := 1.0
var _climb_direction_blend := 1.0
var _last_anim_dt := 0.0
var _climb_pose_blend := 0.0
var _was_climbing_anim_last_frame := false
const FOOTSTEP_STOP_GRACE_SEC := 0.18
const MANUAL_ANIMTREE_STEP_INTERVAL_HYPER_LOW := 1.0 / 12.0
const ANIM_PARAM_FLOAT_EPSILON := 0.0005
const ANIM_BLEND_PARAM_FLOAT_EPSILON := 0.035

# --- LIFECYCLE ---
func _ready() -> void:
	# Asignar controller de forma segura (dos niveles arriba: Pivot -> Visual -> Pilot)
	controller = get_parent().get_parent() if get_parent() and get_parent().get_parent() else null
	
	# DEBUG: Setup Gizmo
	_setup_debug_gizmo()
	
	# Validaciones para asegurar la correcta configuración de la escena.
	if not controller or not controller.has_method("get_wish_direction"):
		push_error("PilotAnimatorV2 debe ser hijo de un PlayerControllerV2 válido.")
		set_process(false)
		return
		 
	if not animation_tree:
		push_error("No se encontró un nodo AnimationTree como hijo del Pivot.")
		set_process(false)
		return

	# Conectar la señal de salto para manejar la animación de forma reactiva.
	controller.connect("jumped", self , "_on_controller_jumped")
	controller.connect("hit_ceiling", self , "_on_controller_hit_ceiling")
	if controller.has_signal("acrobatic_jumped"):
		controller.connect("acrobatic_jumped", self , "_on_controller_acrobatic_jumped")

	# Freeze on scene arrival to prevent not-grounded flicker during transitions
	var scene_mgr := get_node_or_null("/root/SceneManager")
	if scene_mgr and scene_mgr.has_signal("scene_ready"):
		if not scene_mgr.is_connected("scene_ready", self, "_on_scene_ready_freeze"):
			scene_mgr.connect("scene_ready", self, "_on_scene_ready_freeze")

	# Intentar obtener AnimationPlayer si existe (puede estar dentro de Skeleton)
	anim_player = get_node_or_null("AnimationPlayer")
	if not anim_player:
		anim_player = find_node("AnimationPlayer", true, false)
		
	if anim_player:
		_ensure_animation_loaded(CLIMB_UP_ANIM_NAME, CLIMB_UP_ANIM_PATH)
		_ensure_reversed_climb_animation()
		for anim_name in anim_player.get_animation_list():
			if "Loop" in anim_name or "Run" in anim_name or "Walk" in anim_name or "Idle" in anim_name or "Climb" in anim_name:
				var anim = anim_player.get_animation(anim_name)
				if anim:
					anim.loop = true
 
	var playback = animation_tree.get(PARAM_PLAYBACK) if animation_tree else null
	if playback:
		playback.start("Grounded")
	# Activating the AnimationTree safely
	animation_tree.active = true
	_anim_tree_param_cache.clear()

	# Warmup animations to cache blends
	_warmup_animations()
	
	# Cache footsteps
	var fs_node = get_node_or_null("FootstepSfx")
	if fs_node:
		for child in fs_node.get_children():
			if child is AudioStreamPlayer3D:
				_footstep_sounds.append(child)

	_last_world_pos = global_transform.origin
	_has_last_world_pos = true
	_configure_animation_runtime_policy()

func _warmup_animations() -> void:
	"""Fuerza el cacheo de las mezclas de Grounded e InAir avanzando el AnimationTree."""
	for _i in range(10):
		animation_tree.advance(0.001)

	
func play_override_animation(anim_name: String) -> void:
	"""Plays an animation. If it's a State in the AnimationTree, travels to it. Otherwise plays directly on AnimationPlayer."""
	
	# 1. Try AnimationTree State Machine first (Clean blending)
	if animation_tree and animation_tree.active:
		var root = animation_tree.tree_root
		if root is AnimationNodeStateMachine and root.has_node(anim_name):
			print("PilotAnimator: Traveling to AnimationTree State: ", anim_name)
			var playback = animation_tree.get(PARAM_PLAYBACK)
			if playback:
				# Use travel() for smooth blending via established transitions
				playback.travel(anim_name)
				return

	# 2. Fallback: Direct AnimationPlayer playback (Rigid, disables tree)
	if not anim_player or not anim_player.has_animation(anim_name):
		printerr("PilotAnimator: Animation/State not found: ", anim_name)
		return

	print("PilotAnimator: Playing override animation (Direct): ", anim_name)
	
	# Disable Tree to allow direct playback
	if animation_tree:
		animation_tree.active = false
	
	_override_sequence_id += 1
	var seq_id := _override_sequence_id
	anim_player.play(anim_name)
	
	# Wait for finish and restore
	yield (anim_player, "animation_finished")
	if seq_id != _override_sequence_id:
		return
	_restore_animation_tree_after_override()

func stop_override_animation() -> void:
	# Invalidate any coroutine waiting for animation_finished.
	_override_sequence_id += 1
	if anim_player and is_instance_valid(anim_player):
		var current_anim := String(anim_player.current_animation)
		var was_playing := anim_player.is_playing()
		if was_playing:
			anim_player.stop(false)
			# Resume any pending yields started by play_override_animation().
			anim_player.emit_signal("animation_finished", current_anim)
	_restore_animation_tree_after_override()

func _restore_animation_tree_after_override() -> void:
	if animation_tree:
		animation_tree.active = true
		# Force reset to grounded/idle to avoid T-pose flicker
		var playback = animation_tree.get(PARAM_PLAYBACK)
		if playback:
			playback.start("Grounded")

func step_animator(dt: float, p_current_velocity: Vector3) -> void:
	"""
	Actualiza todos los aspectos visuales del personaje.
	Debe ser llamado manualmente por el controlador después de cada 'step' de física.
	"""
	if _transition_freeze_frames > 0 or _transition_freeze_until_grounded:
		if _transition_freeze_frames > 0:
			_transition_freeze_frames -= 1
		# When freezing "until grounded", the grace-frame countdown only ends the
		# freeze once the player is actually back on the floor. While the player is
		# still flying between scenes we keep holding the pose; the instant it lands
		# (or if it was already grounded) the freeze releases, so there is no
		# moonwalk from a fixed multi-frame hold while walking on the ground.
		if _transition_freeze_until_grounded:
			var grounded: bool = controller.is_effectively_grounded() if controller.has_method("is_effectively_grounded") else controller.is_on_floor()
			if _transition_freeze_frames == 0 and grounded:
				_transition_freeze_until_grounded = false
		if _transition_freeze_frames == 0 and not _transition_freeze_until_grounded:
			airborne_time = 0.0 as float
			was_on_floor_last_frame = true
		return
	# Use is_effectively_grounded() to include stair-stepping grace period
	# This prevents animation flickering when climbing stairs
	var is_on_floor: bool = controller.is_effectively_grounded() if controller.has_method("is_effectively_grounded") else controller.is_on_floor()
	_last_anim_dt = dt
	# if is_on_floor != was_on_floor_last_frame:
	# 	print("DEBUG: Animator Grounded Shift: ", is_on_floor, " Controller on_floor: ", controller.is_on_floor())
	
	var wish_direction: Vector3 = controller.get_wish_direction()

	# Guardar la velocidad vertical mientras estamos en el aire para usarla al aterrizar
	if not is_on_floor:
		last_air_vertical_speed = p_current_velocity.y
		airborne_time += dt

	# Lógica de tiempo para flotación
	if is_on_floor:
		time_since_jump = 0.0
		if not was_on_floor_last_frame and airborne_time > 0.0 and airborne_time < stair_air_time_threshold and debug_stair_blend:
			print("[STAIR_BLEND] short_air suppressed: air_time=", airborne_time, " vy=", p_current_velocity.y)
	else:
		time_since_jump += dt

	# Actualizar buffer de salto (permite que is_jumping sea true por unos ms)
	if jumped_buffer_time > 0.0:
		jumped_buffer_time = max(0.0, jumped_buffer_time - dt)

	# 1. SUAVIZADO DE VELOCIDAD PARA ANIMACIÓN
	# Usamos la velocidad del controlador para el movimiento, pero una versión
	# suavizada para que las transiciones de animación (e.g., idle -> run) no sean abruptas.
	if dt > 0:
		visual_velocity = visual_velocity.linear_interpolate(p_current_velocity, velocity_lerp_speed * dt)
	else:
		visual_velocity = p_current_velocity
		
	# --- FOOTSTEP LOGIC ---
	var current_world_pos = global_transform.origin
	var planar_delta := 0.0
	if _has_last_world_pos:
		var move_delta = current_world_pos - _last_world_pos
		planar_delta = Vector2(move_delta.x, move_delta.z).length()
	_last_world_pos = current_world_pos
	_has_last_world_pos = true
	var has_locomotion_intent := _has_locomotion_intent()

	if _should_accumulate_footsteps(is_on_floor, planar_delta, has_locomotion_intent):
		# Use real traveled planar distance, not instantaneous velocity, to avoid step spam when oscillating in place.
		_distance_accumulator += planar_delta

		# Keep speed only for choosing stride profile (walk/run), not for counting distance.
		var speed_h = Vector2(p_current_velocity.x, p_current_velocity.z).length()
		var current_stride = 0.9
		var walk_threshold = 3.0
		if footstep_detector:
			current_stride = footstep_detector.stride_length_walk
			walk_threshold = footstep_detector.walk_speed_threshold
			if speed_h > walk_threshold:
				var t = clamp((speed_h - walk_threshold) / walk_threshold, 0.0, 1.0)
				current_stride = lerp(footstep_detector.stride_length_walk, footstep_detector.stride_length_run, t)
		elif speed_h > walk_threshold:
			var t = clamp((speed_h - walk_threshold) / walk_threshold, 0.0, 1.0)
			current_stride = lerp(0.9, 2.0, t)

		if _distance_accumulator >= current_stride:
			_distance_accumulator -= current_stride # Keep residue for precise rhythm
			_play_footstep()
	else:
		_distance_accumulator = 0.0 # Reset in air so we don't step immediately on land (unless land sound handles that)
	_update_footstep_playback_guard(is_on_floor, planar_delta, dt, has_locomotion_intent)

	# 2. ROTACIÓN VISUAL SUAVE (YAW)
	# Solo rotamos si no estamos bloqueados (durante backflip)
	if not is_rotation_locked:
		var traversal = controller.get("traversal_logic") if controller else null
		if traversal and traversal.is_climbing:
			# ALINEACIÓN DE ESCALADA
			# Miramos HACIA la escalera: Forward (-Z) = -climb_normal
			var climb_normal = traversal.ladder_normal
			if climb_normal.length_squared() > 0.001:
				var look_dir = - climb_normal
				var parent_basis = get_parent().global_transform.basis
				var local_look = parent_basis.xform_inv(look_dir)
				# En Godot, -Z es adelante. Para que -Z apunte a local_look,
				# el ángulo en Y debe ser atan2(local_look.x, local_look.z) + PI
				var target_angle = atan2(local_look.x, local_look.z) + PI
				if dt > 0:
					rotation.y = lerp_angle(rotation.y, target_angle, rotation_lerp_speed * 1.5 * dt)
				else:
					rotation.y = target_angle
		elif controller.get("is_pushing"):
			# ALINEACIÓN DE EMPUJE (Soft Snap -> Strict Snap)
			# Miramos opuesto a la normal de la superficie (hacia la caja)
			var push_normal = controller.get("push_normal")
			var look_dir = - push_normal
			var parent_basis = get_parent().global_transform.basis
			var local_look = parent_basis.xform_inv(look_dir)
			
			var target_angle = atan2(local_look.x, local_look.z)
			# STRICT ALIGNMENT: Force snap immediately when pushing to ensure Z-axis aligns with push normal.
			# Any misalignment causes the Z-offset to slide sideways instead of pulling back.
			rotation.y = target_angle

		else:
			var horizontal_wish_direction = wish_direction * Vector3(1, 0, 1)

			# Validamos longitud en global para saber si hay intención
			if horizontal_wish_direction.length_squared() > 0.01:
				# Convertimos la dirección global deseada al espacio local del padre (Visual/Pilot)
				# Esto corrige el bug donde el mesh rotaba usando coordenadas globales ignorando la rotación del Pilot node.
				var parent_basis = get_parent().global_transform.basis
				var local_wish = parent_basis.xform_inv(wish_direction)

				var target_angle = atan2(local_wish.x, local_wish.z)
				if dt > 0: # Suavizado en modo LIVE.
					rotation.y = lerp_angle(rotation.y, target_angle, rotation_lerp_speed * dt)
				else: # Aplicación instantánea en modo REPLAY.
					rotation.y = target_angle


	# Desbloquear rotación al aterrizar
	if is_on_floor and is_rotation_locked and not acrobatic_trigger_active:
		is_rotation_locked = false

	# 4. PUSH COMPENSATION (Arm Offset + Foot Sliding Fix)
	var is_pushing = controller.get("is_pushing") if controller else false
	var push_direction = Vector3.ZERO
	# Si estamos empujando, asumimos que es hacia adelante relativo a nuestra rotación actual
	if is_pushing:
		push_direction = global_transform.basis.z # Z is forward in Godot Spatial? No, -Z is forward. But let's check basis.
		# Actually, PilotAnimatorV2 rotates the Spatial. 
		# If the character faces the box, the push direction is the direction the character is facing.
		# In Godot -Z is forward.
		push_direction = - global_transform.basis.z

	_update_push_animation_offset(dt, is_pushing, push_direction)
	update_animation_parameters(p_current_velocity, is_on_floor, controller.get_wish_direction().length())
	_update_climb_visual_state(dt)
	_update_climb_pose_correction(dt)
	_advance_animation_tree_if_manual(dt)

	was_on_floor_last_frame = is_on_floor and not (controller.traversal_logic.is_climbing if controller and controller.get("traversal_logic") else false) and not (controller.traversal_logic.is_hanging if controller and controller.get("traversal_logic") else false)

func snap_visual_to_direction(world_direction: Vector3) -> void:
	var horizontal_direction := world_direction
	horizontal_direction.y = 0.0
	if horizontal_direction.length_squared() <= 0.0001:
		return
	horizontal_direction = horizontal_direction.normalized()
	var parent_basis = get_parent().global_transform.basis if get_parent() else Basis()
	var local_direction: Vector3 = parent_basis.xform_inv(horizontal_direction)
	rotation.y = atan2(local_direction.x, local_direction.z)
	is_rotation_locked = false


func update_animation_parameters(velocity: Vector3, is_on_floor: bool, move_vec_length: float) -> void:
	if not animation_tree:
		return

	# Traversal State Integration
	var is_climbing = controller.traversal_logic.is_climbing if controller and controller.get("traversal_logic") else false
	var is_hanging = controller.traversal_logic.is_hanging if controller and controller.get("traversal_logic") else false
	var traversal_locked: bool = is_climbing or is_hanging
	var is_zero_g := false
	if controller:
		var cm = controller.get_node_or_null("ControllerManager")
		if cm and cm.get("current_mode") == cm.Mode.ZERO_GRAVITY:
			is_zero_g = true
	var anim_on_floor: bool = is_on_floor and not traversal_locked and not is_zero_g
	var climb_exit_air: bool = _was_climbing_anim_last_frame and not is_climbing and not is_on_floor and not is_zero_g

	_set_anim_tree_param(PARAM_CONDITIONS_IS_CLIMBING, is_climbing)
	_set_anim_tree_param(PARAM_CONDITIONS_NOT_CLIMBING, not is_climbing)
	_set_anim_tree_param(PARAM_CONDITIONS_IS_HANGING, is_hanging)
	_set_anim_tree_param(PARAM_CONDITIONS_CLIMB_EXIT_AIR, climb_exit_air)

	# Actualizar condiciones básicas
	_set_anim_tree_param(PARAM_CONDITIONS_ON_FLOOR, anim_on_floor)
	_set_anim_tree_param(PARAM_CONDITIONS_NOT_ON_FLOOR, not anim_on_floor)

	# Push State (highest priority over crouch)
	var is_pushing = controller.get("is_pushing") if controller else false
	_set_anim_tree_param(PARAM_CONDITIONS_IS_PUSHING, is_pushing)
	_set_anim_tree_param(PARAM_CONDITIONS_NOT_PUSHING, not is_pushing)

	# Keep acrobatic trigger alive for a couple of frames.
	acrobatic_trigger_active = acrobatic_trigger_frames_left > 0

	# Crouch State
	# If acrobatic is armed this frame, force crouch off to avoid competing transitions.
	var is_crouching: bool = true if controller and controller.get("is_crouching") and not is_pushing and not acrobatic_trigger_active else false
	_set_anim_tree_param(PARAM_CONDITIONS_IS_CROUCHED, is_crouching)
	_set_anim_tree_param(PARAM_CONDITIONS_NOT_CROUCHED, not is_crouching)

	# Estados de salto/caída usando la velocidad registrada en el último frame en aire.
	# IMPORTANTE: Forzamos false si estamos en el suelo (evita flickering en escaleras).
	var effective_airborne: bool = (not anim_on_floor) and (not traversal_locked) and airborne_time >= stair_air_time_threshold

	if is_zero_g:
		effective_airborne = true

	var is_falling: bool = last_air_vertical_speed < -1.0 and effective_airborne
	
	# is_jumping: true si acabamos de disparar el salto (buffer) o si estamos subiendo en aire
	# IMPORTANTE: También forzamos false si estamos en el suelo para evitar saltos visuales en escaleras.
	var is_jumping_param: bool = ((jumped_buffer_time > 0.0) or (effective_airborne and velocity.y > 1.0)) and effective_airborne
	
	# PRIORIDAD ABSOLUTA AL BACKFLIP:
	# Si el latch acrobático está armado, forzamos is_jumping a false.
	# Esto obliga a la StateMachine a ignorar el salto normal y tomar la transición 'is_acrobatic'.
	if acrobatic_trigger_active or is_zero_g:
		is_jumping_param = false

	var is_floating: bool = effective_airborne and not is_falling and not is_jumping_param

	_set_anim_tree_param(PARAM_CONDITIONS_IS_FALLING, is_falling)
	_set_anim_tree_param(PARAM_CONDITIONS_IS_FLOATING, is_floating)

	# Falling Fast
	var is_falling_fast: bool = last_air_vertical_speed < -12.0 and effective_airborne
	_set_anim_tree_param(PARAM_CONDITIONS_IS_FALLING_FAST, is_falling_fast)
		
	_set_anim_tree_param(PARAM_CONDITIONS_IS_JUMPING, is_jumping_param)
	
	# Resetear trigger acrobático usando el latch
	if acrobatic_trigger_active:
		if debug_animation_events:
			print("PilotAnimator: Sending is_acrobatic = TRUE to AnimationTree")
		_set_anim_tree_param(PARAM_CONDITIONS_IS_ACROBATIC, true)
		acrobatic_trigger_frames_left -= 1
		if acrobatic_trigger_frames_left <= 0:
			acrobatic_trigger_active = false
	else:
		_set_anim_tree_param(PARAM_CONDITIONS_IS_ACROBATIC, false)
	
	# Hit Head condition (one-shot, cleared after this frame)
	_set_anim_tree_param(PARAM_CONDITIONS_HIT_HEAD, hit_head_active)
	hit_head_active = false

	# Emitir land_soft / land_hard SOLO en el frame de aterrizaje (edge detect)
	var landed_now: bool = anim_on_floor and not was_on_floor_last_frame and airborne_time >= stair_air_time_threshold
	var land_soft: bool = landed_now and last_air_vertical_speed >= -1.0
	var land_hard: bool = landed_now and last_air_vertical_speed < -1.0

	_set_anim_tree_param(PARAM_CONDITIONS_LAND_SOFT, land_soft)
	_set_anim_tree_param(PARAM_CONDITIONS_LAND_HARD, land_hard)

	# Parámetro para la mezcla de locomoción (Idle/Walk/Run).
	# Usa la magnitud de la velocidad horizontal suavizada.
	var blend_pos = Vector2(visual_velocity.x, visual_velocity.z).length()
	if is_climbing or is_hanging:
		# Use anim_progress from traversal logic for climbing/hanging blend
		blend_pos = controller.traversal_logic.anim_progress if controller and controller.get("traversal_logic") else 0.0

	_set_anim_tree_param(PARAM_GROUNDED_BLEND_POSITION, blend_pos, ANIM_BLEND_PARAM_FLOAT_EPSILON)
	_set_anim_tree_param(PARAM_CROUCHED_BLEND_POSITION, blend_pos, ANIM_BLEND_PARAM_FLOAT_EPSILON)

	# Update IK Targets for Traversal
	if is_hanging:
		_update_hanging_ik()
	elif is_climbing and enable_climbing_ik and _should_apply_climbing_ik():
		_update_climbing_ik()
	else:
		_clear_hand_ik_overrides()

	# Selección entre JumpLoop y FloatLoop: usar JumpLoop si saltamos recientemente
	# o si hay entrada de movimiento significativa.
	var use_jump_loop: bool = (time_since_jump < 0.25) or (move_vec_length > 0.3)
	if is_zero_g:
		use_jump_loop = velocity.length() > 0.35
	_set_anim_tree_param(PARAM_CONDITIONS_USE_JUMP_LOOP, use_jump_loop)

	# Lógica de transición de Salto (Start vs Land)
	# Solo pasamos a Land (1) si tocamos el suelo antes de que termine el estado visual de salto.
	# No pasamos a Land al soltar el botón (Short Jump), para mantener el arco visual en el aire.
	# IMPORTANTE: Forzamos 1 (Land/Grounded) si estamos en el suelo.
	var jump_transition = 1 if anim_on_floor else 0
	_set_anim_tree_param(PARAM_JUMP_TRANSITION_CURRENT, jump_transition)

	if anim_on_floor:
		airborne_time = 0.0
	_was_climbing_anim_last_frame = is_climbing


func _on_controller_jumped() -> void:
	"""Se ejecuta cuando el controlador emite la señal 'jumped'."""
	# Activamos el salto normal.
	# Aseguramos que la transición interna del estado Jump (si aún existe) esté en start
	# O simplemente confiamos en el estado Jump por defecto.
	# animation_tree.set(PARAM_JUMP_TRANSITION_TYPE, 0) # Opcional si limpiaste el nodo Jump
	
	# Usar ONE_SHOT_REQUEST_FIRE es la forma correcta y determinista de activar animaciones OneShot.
	# NO NO NO NO ES ACTIVE 1
	_set_anim_tree_param(PARAM_GROUNDED_JUMP_ACTIVE, 1, 0.0) # NO TOCAR (Legacy logic, mantener si es necesario para compatibilidad)

	# Activar buffer de salto para mantener `is_jumping` verdadero algunos ms
	jumped_buffer_time = jump_buffer_duration

	if jump_sfx:
		jump_sfx.play_sfx()

func _on_controller_hit_ceiling() -> void:
	"""Se ejecuta cuando el controlador emite la señal 'hit_ceiling'."""
	hit_head_active = true

func _update_hanging_ik():
	if not controller or not controller.traversal_logic: return
	var anchor = controller.traversal_logic.ledge_anchor_point
	var normal = controller.traversal_logic.ledge_normal
	var tangent = normal.cross(Vector3.UP).normalized()

	# Hands snapped to ledge
	left_hand_target = anchor - tangent * 0.3
	right_hand_target = anchor + tangent * 0.3
	_update_smoothed_hand_targets(left_hand_target, right_hand_target)

	_apply_arm_ccd_ik("LeftHand", _left_hand_target_smoothed)
	_apply_arm_ccd_ik("RightHand", _right_hand_target_smoothed)

func _update_climbing_ik():
	if not controller or not controller.traversal_logic: return
	var progress = controller.traversal_logic.anim_progress
	var ladder = _find_active_ladder_node()
	if ladder and ladder.has_method("get_climb_hand_targets"):
		var world_y = global_transform.origin.y + climb_hand_height_offset
		var targets = ladder.get_climb_hand_targets(world_y, progress, climb_hand_target_half_width)
		left_hand_target = targets.get("left", global_transform.origin)
		right_hand_target = targets.get("right", global_transform.origin)
	else:
		var anchor = controller.traversal_logic.ladder_anchor_point
		var lateral = controller.traversal_logic.ladder_normal.cross(Vector3.UP).normalized()
		if lateral.length_squared() <= 0.0001:
			lateral = Vector3.RIGHT
		var step_y = floor(progress * 2.0)
		left_hand_target = anchor + Vector3.UP * (step_y * 0.4) - lateral * climb_hand_target_half_width
		right_hand_target = anchor + Vector3.UP * ((1.0 - step_y) * 0.4) + lateral * climb_hand_target_half_width

	_update_smoothed_hand_targets(left_hand_target, right_hand_target)
	_apply_arm_ccd_ik("LeftHand", _left_hand_target_smoothed)
	_apply_arm_ccd_ik("RightHand", _right_hand_target_smoothed)

func _should_apply_climbing_ik() -> bool:
	if not controller or not controller.get("traversal_logic"):
		return false
	var traversal = controller.get("traversal_logic")
	if traversal == null or not traversal.is_climbing:
		return false
	return bool(traversal._ladder_attach_active) or float(traversal.climb_motion_amount) > climb_idle_motion_threshold

func _apply_arm_ccd_ik(bone_name: String, target_world_pos: Vector3) -> void:
	if not _skeleton: return
	var resolved_bone_name = _resolve_ik_bone_name(bone_name)
	var hand_idx = _skeleton.find_bone(resolved_bone_name)
	if hand_idx == -1: return

	var forearm_idx = _skeleton.get_bone_parent(hand_idx)
	if forearm_idx == -1: return
	var upper_arm_idx = _skeleton.get_bone_parent(forearm_idx)
	if upper_arm_idx == -1: return

	var local_target = _skeleton.global_transform.affine_inverse().xform(target_world_pos)
	_rotate_bone_effector_towards_target(forearm_idx, hand_idx, local_target, climb_hand_ik_forearm_weight)
	_rotate_bone_effector_towards_target(upper_arm_idx, hand_idx, local_target, climb_hand_ik_upper_arm_weight)

func _update_smoothed_hand_targets(left_target: Vector3, right_target: Vector3) -> void:
	if not _hand_targets_initialized or _last_anim_dt <= 0.0:
		_left_hand_target_smoothed = left_target
		_right_hand_target_smoothed = right_target
		_hand_targets_initialized = true
		return
	var t = clamp(climb_hand_target_lerp_speed * _last_anim_dt, 0.0, 1.0)
	_left_hand_target_smoothed = _left_hand_target_smoothed.linear_interpolate(left_target, t)
	_right_hand_target_smoothed = _right_hand_target_smoothed.linear_interpolate(right_target, t)

func _rotate_bone_effector_towards_target(bone_idx: int, effector_idx: int, local_target: Vector3, weight: float) -> void:
	if bone_idx < 0 or effector_idx < 0 or weight <= 0.0:
		return
	var bone_pose = _skeleton.get_bone_global_pose(bone_idx)
	var effector_pose = _skeleton.get_bone_global_pose(effector_idx)
	var bone_origin = bone_pose.origin
	var current_dir = effector_pose.origin - bone_origin
	var target_dir = local_target - bone_origin
	if current_dir.length_squared() <= 0.00001 or target_dir.length_squared() <= 0.00001:
		return
	current_dir = current_dir.normalized()
	target_dir = target_dir.normalized()
	var dot_val = clamp(current_dir.dot(target_dir), -1.0, 1.0)
	if dot_val >= 0.9999:
		return
	var axis = current_dir.cross(target_dir)
	if axis.length_squared() <= 0.00001:
		return
	axis = axis.normalized()
	var angle = acos(dot_val) * clamp(weight, 0.0, 1.0)
	angle = min(angle, deg2rad(climb_hand_ik_max_step_deg))
	bone_pose.basis = bone_pose.basis.rotated(axis, angle)
	_skeleton.set_bone_global_pose_override(bone_idx, bone_pose, 1.0, true)

func _clear_hand_ik_overrides() -> void:
	if not _skeleton:
		return
	_hand_targets_initialized = false
	_clear_hand_chain_override("LeftHand")
	_clear_hand_chain_override("RightHand")

func _clear_hand_chain_override(bone_name: String) -> void:
	var hand_idx = _skeleton.find_bone(_resolve_ik_bone_name(bone_name))
	if hand_idx == -1:
		return
	_clear_bone_override(hand_idx)
	var forearm_idx = _skeleton.get_bone_parent(hand_idx)
	if forearm_idx != -1:
		_clear_bone_override(forearm_idx)
		var upper_arm_idx = _skeleton.get_bone_parent(forearm_idx)
		if upper_arm_idx != -1:
			_clear_bone_override(upper_arm_idx)

func _clear_bone_override(bone_idx: int) -> void:
	if bone_idx < 0:
		return
	var pose = _skeleton.get_bone_global_pose(bone_idx)
	_skeleton.set_bone_global_pose_override(bone_idx, pose, 0.0, true)

func _resolve_ik_bone_name(bone_name: String) -> String:
	if not _skeleton:
		return bone_name
	var candidates := [bone_name]
	match bone_name:
		"LeftHand":
			candidates = ["DEF-handL", "LeftHand", "Hand.L", "mixamorig:LeftHand"]
		"RightHand":
			candidates = ["DEF-handR", "RightHand", "Hand.R", "mixamorig:RightHand"]
	for candidate in candidates:
		if _skeleton.find_bone(candidate) != -1:
			return candidate
	return bone_name

func _find_active_ladder_node() -> Node:
	if not controller or not controller.get("traversal_logic"):
		return null
	var traversal = controller.get("traversal_logic")
	if traversal == null or not traversal.is_climbing:
		return null
	var ladders = get_tree().get_nodes_in_group("ladder")
	var best = null
	var best_dist := INF
	for ladder in ladders:
		if not is_instance_valid(ladder):
			continue
		if not ladder.has_method("get_climb_anchor"):
			continue
		var anchor = ladder.get_climb_anchor()
		var dist = anchor.distance_squared_to(traversal.ladder_anchor_point)
		if dist < best_dist:
			best_dist = dist
			best = ladder
	return best

func _ensure_animation_loaded(anim_name: String, anim_path: String) -> void:
	if not anim_player:
		return
	if anim_player.has_animation(anim_name):
		return
	if not ResourceLoader.exists(anim_path):
		return
	var loaded = load(anim_path)
	if loaded is Animation:
		anim_player.add_animation(anim_name, loaded)

func _ensure_reversed_climb_animation() -> void:
	if not anim_player:
		return
	if anim_player.has_animation(CLIMB_DOWN_ANIM_NAME):
		return
	_ensure_animation_loaded(CLIMB_UP_ANIM_NAME, CLIMB_UP_ANIM_PATH)
	if not anim_player.has_animation(CLIMB_UP_ANIM_NAME):
		return
	var source: Animation = anim_player.get_animation(CLIMB_UP_ANIM_NAME)
	if source == null:
		return
	var reversed := Animation.new()
	reversed.length = source.length
	reversed.loop = true
	reversed.step = source.step
	for track_idx in range(source.get_track_count()):
		var track_type = source.track_get_type(track_idx)
		var new_track_idx = reversed.add_track(track_type)
		reversed.track_set_path(new_track_idx, source.track_get_path(track_idx))
		reversed.track_set_interpolation_type(new_track_idx, source.track_get_interpolation_type(track_idx))
		reversed.track_set_interpolation_loop_wrap(new_track_idx, source.track_get_interpolation_loop_wrap(track_idx))
		reversed.track_set_enabled(new_track_idx, source.track_is_enabled(track_idx))
		var key_count = source.track_get_key_count(track_idx)
		for key_idx in range(key_count):
			var source_time = source.track_get_key_time(track_idx, key_idx)
			var reversed_time = source.length - source_time
			if reversed_time >= source.length - 0.0001:
				reversed_time = 0.0
			match track_type:
				Animation.TYPE_TRANSFORM:
					var value = source.transform_track_interpolate(track_idx, source_time)
					if value is Array and value.size() >= 3:
						reversed.transform_track_insert_key(new_track_idx, reversed_time, value[0], value[1], value[2])
				Animation.TYPE_VALUE:
					reversed.track_insert_key(new_track_idx, reversed_time, source.track_get_key_value(track_idx, key_idx), source.track_get_key_transition(track_idx, key_idx))
				Animation.TYPE_METHOD:
					reversed.track_insert_key(new_track_idx, reversed_time, source.track_get_key_value(track_idx, key_idx), source.track_get_key_transition(track_idx, key_idx))
				Animation.TYPE_BEZIER:
					reversed.bezier_track_insert_key(
						new_track_idx,
						reversed_time,
						source.track_get_key_value(track_idx, key_idx),
						source.bezier_track_get_key_in_handle(track_idx, key_idx),
						source.bezier_track_get_key_out_handle(track_idx, key_idx)
					)
				Animation.TYPE_AUDIO:
					reversed.track_insert_key(new_track_idx, reversed_time, source.track_get_key_value(track_idx, key_idx), source.track_get_key_transition(track_idx, key_idx))
				Animation.TYPE_ANIMATION:
					reversed.track_insert_key(new_track_idx, reversed_time, source.track_get_key_value(track_idx, key_idx), source.track_get_key_transition(track_idx, key_idx))
	anim_player.add_animation(CLIMB_DOWN_ANIM_NAME, reversed)

func _on_controller_acrobatic_jumped() -> void:
	"""Trigger Backflip State via is_acrobatic condition."""
	if animation_tree:
		if debug_animation_events:
			print("PilotAnimator: Controller signal received. Arming ACROBATIC latch.")
		# Activamos el latch para que update_animation_parameters lo procese en el momento correcto
		acrobatic_trigger_active = true
		acrobatic_trigger_frames_left = 2
		
		# BLOQUEO DE ROTACIÓN:
		# Miramos opuesto al movimiento para realizar el backflip hacia atrás
		var move_dir = controller.get_wish_direction()
		if move_dir.length_squared() > 0.01:
			var look_dir = - move_dir # Global look direction
			
			# Convertir a espacio local del padre
			var parent_basis = get_parent().global_transform.basis
			var local_look = parent_basis.xform_inv(look_dir)
			
			var target_angle = atan2(local_look.x, local_look.z)
			
			# SOLO forzamos el snap si estamos mirando a más de 45 grados del objetivo
			# Calculamos la diferencia de angulo manualmente (compatible con Godot 3)
			var diff = fposmod(target_angle - rotation.y + PI, PI * 2) - PI
			if abs(diff) > deg2rad(45):
				rotation.y = target_angle
				
			is_rotation_locked = true # Bloquear hasta aterrizar
			if debug_animation_events:
				print("PilotAnimator: Backflip LOCKED orientation")
		
		if jump_sfx:
			jump_sfx.play_sfx()
		
		# IMPORTANTE: NO configuramos jumped_buffer_time aquí para evitar que 'is_jumping' se active
		# y compita con 'is_acrobatic'. Queremos ir SOLO al estado Acrobatic.

func _update_push_animation_offset(dt: float, is_pushing: bool, _push_direction: Vector3) -> void:
	# Note: translation.z is safe because we align rotation to face the box.
	if is_pushing:
		current_push_time += dt
		var delay_denom = push_start_delay if push_start_delay > 0.001 else 0.001
		var delay_factor = clamp(current_push_time / delay_denom, 0.0, 1.0)
		
		# Visual Anchoring: Add correction to Z (move backwards)
		var correction = 0.0
		if controller and "visual_push_correction" in controller:
			correction = controller.visual_push_correction
			
		var target_dist = push_arm_length_offset + correction
		
		# GEOMETRIC FIX: Use the actual push normal to determine the pullback direction in LOCAL space.
		# This ensures we move backwards relative to the BOX, regardless of Parent rotation.
		var push_normal = controller.push_normal if controller.get("push_normal") else -controller.global_transform.basis.z
		# push_normal points OUT of the box (towards player). This is our desired "Backwards" direction.
		
		# Convert global push_normal to Parent's (Visual) local space to apply translation
		var parent_basis = get_parent().global_transform.basis
		var local_back_dir = parent_basis.xform_inv(push_normal).normalized()
		
		var target_pos = local_back_dir * target_dist
		
		# DEBUG: Update Gizmo
		if _debug_sphere:
			_debug_sphere.visible = debug_push_gizmo
			_debug_sphere.visible = debug_push_gizmo
			_debug_sphere.translation = target_pos
		
		_update_hand_gizmos()
		
		# If we have a significant correction, snap immediately to prevent clipping
		# otherwise use the smooth transition for the arm extension
		if correction > 0.01:
			translation = target_pos
		else:
			var current_speed = push_lerp_speed * (0.2 + 0.8 * delay_factor)
			translation = translation.linear_interpolate(target_pos, clamp(current_speed * dt, 0.0, 1.0))
	else:
		current_push_time = 0.0
		if _debug_sphere: _debug_sphere.visible = false
		if _hand_l_gizmo: _hand_l_gizmo.visible = false
		if _hand_r_gizmo: _hand_r_gizmo.visible = false
		# Reset to origin smoothly
		translation = translation.linear_interpolate(Vector3.ZERO, clamp(push_lerp_speed * dt, 0.0, 1.0))

func _setup_debug_gizmo():
	# Create a visual marker for the anchor point
	_debug_sphere = MeshInstance.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	_debug_sphere.mesh = sphere
	var mat = SpatialMaterial.new()
	mat.albedo_color = Color(1, 0, 1) # Magenta for visibility
	mat.flags_unshaded = true
	mat.flags_no_depth_test = true # Always visible on top
	_debug_sphere.material_override = mat
	add_child(_debug_sphere)
	_debug_sphere.visible = false
	
	# Hand Gizmos
	_hand_l_gizmo = MeshInstance.new()
	_hand_l_gizmo.mesh = sphere
	_hand_l_gizmo.material_override = mat
	add_child(_hand_l_gizmo)
	_hand_l_gizmo.visible = false
	
	_hand_r_gizmo = MeshInstance.new()
	_hand_r_gizmo.mesh = sphere
	_hand_r_gizmo.material_override = mat
	add_child(_hand_r_gizmo)
	_hand_r_gizmo.visible = false
	
	# Find Skeleton
	var found_node = find_node("Skeleton", true, false)
	if found_node is Skeleton:
		_skeleton = found_node
	else:
		# Try looking in children of children indiscriminately for ANY Skeleton
		_skeleton = null # Reset
		# Breadth-first search for a Skeleton node
		var queue = [ self ]
		while not queue.empty():
			var curr = queue.pop_front()
			if curr is Skeleton:
				_skeleton = curr
				break
			# Add children to queue
			for child in curr.get_children():
				if child != _debug_sphere and child != _hand_l_gizmo and child != _hand_r_gizmo:
					queue.push_back(child)
	if _skeleton:
		_skeleton_base_translation = _skeleton.translation
		_skeleton_base_basis = _skeleton.transform.basis

func _update_climb_visual_state(dt: float) -> void:
	if not controller or not controller.get("traversal_logic"):
		_restore_climb_visual_state(dt)
		return
	var traversal = controller.get("traversal_logic")
	if traversal == null:
		_restore_climb_visual_state(dt)
		return

	var target_playback_speed := 1.0
	var target_skeleton_translation := _skeleton_base_translation
	var target_skeleton_basis := _skeleton_base_basis
	var target_direction_blend := _climb_direction_blend
	if traversal.is_climbing:
		var is_climbing_moving: bool = bool(traversal._ladder_attach_active) or float(traversal.climb_motion_amount) > climb_idle_motion_threshold
		if is_climbing_moving:
			var climb_dir := float(traversal.climb_motion_direction)
			target_playback_speed = climb_motion_playback_scale
			if climb_dir < -0.01:
				target_direction_blend = 0.0
			elif climb_dir > 0.01:
				target_direction_blend = 1.0
		else:
			target_playback_speed = climb_idle_playback_scale
		if _skeleton and traversal.ladder_normal.length_squared() > 0.001:
			var world_offset = - traversal.ladder_normal.normalized() * climb_visual_wall_offset
			var local_offset = global_transform.basis.xform_inv(world_offset)
			local_offset.x += climb_visual_lateral_offset
			local_offset.y += climb_visual_vertical_offset
			target_skeleton_translation += local_offset
			target_skeleton_basis = _skeleton_base_basis.rotated(Vector3.RIGHT, deg2rad(climb_visual_pitch_deg))

	if dt > 0.0:
		_climb_playback_scale = lerp(_climb_playback_scale, target_playback_speed, clamp(climb_playback_lerp_speed * dt, 0.0, 1.0))
		_climb_direction_blend = lerp(_climb_direction_blend, target_direction_blend, clamp(climb_playback_lerp_speed * dt, 0.0, 1.0))
	else:
		_climb_playback_scale = target_playback_speed
		_climb_direction_blend = target_direction_blend
	_set_anim_tree_param(PARAM_CLIMBING_TIMESCALE, _climb_playback_scale, 0.0)
	_set_anim_tree_param(PARAM_CLIMBING_DIRECTION_BLEND, _climb_direction_blend, 0.0)
	if _skeleton:
		if dt > 0.0:
			_skeleton.translation = _skeleton.translation.linear_interpolate(
				target_skeleton_translation,
				clamp(climb_visual_offset_lerp_speed * dt, 0.0, 1.0)
			)
			var from_quat := Quat(_skeleton.transform.basis)
			var to_quat := Quat(target_skeleton_basis)
			var rot_t := clamp(climb_visual_offset_lerp_speed * dt, 0.0, 1.0)
			_skeleton.transform.basis = Basis(from_quat.slerp(to_quat, rot_t))
		else:
			_skeleton.translation = target_skeleton_translation
			_skeleton.transform.basis = target_skeleton_basis

func _restore_climb_visual_state(dt: float) -> void:
	_climb_playback_scale = 1.0
	_climb_direction_blend = 1.0
	_set_anim_tree_param(PARAM_CLIMBING_TIMESCALE, 1.0, 0.0)
	_set_anim_tree_param(PARAM_CLIMBING_DIRECTION_BLEND, 1.0, 0.0)
	if not _skeleton:
		return
	if dt > 0.0:
		_skeleton.translation = _skeleton.translation.linear_interpolate(
			_skeleton_base_translation,
			clamp(climb_visual_offset_lerp_speed * dt, 0.0, 1.0)
		)
		var from_quat := Quat(_skeleton.transform.basis)
		var to_quat := Quat(_skeleton_base_basis)
		var rot_t := clamp(climb_visual_offset_lerp_speed * dt, 0.0, 1.0)
		_skeleton.transform.basis = Basis(from_quat.slerp(to_quat, rot_t))
	else:
		_skeleton.translation = _skeleton_base_translation
		_skeleton.transform.basis = _skeleton_base_basis

func _update_climb_pose_correction(dt: float) -> void:
	if not _skeleton or not controller or not controller.get("traversal_logic"):
		_climb_pose_blend = 0.0
		_clear_climb_pose_corrections()
		return
	var traversal = controller.get("traversal_logic")
	var target_blend := 1.0 if traversal and traversal.is_climbing else 0.0
	if dt > 0.0:
		_climb_pose_blend = lerp(_climb_pose_blend, target_blend, clamp(climb_pose_correction_lerp_speed * dt, 0.0, 1.0))
	else:
		_climb_pose_blend = target_blend
	if _climb_pose_blend <= 0.001:
		_clear_climb_pose_corrections()
		return
	_apply_climb_pose_correction_to_bone("DEF-spine001", 0.0, 0.0, climb_spine_pitch_deg_1)
	_apply_climb_pose_correction_to_bone("DEF-spine002", 0.0, 0.0, climb_spine_pitch_deg_2)
	_apply_climb_pose_correction_to_bone("DEF-spine003", 0.0, 0.0, climb_spine_pitch_deg_3)
	_apply_climb_pose_correction_to_bone("DEF-thighL", 0.0, 0.0, climb_thigh_pitch_deg)
	_apply_climb_pose_correction_to_bone("DEF-thighR", 0.0, 0.0, climb_thigh_pitch_deg)
	_apply_climb_pose_correction_to_bone("DEF-shinL", 0.0, 0.0, climb_shin_pitch_deg)
	_apply_climb_pose_correction_to_bone("DEF-shinR", 0.0, 0.0, climb_shin_pitch_deg)
	_apply_climb_pose_correction_to_bone("DEF-shoulderL", climb_clavicle_out_deg_left, 0.0, 0.0)
	_apply_climb_pose_correction_to_bone("DEF-shoulderR", climb_clavicle_out_deg_right, 0.0, 0.0)
	_apply_climb_pose_correction_to_bone("DEF-upper_armL", climb_upper_arm_out_deg_left, climb_upper_arm_back_deg, 0.0)
	_apply_climb_pose_correction_to_bone("DEF-upper_armR", climb_upper_arm_out_deg_right, climb_upper_arm_back_deg, 0.0)

func _apply_climb_pose_correction_to_bone(bone_name: String, out_deg: float, back_deg: float, pitch_deg: float) -> void:
	var bone_idx = _skeleton.find_bone(bone_name)
	if bone_idx == -1:
		return
	_clear_bone_override(bone_idx)
	var pose = _skeleton.get_bone_global_pose(bone_idx)
	var out_angle = deg2rad(out_deg * _climb_pose_blend)
	var back_angle = deg2rad(back_deg * _climb_pose_blend)
	var pitch_angle = deg2rad(pitch_deg * _climb_pose_blend)
	var right_axis = pose.basis.x.normalized()
	var up_axis = pose.basis.y.normalized()
	var forward_axis = pose.basis.z.normalized()
	if right_axis.length_squared() > 0.0 and abs(pitch_angle) > 0.0001:
		pose.basis = pose.basis.rotated(right_axis, pitch_angle)
	if up_axis.length_squared() > 0.0 and abs(out_angle) > 0.0001:
		pose.basis = pose.basis.rotated(up_axis, out_angle)
	if forward_axis.length_squared() > 0.0 and abs(back_angle) > 0.0001:
		pose.basis = pose.basis.rotated(forward_axis, back_angle)
	_skeleton.set_bone_global_pose_override(bone_idx, pose, _climb_pose_blend, true)

func _clear_climb_pose_corrections() -> void:
	_clear_bone_override_by_name("DEF-spine001")
	_clear_bone_override_by_name("DEF-spine002")
	_clear_bone_override_by_name("DEF-spine003")
	_clear_bone_override_by_name("DEF-thighL")
	_clear_bone_override_by_name("DEF-thighR")
	_clear_bone_override_by_name("DEF-shinL")
	_clear_bone_override_by_name("DEF-shinR")
	_clear_bone_override_by_name("DEF-shoulderL")
	_clear_bone_override_by_name("DEF-shoulderR")
	_clear_bone_override_by_name("DEF-upper_armL")
	_clear_bone_override_by_name("DEF-upper_armR")

func _clear_bone_override_by_name(bone_name: String) -> void:
	var bone_idx = _skeleton.find_bone(bone_name)
	if bone_idx != -1:
		_clear_bone_override(bone_idx)

func _update_hand_gizmos():
	if not _skeleton or not debug_push_gizmo:
		if _hand_l_gizmo: _hand_l_gizmo.visible = false
		if _hand_r_gizmo: _hand_r_gizmo.visible = false
		return
		
	_hand_l_gizmo.visible = true
	_hand_r_gizmo.visible = true
	
	# Try mixamo/standard bone names
	var l_idx = _skeleton.find_bone("LeftHand")
	if l_idx == -1: l_idx = _skeleton.find_bone("Hand.L")
	if l_idx == -1: l_idx = _skeleton.find_bone("mixamorig:LeftHand")
	if l_idx == -1: l_idx = 12 # Fallback to standard index 12 (OYS default)
	
	var r_idx = _skeleton.find_bone("RightHand")
	if r_idx == -1: r_idx = _skeleton.find_bone("Hand.R")
	if r_idx == -1: r_idx = _skeleton.find_bone("mixamorig:RightHand")
	if r_idx == -1: r_idx = 22 # Fallback to standard index 22 (OYS default)
	
	if l_idx != -1 and l_idx < _skeleton.get_bone_count():
		# Get bone global pose relative to Skeleton
		var bone_pose = _skeleton.get_bone_global_pose(l_idx)
		# Transform to world space
		var global_bone = _skeleton.global_transform * bone_pose
		_hand_l_gizmo.global_transform.origin = global_bone.origin
		
	if r_idx != -1 and r_idx < _skeleton.get_bone_count():
		var bone_pose = _skeleton.get_bone_global_pose(r_idx)
		var global_bone = _skeleton.global_transform * bone_pose
		_hand_r_gizmo.global_transform.origin = global_bone.origin

func _play_footstep():
	_footstep_stop_grace_left = FOOTSTEP_STOP_GRACE_SEC
	if footstep_detector:
		if "stream_paused" in footstep_detector:
			footstep_detector.stream_paused = false
		if footstep_detector.playing:
			footstep_detector.stop()
		footstep_detector.play_footstep()
	elif not _footstep_sounds.empty():
		var idx = randi() % _footstep_sounds.size()
		var player = _footstep_sounds[idx]
		if player:
			if "stream_paused" in player:
				player.stream_paused = false
			if player.playing:
				player.stop()
			player.pitch_scale = rand_range(0.9, 1.1)
			player.play()

func _is_hyper_low_runtime() -> bool:
	var forced_device = OS.get_environment("ODISEA_DEVICE").to_lower().strip_edges()
	return forced_device.find("anbernic") != -1

func _configure_animation_runtime_policy() -> void:
	_manual_animtree_step_enabled = _is_hyper_low_runtime()
	if animation_tree == null:
		return
	_anim_tree_param_cache.clear()
	if _manual_animtree_step_enabled:
		animation_tree.process_mode = AnimationTree.ANIMATION_PROCESS_MANUAL
	else:
		animation_tree.process_mode = AnimationTree.ANIMATION_PROCESS_IDLE

func _set_anim_tree_param(path: String, value, float_epsilon := ANIM_PARAM_FLOAT_EPSILON) -> void:
	if animation_tree == null:
		return
	if _anim_tree_param_cache.has(path):
		var previous = _anim_tree_param_cache[path]
		if typeof(value) in [TYPE_REAL, TYPE_INT] and typeof(previous) in [TYPE_REAL, TYPE_INT]:
			if abs(float(previous) - float(value)) <= float(float_epsilon):
				return
		elif previous == value:
			return
	_anim_tree_param_cache[path] = value
	animation_tree.set(path, value)

func _advance_animation_tree_if_manual(dt: float) -> void:
	if not _manual_animtree_step_enabled:
		return
	if animation_tree == null or not animation_tree.active:
		return
	_manual_animtree_step_accum += max(0.0, dt)
	if _manual_animtree_step_accum < MANUAL_ANIMTREE_STEP_INTERVAL_HYPER_LOW:
		return
	var step_dt = _manual_animtree_step_accum
	_manual_animtree_step_accum = 0.0
	animation_tree.advance(step_dt)

func _update_footstep_playback_guard(is_on_floor: bool, planar_delta: float, dt: float, has_locomotion_intent: bool = false) -> void:
	_footstep_stop_grace_left = max(0.0, _footstep_stop_grace_left - max(0.0, dt))
	if _should_accumulate_footsteps(is_on_floor, planar_delta, has_locomotion_intent, 0.004):
		return
	if _footstep_stop_grace_left > 0.0:
		return
	_stop_footstep_audio_if_playing()

func _has_locomotion_intent() -> bool:
	if controller == null or not controller.has_method("get_wish_direction"):
		return false
	var wish_direction = controller.get_wish_direction()
	return typeof(wish_direction) == TYPE_VECTOR3 and wish_direction.length_squared() > 0.0001

func _should_accumulate_footsteps(is_on_floor: bool, planar_delta: float, has_locomotion_intent: bool, planar_threshold: float = 0.001) -> bool:
	if not is_on_floor or planar_delta <= planar_threshold:
		return false
	if not has_locomotion_intent:
		return false
	if controller and bool(controller.get("is_pushing")):
		return false
	return true

func _stop_footstep_audio_if_playing() -> void:
	if footstep_detector:
		if footstep_detector.playing:
			footstep_detector.stop()
	for player in _footstep_sounds:
		if player and is_instance_valid(player):
			if player.playing:
				player.stop()

# Suppress animation updates for N physics frames — use on scene transitions
# to prevent fall/jump poses from flickering during the loading gap.
func freeze(frames: int = 4) -> void:
	_transition_freeze_frames = max(_transition_freeze_frames, frames)
	_transition_freeze_until_grounded = true
	airborne_time = float(0)

func _on_scene_ready_freeze(_path, _scene_root, _params) -> void:
	print("[PilotAnim] _on_scene_ready_freeze path=", _path)
	_transition_freeze_until_grounded = true
	airborne_time = float(0)
