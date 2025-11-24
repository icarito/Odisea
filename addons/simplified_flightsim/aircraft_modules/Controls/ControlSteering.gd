extends AircraftModule
class_name AircraftModule_ControlSteering

export(bool) var ControlActive = true

# There should be only one steering and one steering control in the aircraft
var steering_module = null

func _ready():
	ReceiveInput = true
	ProcessPhysics = true # Necesario para el sondeo del teclado


func setup(aircraft_node):
	aircraft = aircraft_node
	steering_module = aircraft.find_modules_by_type("steering").pop_front()
	print("steering found: %s" % str(steering_module))

func process_physic_frame(_delta):
	if (not steering_module) or (not ControlActive):
		return
	
	# Unificamos el procesamiento de todos los ejes en una sola función
	_process_all_steering_inputs()

func receive_input(event):
	# Esta función ahora solo se usa para depurar y ver los eventos que llegan.
	# La lógica de control real está en _physics_process.
	if event is InputEventJoypadButton:
		print("ControlSteering: Joypad button event. Index: ", event.button_index, " Pressed: ", event.pressed)

func _process_all_steering_inputs():
	var joy_id = 0

	# --- Roll (Alabeo): Stick Izquierdo X + Teclas A/D ---
	var roll_axis = 0.0
	if Input.is_joy_known(joy_id):
		roll_axis += -Input.get_joy_axis(joy_id, JOY_AXIS_0) # Aileron (stick izquierdo X)
	if Input.is_key_pressed(KEY_A):
		roll_axis -= 1.0
	if Input.is_key_pressed(KEY_D):
		roll_axis += 1.0
	steering_module.set_z(clamp(roll_axis, -1.0, 1.0))

	# --- Pitch (Cabeceo): Stick Izquierdo Y + Teclas W/S ---
	var pitch_axis = 0.0
	if Input.is_joy_known(joy_id):
		pitch_axis += -Input.get_joy_axis(joy_id, JOY_AXIS_1) # Elevador (stick izquierdo Y)
	if Input.is_key_pressed(KEY_W):
		pitch_axis -= 1.0
	if Input.is_key_pressed(KEY_S):
		pitch_axis += 1.0
	steering_module.set_x(clamp(pitch_axis, -1.0, 1.0))

	# --- Yaw (Guiñada): L1/R1 + Teclas Q/E ---
	var yaw_axis = 0.0
	# Teclado
	if Input.is_key_pressed(KEY_Q):
		yaw_axis += 1.0
	if Input.is_key_pressed(KEY_E):
		yaw_axis -= 1.0
	
	# Joypad (sobrescribe al teclado si se pulsa)
	if Input.is_joy_button_pressed(joy_id, 4): # L1
		print("ControlSteering: Joypad Yaw Override -> L1 (Yaw Left)")
		yaw_axis = 1.0
	elif Input.is_joy_button_pressed(joy_id, 5): # R1
		print("ControlSteering: Joypad Yaw Override -> R1 (Yaw Right)")
		yaw_axis = -1.0
		
	steering_module.set_y(clamp(yaw_axis, -1.0, 1.0))
