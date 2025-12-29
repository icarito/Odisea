extends Spatial

class_name PilotAnimatorV2

# --- EXPORTS ---
# Velocidad de suavizado para la rotación visual del personaje.
export var rotation_lerp_speed: float = 15.0
# Velocidad de suavizado para la velocidad usada en el AnimationTree.
export var velocity_lerp_speed: float = 10.0

# --- NODES ---
onready var controller: KinematicBody = get_parent()
onready var animation_tree: AnimationTree = $AnimationTree

# --- STATE ---
# Almacena la velocidad suavizada para el blend tree de animación.
var visual_velocity: Vector3 = Vector3.ZERO

# --- LIFECYCLE ---

func _ready() -> void:
	if not controller or not (controller is KinematicBody and controller.has_method("step")):
		push_error("PilotAnimatorV2 debe ser hijo de un PlayerControllerV2 válido.")
		set_process(false)
		return

	if not animation_tree:
		push_error("No se encontró un nodo AnimationTree como hijo.")
		set_process(false)
		return

	# Inicializa la rotación visual para que coincida con la del controlador al inicio.
	rotation = controller.rotation
	
	# Conectar la señal de salto para manejar la animación de forma reactiva.
	controller.connect("jumped", self, "_on_controller_jumped")

func _process(delta: float) -> void:
	if not is_instance_valid(controller):
		return

	# 1. SUAVIZADO DE ROTACIÓN VISUAL
	# Interpola suavemente la rotación de este nodo (el modelo visual) hacia la
	# rotación instantánea y lógica del controlador padre.
	# Esto es clave para no afectar el determinismo del replay.
	self.global_transform.basis = self.global_transform.basis.slerp(controller.global_transform.basis, rotation_lerp_speed * delta)

	# 2. LECTURA DE ESTADO DEL CONTROLADOR
	var is_on_floor: bool = controller.is_on_floor()
	# La velocidad del controlador puede ser instantánea/jittery, la suavizamos para la animación.
	var current_velocity: Vector3 = controller.velocity 
	
	# 3. SUAVIZADO DE VELOCIDAD PARA ANIMACIÓN
	# Usamos la velocidad del controlador para el movimiento, pero una versión
	# suavizada para que las transiciones de animación (e.g., idle -> run) no sean abruptas.
	visual_velocity = visual_velocity.linear_interpolate(current_velocity, velocity_lerp_speed * delta)

	# 4. APLICACIÓN DE ESTADO AL ANIMATIONTREE
	# Se asume que el AnimationTree tiene estos parámetros para controlar los blends.
	
	# El parámetro "speed" controla la mezcla entre idle, walk y run.
	# Usamos la longitud del vector de velocidad horizontal suavizado para el blendspace.
	animation_tree.set("parameters/Grounded/Locomotion/blend_position", Vector2(visual_velocity.x, visual_velocity.z).length())
	# Parámetro para animaciones en el aire (salto, caída).
	animation_tree.set("parameters/is_on_floor", is_on_floor)

	# Ejemplo de otros posibles estados a animar:
	# if controller.is_rolling():
	#     animation_tree.set("parameters/roll/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _on_controller_jumped() -> void:
	"""Se ejecuta cuando el controlador emite la señal 'jumped'."""
	animation_tree.set("parameters/Grounded/Jump/request", 1)
