extends Node2D
export var debug = false

onready var debug_label: Label = $DebugLabel
onready var cursor_sprite: Sprite = $Cursor

#--- JOYSTICK CONTROL ---
export (float, 0.0, 1.0) var joystick_deadzone = 0.02
export (float) var joystick_sensitivity = 650.0

enum JoystickCurveType { LINEAR, EXPONENTIAL, INVERSE_S }
export (JoystickCurveType) var joystick_curve_type = JoystickCurveType.EXPONENTIAL

# Cargamos las curvas desde los archivos que creaste en la carpeta res://Curves/
# This MUST be a var, not const, to avoid errors in Godot 3.5+
var CURVE_RESOURCES = [
	load("res://Curves/Linear.tres"),
	load("res://Curves/Exponential.tres"),
	load("res://Curves/Inverse_S.tres")
]

var _joy_vector = Vector2.ZERO
#-------------------------

# Called when the node enters the scene tree for the first time.
func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var viewport = get_viewport()
	cursor_sprite.position = viewport.size / 2
	
	get_viewport().connect("size_changed", self, "_on_viewport_size_changed")
	clamp_cursor_to_screen()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	_process_joystick_input(delta)
	# Si el modo debug está activo, pedimos que se redibuje la pantalla
	# para que se muestre nuestro punto de debug.
	if debug:
		update()


# Se llama cada vez que el nodo necesita redibujarse (cuando llamamos a update())
func _draw():
	# Si el modo debug está activo, dibujamos el punto rojo.
	if debug:
		# Dibuja un pequeño círculo rojo en la posición exacta del cursor virtual.
		draw_circle(cursor_sprite.position, 3, Color.red)


func _input(event):
	# Si se mueve el ratón real, el cursor virtual lo sigue.
	# Hacemos esto en _input() para capturar el evento ANTES de que la UI lo consuma.
	if event is InputEventMouseMotion:
		cursor_sprite.position = event.position
		clamp_cursor_to_screen()


func _unhandled_input(event):
	# --- DEBUG LABEL ---
	var text = debug_label.text
	var lista = Array(text.split("\n"))
	while lista.size() > 11:
		lista.pop_front()
	text = PoolStringArray(lista).join("\n")
	debug_label.text = text + "\n" + event.as_text()
	# --------------------

	# Gestionar los clics de joystick (izquierdo y derecho)
	if event is InputEventJoypadButton:
		var mouse_button_index = 0
		if event.button_index == JOY_BUTTON_0: # Botón A (normalmente)
			mouse_button_index = BUTTON_LEFT
		elif event.button_index == JOY_BUTTON_1: # Botón B (normalmente)
			mouse_button_index = BUTTON_RIGHT
		
		# Si es un botón que hemos mapeado (izq o der), creamos el evento de ratón.
		if mouse_button_index != 0:
			var click_event = InputEventMouseButton.new()
			click_event.button_index = mouse_button_index
			click_event.pressed = event.is_pressed() # Refleja el estado real (pulsado o soltado)
			click_event.position = cursor_sprite.position
			get_tree().input_event(click_event)


func _process_joystick_input(delta):
	# Usamos Input Actions para que sea configurable.
	# Ejes invertidos como se solicitó.
	_joy_vector.x = Input.get_action_strength("cursor_left") - Input.get_action_strength("cursor_right")
	_joy_vector.y = Input.get_action_strength("cursor_up") - Input.get_action_strength("cursor_down")
	
	if _joy_vector.length() < joystick_deadzone:
		return

	var processed_vector = _joy_vector.normalized()
	# Obtenemos la curva seleccionada desde nuestros recursos cargados
	var curve: Curve = CURVE_RESOURCES[joystick_curve_type]
	# Aplicamos la curva a la magnitud del input
	var curve_val = curve.interpolate(_joy_vector.length())
	
	processed_vector *= curve_val * joystick_sensitivity * delta
	
	cursor_sprite.position += processed_vector
	clamp_cursor_to_screen()
	
	# 1. Hacemos warp solo cuando el joystick está activo.
	Input.warp_mouse_position(cursor_sprite.position)
	
	# 2. Forzamos un evento de movimiento para que la UI detecte el "hover".
	var motion_event = InputEventMouseMotion.new()
	motion_event.position = cursor_sprite.position
	motion_event.global_position = cursor_sprite.position
	get_tree().input_event(motion_event)

func clamp_cursor_to_screen():
	# Hacemos clamp para que el centro del cursor pueda llegar a los bordes.
	var viewport_size = get_viewport().size
	cursor_sprite.position.x = clamp(cursor_sprite.position.x, 0, viewport_size.x)
	cursor_sprite.position.y = clamp(cursor_sprite.position.y, 0, viewport_size.y)

func _on_viewport_size_changed():
	# Cuando la ventana cambia de tamaño, nos aseguramos de que el cursor siga dentro.
	clamp_cursor_to_screen()

func _on_Third_pressed():
	get_tree().change_scene("res://World.tscn")
	
func _on_Flight_pressed():
	get_tree().change_scene("res://example/Example1_Simple.tscn")
