extends Spatial
class_name VehicleInputController

# --- Configuración del Control ---
export(bool) var control_active = true
# NOTA: La 'deadzone' del joypad ahora se configura en el Mapa de Entradas del proyecto.

# --- Configuración del Vehículo ---
export(float) var engine_power = 2500.0 # Aumentado para más potencia
export(float) var brake_power = 1.0 # Corresponde a la fricción Z de DriveElement
export(float) var rolling_resistance = 0.02 # Resistencia mínima para evitar deslizamiento infinito
export(float) var steering_angle_deg = 35.0

# Módulos del vehículo (se asignan automáticamente)
var drive_wheels = []
var steering_wheels = []

onready var parent_body: RigidBody = get_parent()

# Variable para rastrear el último tipo de dispositivo de entrada utilizado
var _last_input_is_joypad = false

func _ready():
	# Busca las ruedas con las etiquetas correspondientes al iniciar
	# Asegúrate de haber etiquetado tus nodos DriveElement en el editor.
	# Por ejemplo, las ruedas traseras con "drive" y las delanteras con "steering".
	for child in parent_body.get_children():
		if child is DriveElement:
			if child.is_in_group("drive"):
				drive_wheels.append(child)
			if child.is_in_group("steering"):
				steering_wheels.append(child)
	
	print("Controlador de vehículo listo.")
	print("Ruedas de tracción encontradas: ", drive_wheels.size())
	print("Ruedas de dirección encontradas: ", steering_wheels.size())

func _input(event):
	# Detecta si el último evento de entrada fue del teclado o del mando
	if event is InputEventKey:
		_last_input_is_joypad = false
	elif event is InputEventJoypadMotion or event is InputEventJoypadButton:
		_last_input_is_joypad = true

func _physics_process(_delta):
	if not control_active:
		return

	var throttle_input = 0.0
	var steering_input = 0.0

	# Priorizamos la entrada del mando (joystick/palanca)
	var joy_throttle = -Input.get_joy_axis(0, JOY_AXIS_1) # Eje Y de la palanca izquierda
	var joy_steering = Input.get_joy_axis(0, JOY_AXIS_0) # Eje X de la palanca izquierda

	# Si hay entrada del mando, la usamos. Si no, usamos la del teclado.
	# Esto evita que el teclado y el mando se interfieran.
	throttle_input = joy_throttle if abs(joy_throttle) > 0.1 else Input.get_axis("backward", "forward")
	steering_input = joy_steering if abs(joy_steering) > 0.1 else Input.get_axis("left", "right")

	var brake_input = Input.get_action_strength("jump") # 'jump' (Botón A/Espacio) como freno.

	# Aplicar fuerzas de aceleración y freno
	for wheel in drive_wheels:
		if throttle_input != 0:
			var forward_force = wheel.global_transform.basis.z * -engine_power * throttle_input
			wheel.apply_force(forward_force)
		
		# Aplicar freno si se pulsa la acción de frenado, de lo contrario, aplicar resistencia al rodamiento.
		var current_brake = brake_power if brake_input > 0 else rolling_resistance
		wheel.apply_brake(current_brake)
	
	# Aplicar la rotación a las ruedas de dirección
	var target_rotation_y = deg2rad(steering_angle_deg) * steering_input
	
	for wheel in steering_wheels:
		# Rotamos el nodo de la rueda para simular la dirección
		wheel.rotation.y = lerp(wheel.rotation.y, target_rotation_y, 0.1)
