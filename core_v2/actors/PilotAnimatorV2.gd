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
onready var jump_sfx: SFXComponentV2 = get_node_or_null("JumpSFX")
onready var footstep_detector: FootstepDetector = get_node_or_null("FootstepDetector")
var _footstep_sounds: Array = []

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

# --- FOOTSTEPS ---
var _distance_accumulator: float = 0.0
var _last_world_pos: Vector3 = Vector3.ZERO
var _has_last_world_pos: bool = false

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
	controller.connect("jumped", self, "_on_controller_jumped")
	controller.connect("hit_ceiling", self, "_on_controller_hit_ceiling")
	if controller.has_signal("acrobatic_jumped"):
		controller.connect("acrobatic_jumped", self, "_on_controller_acrobatic_jumped")

	# Intentar obtener AnimationPlayer si existe (puede estar dentro de Skeleton)
	anim_player = get_node_or_null("AnimationPlayer")
	if not anim_player:
		anim_player = find_node("AnimationPlayer", true, false)
 
	var playback = animation_tree.get(PARAM_PLAYBACK) if animation_tree else null
	if playback:
		playback.start("Grounded")
	# Activating the AnimationTree safely
	animation_tree.active = true

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
	
	anim_player.play(anim_name)
	
	# Wait for finish and restore
	yield (anim_player, "animation_finished")
	
	if animation_tree:
		animation_tree.active = true
		# Force reset to grounded/idle to avoid T-pose flicker
		var playback = animation_tree.get(PARAM_PLAYBACK)
		if playback: playback.start("Grounded")

func step_animator(dt: float, p_current_velocity: Vector3) -> void:
	"""
	Actualiza todos los aspectos visuales del personaje.
	Debe ser llamado manualmente por el controlador después de cada 'step' de física.
	"""
	# Use is_effectively_grounded() to include stair-stepping grace period
	# This prevents animation flickering when climbing stairs
	var is_on_floor: bool = controller.is_effectively_grounded() if controller.has_method("is_effectively_grounded") else controller.is_on_floor()
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

	if is_on_floor and not controller.get("is_pushing"):
		# Use real traveled planar distance, not instantaneous velocity, to avoid step spam when oscillating in place.
		if planar_delta > 0.001:
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

	# 2. ROTACIÓN VISUAL SUAVE (YAW)
	# Solo rotamos si no estamos bloqueados (durante backflip)
	if not is_rotation_locked:
		if controller.get("is_pushing"):
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

	# 3. APLICACIÓN DE ESTADO AL ANIMATIONTREE
	update_animation_parameters(p_current_velocity, is_on_floor, controller.get_wish_direction().length())

	was_on_floor_last_frame = is_on_floor


func update_animation_parameters(velocity: Vector3, is_on_floor: bool, move_vec_length: float) -> void:
	if not animation_tree:
		return

	# Actualizar condiciones básicas
	animation_tree.set(PARAM_CONDITIONS_ON_FLOOR, is_on_floor)
	animation_tree.set(PARAM_CONDITIONS_NOT_ON_FLOOR, not is_on_floor)

	# Push State (highest priority over crouch)
	var is_pushing = controller.get("is_pushing") if controller else false
	animation_tree.set(PARAM_CONDITIONS_IS_PUSHING, is_pushing)
	animation_tree.set(PARAM_CONDITIONS_NOT_PUSHING, not is_pushing)

	# Keep acrobatic trigger alive for a couple of frames.
	acrobatic_trigger_active = acrobatic_trigger_frames_left > 0

	# Crouch State
	# If acrobatic is armed this frame, force crouch off to avoid competing transitions.
	var is_crouching: bool = true if controller and controller.get("is_crouching") and not is_pushing and not acrobatic_trigger_active else false
	animation_tree.set(PARAM_CONDITIONS_IS_CROUCHED, is_crouching)
	animation_tree.set(PARAM_CONDITIONS_NOT_CROUCHED, not is_crouching)

	# Estados de salto/caída usando la velocidad registrada en el último frame en aire.
	# IMPORTANTE: Forzamos false si estamos en el suelo (evita flickering en escaleras).
	var effective_airborne: bool = (not is_on_floor) and airborne_time >= stair_air_time_threshold
	var is_falling: bool = last_air_vertical_speed < -1.0 and effective_airborne
	var is_floating: bool = last_air_vertical_speed >= -1.0 and last_air_vertical_speed < 0.0 and effective_airborne

	animation_tree.set(PARAM_CONDITIONS_IS_FALLING, is_falling)
	animation_tree.set(PARAM_CONDITIONS_IS_FLOATING, is_floating)

	# Falling Fast
	var is_falling_fast: bool = last_air_vertical_speed < -12.0 and effective_airborne
	animation_tree.set(PARAM_CONDITIONS_IS_FALLING_FAST, is_falling_fast)

	# is_jumping: true si acabamos de disparar el salto (buffer) o si estamos subiendo en aire
	# IMPORTANTE: También forzamos false si estamos en el suelo para evitar saltos visuales en escaleras.
	var is_jumping_param: bool = ((jumped_buffer_time > 0.0) or (effective_airborne and velocity.y > 1.0)) and effective_airborne
	
	# PRIORIDAD ABSOLUTA AL BACKFLIP:
	# Si el latch acrobático está armado, forzamos is_jumping a false.
	# Esto obliga a la StateMachine a ignorar el salto normal y tomar la transición 'is_acrobatic'.
	if acrobatic_trigger_active:
		is_jumping_param = false
		
	animation_tree.set(PARAM_CONDITIONS_IS_JUMPING, is_jumping_param)
	
	# Resetear trigger acrobático usando el latch
	if acrobatic_trigger_active:
		if debug_animation_events:
			print("PilotAnimator: Sending is_acrobatic = TRUE to AnimationTree")
		animation_tree.set(PARAM_CONDITIONS_IS_ACROBATIC, true)
		acrobatic_trigger_frames_left -= 1
		if acrobatic_trigger_frames_left <= 0:
			acrobatic_trigger_active = false
	else:
		animation_tree.set(PARAM_CONDITIONS_IS_ACROBATIC, false)
	
	# Hit Head condition (one-shot, cleared after this frame)
	animation_tree.set(PARAM_CONDITIONS_HIT_HEAD, hit_head_active)
	hit_head_active = false

	# Emitir land_soft / land_hard SOLO en el frame de aterrizaje (edge detect)
	var landed_now: bool = is_on_floor and not was_on_floor_last_frame and airborne_time >= stair_air_time_threshold
	var land_soft: bool = landed_now and last_air_vertical_speed >= -1.0
	var land_hard: bool = landed_now and last_air_vertical_speed < -1.0

	animation_tree.set(PARAM_CONDITIONS_LAND_SOFT, land_soft)
	animation_tree.set(PARAM_CONDITIONS_LAND_HARD, land_hard)

	# Parámetro para la mezcla de locomoción (Idle/Walk/Run).
	# Usa la magnitud de la velocidad horizontal suavizada.
	var blend_pos = Vector2(visual_velocity.x, visual_velocity.z).length()
	animation_tree.set(PARAM_GROUNDED_BLEND_POSITION, blend_pos)
	animation_tree.set(PARAM_CROUCHED_BLEND_POSITION, blend_pos)

	# Selección entre JumpLoop y FloatLoop: usar JumpLoop si saltamos recientemente
	# o si hay entrada de movimiento significativa.
	var use_jump_loop: bool = (time_since_jump < 0.25) or (move_vec_length > 0.3)
	animation_tree.set(PARAM_CONDITIONS_USE_JUMP_LOOP, use_jump_loop)

	# Lógica de transición de Salto (Start vs Land)
	# Solo pasamos a Land (1) si tocamos el suelo antes de que termine el estado visual de salto.
	# No pasamos a Land al soltar el botón (Short Jump), para mantener el arco visual en el aire.
	# IMPORTANTE: Forzamos 1 (Land/Grounded) si estamos en el suelo.
	var jump_transition = 1 if is_on_floor else 0
	animation_tree.set(PARAM_JUMP_TRANSITION_CURRENT, jump_transition)

	if is_on_floor:
		airborne_time = 0.0


func _on_controller_jumped() -> void:
	"""Se ejecuta cuando el controlador emite la señal 'jumped'."""
	# Activamos el salto normal.
	# Aseguramos que la transición interna del estado Jump (si aún existe) esté en start
	# O simplemente confiamos en el estado Jump por defecto.
	# animation_tree.set(PARAM_JUMP_TRANSITION_TYPE, 0) # Opcional si limpiaste el nodo Jump
	
	# Usar ONE_SHOT_REQUEST_FIRE es la forma correcta y determinista de activar animaciones OneShot.
	# NO NO NO NO ES ACTIVE 1
	animation_tree.set(PARAM_GROUNDED_JUMP_ACTIVE, 1) # NO TOCAR (Legacy logic, mantener si es necesario para compatibilidad)

	# Activar buffer de salto para mantener `is_jumping` verdadero algunos ms
	jumped_buffer_time = jump_buffer_duration

	if jump_sfx:
		jump_sfx.play_sfx()

func _on_controller_hit_ceiling() -> void:
	"""Se ejecuta cuando el controlador emite la señal 'hit_ceiling'."""
	hit_head_active = true

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
		var queue = [self]
		while not queue.empty():
			var curr = queue.pop_front()
			if curr is Skeleton:
				_skeleton = curr
				break
			# Add children to queue
			for child in curr.get_children():
				if child != _debug_sphere and child != _hand_l_gizmo and child != _hand_r_gizmo:
					queue.push_back(child)

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
	if footstep_detector:
		footstep_detector.play_footstep()
	elif not _footstep_sounds.empty():
		var idx = randi() % _footstep_sounds.size()
		var player = _footstep_sounds[idx]
		if player and not player.playing:
			player.pitch_scale = rand_range(0.9, 1.1)
			player.play()
