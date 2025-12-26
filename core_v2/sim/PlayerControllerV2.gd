extends KinematicBody

const FIXED_DT := 1.0 / 60.0
const UP := Vector3.UP

# tuning
const MOVE_SPEED := 6.0
const GRAVITY := -9.8
const JUMP_FORCE := 8.0
export var mouse_sensitivity := 0.0001

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

	# --- HORIZONTAL VELOCITY ---
	var target = dir * MOVE_SPEED
	velocity.x = target.x
	velocity.z = target.z

	# --- GRAVITY ---
	velocity.y += GRAVITY * dt

	# --- JUMP ---
	if input.jump and is_on_floor():
		velocity.y = JUMP_FORCE

	# --- APPLY ---
	velocity = move_and_slide(velocity, UP)

func _physics_process(_delta):
    var input := input_provider.get_frame_input()
    step(FIXED_DT, input)