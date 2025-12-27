extends KinematicBody

const FIXED_DT := 1.0 / 60.0
const UP := Vector3.UP

# --- EXPORTED TUNING ---
export var move_speed := 5.0
export var run_speed_multiplier := 1.8  # Correr será un 80% más rápido
export var gravity := -9.8
export var jump_force := 8.0
export var mouse_sensitivity := 0.005

# state
var velocity := Vector3()
var yaw := 0.0
var pitch := 0.0

# Nodos (Asegúrate de que los nombres coincidan con tu escena)
onready var camera_rig = $CameraRig 

var input_provider : InputProviderV2

func _ready():
	input_provider = InputProviderV2.new()
	# 1. CAPTURA DEL MOUSE: Bloquea el puntero al centro de la pantalla
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	# Opcional: Liberar el mouse con la tecla ESC
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Re-capturar al hacer click en la pantalla
	if event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Acumulamos el delta del mouse para determinismo
	if event is InputEventMouseMotion:
		input_provider.mouse_delta_accum += event.relative

func step(dt: float, input: InputDataV2):
	# --- ROTATION ---
	# Acumulamos los ángulos
	yaw   -= input.mouse_delta.x * mouse_sensitivity
	pitch -= input.mouse_delta.y * mouse_sensitivity
	
	# Limitamos el Pitch para no dar una voltereta (aprox -85 a 85 grados)
	pitch = clamp(pitch, deg2rad(-85), deg2rad(85))

	# APLICACIÓN:
	# El cuerpo (self) SOLO rota en Y (izquierda/derecha)
	self.rotation.y = yaw
	
	# El CameraRig SOLO rota en X (arriba/abajo)
	if camera_rig:
		camera_rig.rotation.x = pitch

	# --- MOVEMENT INPUT ---
	var dir = Vector3()

	# Usamos la base del cuerpo (que ahora solo tiene Yaw)
	# Esto garantiza que 'forward' siempre sea paralelo al suelo
	var basis = global_transform.basis
	var forward = -basis.z
	var right = basis.x

	dir += forward * input.move_vec.y
	dir += right * input.move_vec.x
	dir = dir.normalized()

	# --- SPRINT LOGIC ---
	var current_speed = move_speed
	if input.sprint: # Asumiendo que InputDataV2 ya tiene el booleano 'sprint'
		current_speed *= run_speed_multiplier

	# --- HORIZONTAL VELOCITY ---
	var target = dir * current_speed
	velocity.x = target.x
	velocity.z = target.z

	# --- GRAVITY ---
	velocity.y += gravity * dt

	# --- JUMP ---
	if input.jump and is_on_floor():
		velocity.y = jump_force

	# --- APPLY ---
	velocity = move_and_slide(velocity, UP)

func _physics_process(_delta):
	var input := input_provider.get_frame_input()
	step(FIXED_DT, input)
