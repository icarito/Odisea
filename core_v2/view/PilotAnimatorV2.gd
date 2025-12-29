extends Spatial

class_name PilotAnimatorV2

# --- EXPORTS ---
# Velocidad de suavizado para la velocidad usada en el AnimationTree.
export var velocity_lerp_speed: float = 10.0
# Velocidad de suavizado para la rotación visual del personaje.
export var rotation_lerp_speed: float = 10.0

# --- NODES ---
onready var controller = get_parent().get_parent() # Sube dos niveles: Pivot -> Visual -> Pilot
onready var animation_tree: AnimationTree = $AnimationTree # AnimationTree es ahora hijo del Pivot

# --- STATE ---
# Almacena la velocidad suavizada para el blend tree de animación.
var visual_velocity: Vector3 = Vector3.ZERO
var is_initialized := false

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

	# Asegurarse de que el AnimationTree esté activo y tenga un playback válido.
	if not animation_tree.active:
		animation_tree.active = true

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

	# 2. SUAVIZADO DE VELOCIDAD PARA ANIMACIÓN
	# Usamos la velocidad del controlador para el movimiento, pero una versión
	# suavizada para que las transiciones de animación (e.g., idle -> run) no sean abruptas.
	if dt > 0:
		visual_velocity = visual_velocity.linear_interpolate(p_current_velocity, velocity_lerp_speed * dt)
	else:
		visual_velocity = p_current_velocity

	# 3. ROTACIÓN VISUAL (DESACTIVADA POR AHORA)
	# En el siguiente paso, desacoplaremos la rotación del cuerpo y activaremos esta sección
	# para que el modelo mire hacia donde se mueve, independientemente de la cámara.
	#
	#var horizontal_velocity = wish_direction * Vector3(1, 0, 1)
	#if horizontal_velocity.length_squared() > 0.01:
	#	var target_angle = atan2(horizontal_velocity.x, horizontal_velocity.z)
	#	if dt > 0: # Suavizado en modo LIVE
	#		self.rotation.y = lerp_angle(self.rotation.y, target_angle, rotation_lerp_speed * dt)
	#	else: # Aplicación instantánea en modo REPLAY
	#		self.rotation.y = target_angle

	# 4. APLICACIÓN DE ESTADO AL ANIMATIONTREE
	update_animation_parameters(is_on_floor, visual_velocity)
	
	# 5. AVANCE MANUAL DEL ANIMATIONTREE
	# Esto es crítico para el determinismo en tests y replays.
	animation_tree.advance(dt)


func update_animation_parameters(is_on_floor: bool, p_visual_velocity: Vector3) -> void:
	"""Actualiza los parámetros del AnimationTree basados en el estado del controlador."""

	# Parámetros de condición para la máquina de estados.
	animation_tree.set("parameters/conditions/is_on_floor", is_on_floor)
	animation_tree.set("parameters/conditions/!is_on_floor", not is_on_floor)

	# Parámetro para la mezcla de locomoción (Idle/Walk/Run).
	# Usa la magnitud de la velocidad horizontal suavizada.
	var blend_pos = Vector2(p_visual_velocity.x, p_visual_velocity.z).length()
	animation_tree.set("parameters/Grounded/Locomotion/blend_position", blend_pos)
	
	# DEBUG: Imprime la velocidad que se pasa al blend tree
	# print("Animation Speed: ", blend_pos)
	
	# Parámetros para animaciones en el aire (salto/caída).
	# Distingue entre ascenso y descenso para transiciones más precisas.
	if not is_on_floor:
		animation_tree.set("parameters/conditions/is_falling", p_visual_velocity.y < 0)
		animation_tree.set("parameters/conditions/is_jumping", p_visual_velocity.y > 0)

	# Desactiva el OneShot de salto cuando el jugador vuelve al suelo para que pueda
	# ejecutarse de nuevo en el próximo salto.
	if animation_tree.get("parameters/Grounded/Jump/active") and controller.is_on_floor():
		animation_tree.set("parameters/Grounded/Jump/active", false)


func _on_controller_jumped() -> void:
	"""Se ejecuta cuando el controlador emite la señal 'jumped'."""
	# Usar ONE_SHOT_REQUEST_FIRE es la forma correcta y determinista de activar animaciones OneShot.
	# NO NO NO NO ES ACTIVE 1
	animation_tree.set("parameters/Grounded/Jump/active", 1) ### NO TOCAR
