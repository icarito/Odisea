extends Spatial

class_name PilotAnimatorV2

# --- EXPORTS ---
# Velocidad de suavizado para la velocidad usada en el AnimationTree.
export var velocity_lerp_speed: float = 10.0
# Velocidad de suavizado para la rotación visual del personaje.
export var rotation_lerp_speed: float = 10.0

# --- NODES ---
onready var controller = get_parent()
onready var animation_tree: AnimationTree = $AnimationTree

# --- STATE ---
# Almacena la velocidad suavizada para el blend tree de animación.
var visual_velocity: Vector3 = Vector3.ZERO

# --- LIFECYCLE ---
func _ready() -> void:
	# Validaciones para asegurar la correcta configuración de la escena.
	if not controller or not controller.has_method("get_wish_direction"):
		push_error("PilotAnimatorV2 debe ser hijo de un PlayerControllerV2 válido.")
		set_process(false)
		return
		
	if not animation_tree:
		push_error("No se encontró un nodo AnimationTree dentro de 'Pivot'.")
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

	
func _physics_process(delta: float) -> void:
	if not is_instance_valid(controller):
		return

	# 1. LECTURA DE ESTADO DEL CONTROLADOR
	var is_on_floor: bool = controller.is_on_floor()
	var current_velocity: Vector3 = controller.velocity
	var wish_direction: Vector3 = controller.get_wish_direction()

	# 2. SUAVIZADO DE VELOCIDAD PARA ANIMACIÓN
	# Usamos la velocidad del controlador para el movimiento, pero una versión
	# suavizada para que las transiciones de animación (e.g., idle -> run) no sean abruptas.
	visual_velocity = visual_velocity.linear_interpolate(current_velocity, velocity_lerp_speed * delta)

	# 3. ROTACIÓN VISUAL SUAVE (YAW)
	# Rota el pivote visual hacia la dirección de movimiento deseada (wish_direction).
	# Esto solo ocurre si hay una intención de movimiento para evitar que el personaje
	# vuelva a la rotación por defecto al detenerse.
	var horizontal_velocity = wish_direction * Vector3(1, 0, 1)
	if horizontal_velocity.length_squared() > 0.01:
		var target_angle = atan2(horizontal_velocity.x, horizontal_velocity.z)
		self.rotation.y = lerp_angle(self.rotation.y, target_angle, rotation_lerp_speed * delta)
		# DEBUG: Imprime la dirección deseada y el ángulo objetivo
		# print("Wish Direction: ", wish_direction, " Target Angle: ", rad2deg(target_angle))

	# 4. APLICACIÓN DE ESTADO AL ANIMATIONTREE
	update_animation_parameters(is_on_floor, visual_velocity)


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
	animation_tree.set("parameters/Grounded/Jump/active", true)
