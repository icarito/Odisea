extends Spatial

class_name PilotAnimatorV2

enum JumpPhase { GROUNDED, START, JUMP_LOOP, FLOAT_LOOP, LAND }

# --- EXPORTS ---
# Velocidad de suavizado para la velocidad usada en el AnimationTree.
export var velocity_lerp_speed: float = 10.0
# Velocidad de suavizado para la rotación visual del personaje.
export var rotation_lerp_speed: float = 10.0
# Umbral de velocidad de caída para distinguir entre JUMP_LOOP y FLOAT_LOOP.
export var fall_speed_threshold: float = 2.0
# Duración de la fase START del salto.
export var jump_start_duration: float = 0.3

# --- NODES ---
onready var controller = get_parent().get_parent() # Sube dos niveles: Pivot -> Visual -> Pilot
onready var animation_tree: AnimationTree = $AnimationTree # AnimationTree es ahora hijo del Pivot

# --- STATE ---
# Almacena la velocidad suavizada para el blend tree de animación.
var visual_velocity: Vector3 = Vector3.ZERO
var is_initialized := false
var was_on_floor_last_frame: bool = true
var current_jump_phase: int = JumpPhase.GROUNDED
var time_on_ground_after_land: float = 0.0
var jump_timer: float = 0.0

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

	var playback = animation_tree.get("parameters/playback")
	if playback:
		playback.start("Grounded")
	
	is_initialized = true

	
func step_animator(dt: float, p_current_velocity: Vector3) -> void:
	"""
	Actualiza todos los aspectos visuales del personaje.
	Debe ser llamado manualmente por el controlador después de cada 'step' de física.
	"""
	var is_on_floor: bool = controller.is_on_floor()
	var wish_direction: Vector3 = controller.get_wish_direction()

	# DETECCIÓN DE FASES DE SALTO
	if is_on_floor:
		if not was_on_floor_last_frame:
			current_jump_phase = JumpPhase.LAND
			time_on_ground_after_land = 0.0
		elif current_jump_phase == JumpPhase.LAND:
			time_on_ground_after_land += dt
			if time_on_ground_after_land > 0.2:
				current_jump_phase = JumpPhase.GROUNDED
				time_on_ground_after_land = 0.0
	else:  # Aire
		if was_on_floor_last_frame:  # Despegue
			if p_current_velocity.y > 1.0:
				current_jump_phase = JumpPhase.START
				jump_timer = jump_start_duration
			else:
				current_jump_phase = JumpPhase.FLOAT_LOOP
		else:  # Durante el aire
			if current_jump_phase == JumpPhase.START:
				jump_timer -= dt
				if jump_timer <= 0 or p_current_velocity.y < -fall_speed_threshold:
					if p_current_velocity.y < -fall_speed_threshold:
						current_jump_phase = JumpPhase.JUMP_LOOP
					else:
						current_jump_phase = JumpPhase.FLOAT_LOOP
			else:
				if p_current_velocity.y < -fall_speed_threshold:
					current_jump_phase = JumpPhase.JUMP_LOOP
				else:
					current_jump_phase = JumpPhase.FLOAT_LOOP

	# Actualizar el AnimationTree
	animation_tree.set("parameters/JumpState/current", current_jump_phase)

	# 2. SUAVIZADO DE VELOCIDAD PARA ANIMACIÓN
	# Usamos la velocidad del controlador para el movimiento, pero una versión
	# suavizada para que las transiciones de animación (e.g., idle -> run) no sean abruptas.
	if dt > 0:
		visual_velocity = visual_velocity.linear_interpolate(p_current_velocity, velocity_lerp_speed * dt)
	else:
		visual_velocity = p_current_velocity

	# 3. ROTACIÓN VISUAL SUAVE (YAW)
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

	# 4. APLICACIÓN DE ESTADO AL ANIMATIONTREE
	update_animation_parameters(is_on_floor, visual_velocity)
	
	# 5. AVANCE MANUAL DEL ANIMATIONTREE
	# Esto es crítico para el determinismo en tests y replays.
	animation_tree.advance(dt)

	was_on_floor_last_frame = is_on_floor


func update_animation_parameters(is_on_floor: bool, p_visual_velocity: Vector3) -> void:
	"""Actualiza los parámetros del AnimationTree basados en el estado del controlador."""

	# Parámetros de condición para la máquina de estados.
	animation_tree.set("parameters/conditions/is_on_floor", is_on_floor)
	animation_tree.set("parameters/conditions/!is_on_floor", not is_on_floor)

	# Parámetro para la mezcla de locomoción (Idle/Walk/Run).
	# Usa la magnitud de la velocidad horizontal suavizada.
	var blend_pos = Vector2(p_visual_velocity.x, p_visual_velocity.z).length()
	animation_tree.set("parameters/Grounded/blend_position", blend_pos)
	
	# DEBUG: Imprime la velocidad que se pasa al blend tree
	# print("Animation Speed: ", blend_pos)


func _on_controller_jumped() -> void:
	"""Se ejecuta cuando el controlador emite la señal 'jumped'."""
	# Usar ONE_SHOT_REQUEST_FIRE es la forma correcta y determinista de activar animaciones OneShot.
	# NO NO NO NO ES ACTIVE 1
	animation_tree.set("parameters/Grounded/Jump/active", 1) ### NO TOCAR
