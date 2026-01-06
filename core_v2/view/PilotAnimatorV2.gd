extends Spatial

class_name PilotAnimatorV2

# --- PARAMETER PATHS (CACHED STRINGS) ---
const PARAM_PLAYBACK = "parameters/playback"
const PARAM_CONDITIONS_ON_FLOOR = "parameters/conditions/on_floor"
const PARAM_CONDITIONS_IS_FALLING = "parameters/conditions/is_falling"
const PARAM_CONDITIONS_IS_JUMPING = "parameters/conditions/is_jumping"
const PARAM_CONDITIONS_IS_FLOATING = "parameters/conditions/is_floating"
const PARAM_CONDITIONS_IS_FALLING_FAST = "parameters/conditions/is_falling_fast"
const PARAM_GROUNDED_BLEND_POSITION = "parameters/Grounded/blend_position"
const PARAM_GROUNDED_JUMP_ACTIVE = "parameters/Grounded/Jump/active"
const PARAM_PLAYBACK_ACTIVE = "parameters/playback/active"

# --- EXPORTS ---
# Velocidad de suavizado para la velocidad usada en el AnimationTree.
export var velocity_lerp_speed: float = 5.0
# Velocidad de suavizado para la rotación visual del personaje.
export var rotation_lerp_speed: float = 10.0

# --- NODES ---
onready var controller = get_parent().get_parent() # Sube dos niveles: Pivot -> Visual -> Pilot
onready var animation_tree: AnimationTree = $AnimationTree # AnimationTree es ahora hijo del Pivot

# --- STATE ---
# Almacena la velocidad suavizada para el blend tree de animación.
var visual_velocity: Vector3 = Vector3.ZERO
var is_initialized := false
var was_on_floor_last_frame: bool = true
var time_since_jump: float = 0.0
var time_since_input: float = 0.0

# --- LIFECYCLE ---
func _ready() -> void:
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

	var playback = animation_tree.get(PARAM_PLAYBACK)
	if playback:
		playback.start("Grounded")
	
	animation_tree.set(PARAM_PLAYBACK_ACTIVE, true)
	
	is_initialized = true

	# Warmup animations to cache blends
	_warmup_animations()

func _warmup_animations() -> void:
	"""Fuerza el cacheo de las mezclas de Grounded e InAir avanzando el AnimationTree."""
	for _i in range(10):
		animation_tree.advance(0.001)

	
func step_animator(dt: float, p_current_velocity: Vector3) -> void:
	"""
	Actualiza todos los aspectos visuales del personaje.
	Debe ser llamado manualmente por el controlador después de cada 'step' de física.
	"""
	var is_on_floor: bool = controller.is_on_floor()
	var wish_direction: Vector3 = controller.get_wish_direction()

	# Lógica de tiempo para flotación
	if is_on_floor:
		time_since_jump = 0.0
		time_since_input = 0.0
	else:
		time_since_jump += dt
		time_since_input += dt

	if controller.get_wish_direction().length() > 0.1:
		time_since_input = 0.0

	# Cálculo de is_floating
	var is_floating = (!is_on_floor) and (time_since_jump > 0.4 or (abs(p_current_velocity.y) < 1.5 and time_since_input > 0.2))

	# 1. SUAVIZADO DE VELOCIDAD PARA ANIMACIÓN
	# Usamos la velocidad del controlador para el movimiento, pero una versión
	# suavizada para que las transiciones de animación (e.g., idle -> run) no sean abruptas.
	if dt > 0:
		visual_velocity = visual_velocity.linear_interpolate(p_current_velocity, velocity_lerp_speed * dt)
	else:
		visual_velocity = p_current_velocity

	# 2. ROTACIÓN VISUAL SUAVE (YAW)
	# Rota el pivote visual hacia la dirección de movimiento deseada (wish_direction).
	# Esto solo ocurre si hay una intención de movimiento para evitar que el personaje
	# vuelva a la rotación por defecto al detenerse.
	var horizontal_wish_direction = wish_direction * Vector3(1, 0, 1)
	if horizontal_wish_direction.length_squared() > 0.01:
		# wish_direction ahora es siempre correcta, por lo que no necesitamos lógica condicional.
		var target_angle = atan2(horizontal_wish_direction.x, horizontal_wish_direction.z)
		if dt > 0: # Suavizado en modo LIVE.
			rotation.y = lerp_angle(rotation.y, target_angle, rotation_lerp_speed * dt)
		else: # Aplicación instantánea en modo REPLAY.
			rotation.y = target_angle

	# 3. APLICACIÓN DE ESTADO AL ANIMATIONTREE
	update_animation_parameters(is_on_floor, p_current_velocity, is_floating)

	was_on_floor_last_frame = is_on_floor


func update_animation_parameters(is_on_floor: bool, velocity: Vector3, is_floating: bool) -> void:
	"""Actualiza los parámetros del AnimationTree basados en el estado del controlador."""

	# Solo actualizar 3 condiciones base: on_floor, is_jumping (trigger de inicio), is_floating (parámetro interno de In_Air).
	animation_tree.set(PARAM_CONDITIONS_ON_FLOOR, is_on_floor)
	
	# is_falling solo se activa cuando está cayendo significativamente
	var is_falling = velocity.y < -1.0
	animation_tree.set(PARAM_CONDITIONS_IS_FALLING, is_falling)
	
	if is_on_floor:
		# Forzar is_jumping a false inmediatamente para limpiar el buffer del AnimationTree y evitar que el personaje quiera saltar de nuevo al aterrizar.
		animation_tree.set(PARAM_CONDITIONS_IS_JUMPING, false)
	else:
		# is_jumping solo true si velocity.y > 1.0 y no está en el suelo (trigger de inicio).
		animation_tree.set(PARAM_CONDITIONS_IS_JUMPING, velocity.y > 1.0)
	
	animation_tree.set(PARAM_CONDITIONS_IS_FLOATING, is_floating)

	# Parámetro para la mezcla de locomoción (Idle/Walk/Run).
	# Usa la magnitud de la velocidad horizontal suavizada.
	var blend_pos = Vector2(visual_velocity.x, visual_velocity.z).length()
	animation_tree.set(PARAM_GROUNDED_BLEND_POSITION, blend_pos)


func _on_controller_jumped() -> void:
	"""Se ejecuta cuando el controlador emite la señal 'jumped'."""
	# Usar ONE_SHOT_REQUEST_FIRE es la forma correcta y determinista de activar animaciones OneShot.
	# NO NO NO NO ES ACTIVE 1
	animation_tree.set(PARAM_GROUNDED_JUMP_ACTIVE, 1) ### NO TOCAR
