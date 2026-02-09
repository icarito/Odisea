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
const PARAM_GROUNDED_JUMP_ACTIVE = "parameters/Grounded/Jump/active"
const PARAM_LAND_TRANSITION_CURRENT = "parameters/Land/Transition/current"
const PARAM_JUMP_TRANSITION_CURRENT = "parameters/Jump/Transition/current"
const PARAM_PLAYBACK_ACTIVE = "parameters/playback/active"
const PARAM_CONDITIONS_IS_ACROBATIC = "parameters/conditions/is_acrobatic"

# --- EXPORTS ---
# Velocidad de suavizado para la velocidad usada en el AnimationTree.
export var velocity_lerp_speed: float = 5.0
# Velocidad de suavizado para la rotación visual del personaje.
export var rotation_lerp_speed: float = 10.0
# Velocidad de suavizado para la inclinación (tilt) vertical.
export var tilt_lerp_speed: float = 5.0
# Ángulo máximo de inclinación en grados.
export var max_tilt_angle: float = 25.0
# Duración en segundos durante la cual consideramos que el salto acaba de iniciarse (buffer)
export var jump_buffer_duration: float = 0.18

# --- NODES ---
var controller: Node = null
onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree")
var anim_player: AnimationPlayer = null

# --- STATE ---
# Almacena la velocidad suavizada para el blend tree de animación.
var visual_velocity: Vector3 = Vector3.ZERO
var is_initialized := false
var was_on_floor_last_frame: bool = true
var time_since_jump: float = 0.0
var time_since_input: float = 0.0
var last_air_vertical_speed: float = 0.0 # Guarda la velocidad vertical del último frame en el aire
var jumped_buffer_time: float = 0.0
var acrobatic_trigger_active: bool = false # Latch para garantizar que la SM vea el trigger
var is_rotation_locked: bool = false # Impide que el personaje rote durante maniobras (backflip)
var hit_head_active: bool = false

# --- LIFECYCLE ---
func _ready() -> void:
	# Asignar controller de forma segura (dos niveles arriba: Pivot -> Visual -> Pilot)
	controller = get_parent().get_parent() if get_parent() and get_parent().get_parent() else null
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
	# activar el AnimationTree de forma segura
	animation_tree.active = true
	
	is_initialized = true

	# Warmup animations to cache blends
	_warmup_animations()

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
				# Use start() to force the state even if no transition path exists
				# This handles "isolated" states like Confused that might not have incoming connections
				playback.start(anim_name)
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

	# Lógica de tiempo para flotación
	if is_on_floor:
		time_since_jump = 0.0
		time_since_input = 0.0
	else:
		time_since_jump += dt
		time_since_input += dt

	# Actualizar buffer de salto (permite que is_jumping sea true por unos ms)
	if jumped_buffer_time > 0.0:
		jumped_buffer_time = max(0.0, jumped_buffer_time - dt)

	if controller.get_wish_direction().length() > 0.1:
		time_since_input = 0.0

	# 1. SUAVIZADO DE VELOCIDAD PARA ANIMACIÓN
	# Usamos la velocidad del controlador para el movimiento, pero una versión
	# suavizada para que las transiciones de animación (e.g., idle -> run) no sean abruptas.
	if dt > 0:
		visual_velocity = visual_velocity.linear_interpolate(p_current_velocity, velocity_lerp_speed * dt)
	else:
		visual_velocity = p_current_velocity

	# 2. ROTACIÓN VISUAL SUAVE (YAW)
	# Solo rotamos si no estamos bloqueados (durante backflip)
	if not is_rotation_locked:
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

	# 3. INCLINACIÓN (TILT) BASADA EN PENDIENTE/ESCALERAS
	# Calculamos el ángulo de inclinación basado en la relación entre velocidad vertical y horizontal
	var horz_speed = Vector2(visual_velocity.x, visual_velocity.z).length()
	var target_pitch = 0.0
	
	# Solo calculamos tilt si estamos "efectivamente en el suelo" y moviéndonos
	if is_on_floor and horz_speed > 0.1:
		# atan2(y, x) nos da el ángulo de la pendiente. 
		# Limitamos el ángulo para evitar poses extremas.
		target_pitch = - clamp(atan2(visual_velocity.y, horz_speed), deg2rad(-max_tilt_angle), deg2rad(max_tilt_angle))
	
	if dt > 0:
		rotation.x = lerp_angle(rotation.x, target_pitch, tilt_lerp_speed * dt)
	else:
		rotation.x = target_pitch


	# Desbloquear rotación al aterrizar
	if is_on_floor and is_rotation_locked and not acrobatic_trigger_active:
		is_rotation_locked = false

	# 3. APLICACIÓN DE ESTADO AL ANIMATIONTREE
	update_animation_parameters(p_current_velocity, is_on_floor, controller.get_wish_direction().length())

	was_on_floor_last_frame = is_on_floor


func update_animation_parameters(velocity: Vector3, is_on_floor: bool, move_vec_length: float) -> void:
	if not animation_tree:
		return

	# Actualizar condiciones básicas
	animation_tree.set(PARAM_CONDITIONS_ON_FLOOR, is_on_floor)
	animation_tree.set(PARAM_CONDITIONS_NOT_ON_FLOOR, not is_on_floor)

	# Estados de salto/caída usando la velocidad registrada en el último frame en aire.
	# IMPORTANTE: Forzamos false si estamos en el suelo (evita flickering en escaleras).
	var is_falling: bool = last_air_vertical_speed < -1.0 and not is_on_floor
	var is_floating: bool = last_air_vertical_speed >= -1.0 and last_air_vertical_speed < 0.0 and not is_on_floor

	animation_tree.set(PARAM_CONDITIONS_IS_FALLING, is_falling)
	animation_tree.set(PARAM_CONDITIONS_IS_FLOATING, is_floating)

	# is_jumping: true si acabamos de disparar el salto (buffer) o si estamos subiendo en aire
	# IMPORTANTE: También forzamos false si estamos en el suelo para evitar saltos visuales en escaleras.
	var is_jumping_param: bool = ((jumped_buffer_time > 0.0) or (not is_on_floor and velocity.y > 1.0)) and not is_on_floor
	
	# PRIORIDAD ABSOLUTA AL BACKFLIP:
	# Si el latch acrobático está armado, forzamos is_jumping a false.
	# Esto obliga a la StateMachine a ignorar el salto normal y tomar la transición 'is_acrobatic'.
	if acrobatic_trigger_active:
		is_jumping_param = false
		
	animation_tree.set(PARAM_CONDITIONS_IS_JUMPING, is_jumping_param)
	
	# Resetear trigger acrobático usando el latch
	if acrobatic_trigger_active:
		print("PilotAnimator: Sending is_acrobatic = TRUE to AnimationTree")
		animation_tree.set(PARAM_CONDITIONS_IS_ACROBATIC, true)
		acrobatic_trigger_active = false # Consumimos el trigger
	else:
		animation_tree.set(PARAM_CONDITIONS_IS_ACROBATIC, false)
	
	# Hit Head condition (one-shot, cleared after this frame)
	animation_tree.set(PARAM_CONDITIONS_HIT_HEAD, hit_head_active)
	hit_head_active = false

	# Emitir land_soft / land_hard SOLO en el frame de aterrizaje (edge detect)
	var landed_now: bool = is_on_floor and not was_on_floor_last_frame
	var land_soft: bool = landed_now and last_air_vertical_speed >= -1.0
	var land_hard: bool = landed_now and last_air_vertical_speed < -1.0

	animation_tree.set(PARAM_CONDITIONS_LAND_SOFT, land_soft)
	animation_tree.set(PARAM_CONDITIONS_LAND_HARD, land_hard)

	# Parámetro para la mezcla de locomoción (Idle/Walk/Run).
	# Usa la magnitud de la velocidad horizontal suavizada.
	var blend_pos = Vector2(visual_velocity.x, visual_velocity.z).length()
	animation_tree.set(PARAM_GROUNDED_BLEND_POSITION, blend_pos)

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


func _on_controller_jumped() -> void:
	"""Se ejecuta cuando el controlador emite la señal 'jumped'."""
	# Activamos el salto normal.
	# Aseguramos que la transición interna del estado Jump (si aún existe) esté en start
	# O simplemente confiamos en el estado Jump por defecto.
	# animation_tree.set(PARAM_JUMP_TRANSITION_TYPE, 0) # Opcional si limpiaste el nodo Jump
	
	# Usar ONE_SHOT_REQUEST_FIRE es la forma correcta y determinista de activar animaciones OneShot.
	# NO NO NO NO ES ACTIVE 1
	animation_tree.set(PARAM_GROUNDED_JUMP_ACTIVE, 1) ## # NO TOCAR (Legacy logic, mantener si es necesario para compatibilidad)

	# Activar buffer de salto para mantener `is_jumping` verdadero algunos ms
	jumped_buffer_time = jump_buffer_duration

func _on_controller_hit_ceiling() -> void:
	"""Se ejecuta cuando el controlador emite la señal 'hit_ceiling'."""
	hit_head_active = true

func _on_controller_acrobatic_jumped() -> void:
	"""Trigger Backflip State via is_acrobatic condition."""
	if animation_tree:
		print("PilotAnimator: Controller signal received. Arming ACROBATIC latch.")
		# Activamos el latch para que update_animation_parameters lo procese en el momento correcto
		acrobatic_trigger_active = true
		
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
			print("PilotAnimator: Backflip LOCKED orientation")
		
		# IMPORTANTE: NO configuramos jumped_buffer_time aquí para evitar que 'is_jumping' se active
		# y compita con 'is_acrobatic'. Queremos ir SOLO al estado Acrobatic.
