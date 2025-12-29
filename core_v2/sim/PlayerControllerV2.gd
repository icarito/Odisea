extends KinematicBody

const InputProviderV2 = preload("../input/InputProviderV2.gd")

const FIXED_DT := 1.0 / 60.0
const UP := Vector3.UP


# --- EXPORTED TUNING ---
export(float) var move_speed := 5.0 setget set_move_speed, get_move_speed
export(float) var run_speed_multiplier := 1.8 setget set_run_speed_multiplier, get_run_speed_multiplier # Correr será un 80% más rápido
export(float) var gravity := -9.8 setget set_gravity, get_gravity
export(float) var jump_force := 8.0 setget set_jump_force, get_jump_force
export(float) var mouse_sensitivity := 0.005 setget set_mouse_sensitivity, get_mouse_sensitivity

# Métodos de acceso para export (opcional, para Inspector)
func set_move_speed(v):
	if v == null:
		move_speed = 5.0
	else:
		move_speed = v
func get_move_speed(): return move_speed
func set_run_speed_multiplier(v):
	if v == null:
		run_speed_multiplier = 1.8
	else:
		run_speed_multiplier = v
func get_run_speed_multiplier(): return run_speed_multiplier
func set_gravity(v):
	if v == null:
		gravity = -9.8
	else:
		gravity = v
func get_gravity(): return gravity
func set_jump_force(v):
	if v == null:
		jump_force = 8.0
	else:
		jump_force = v
func get_jump_force(): return jump_force
func set_mouse_sensitivity(v):
	if v == null:
		mouse_sensitivity = 0.005
	else:
		mouse_sensitivity = v
func get_mouse_sensitivity(): return mouse_sensitivity

# --- SEÑALES ---
signal jumped

## --- SNAPSHOT SERIALIZACIÓN ---
func get_full_snapshot() -> Dictionary:
	return {
		"position": [self.global_transform.origin.x, self.global_transform.origin.y, self.global_transform.origin.z],
		"velocity": [velocity.x, velocity.y, velocity.z],
		"yaw": yaw,
		"pitch": pitch
	}

func restore_snapshot(data: Dictionary) -> void:
	if data.has("position"):
		var pos = data["position"]
		if typeof(pos) == TYPE_ARRAY:
			pos = Vector3(pos[0], pos[1], pos[2])
		var t = self.global_transform
		t.origin = pos
		self.global_transform = t
	if data.has("velocity"):
		var vel = data["velocity"]
		if typeof(vel) == TYPE_ARRAY:
			vel = Vector3(vel[0], vel[1], vel[2])
		velocity = vel
	else:
		velocity = Vector3.ZERO
	if data.has("yaw"):
		yaw = data["yaw"]
		self.rotation.y = yaw
	if data.has("pitch"):
		pitch = data["pitch"]
		if camera_rig:
			camera_rig.rotation.x = pitch

# state
var velocity := Vector3()
var yaw := 0.0
var pitch := 0.0

# Nodos (Asegúrate de que los nombres coincidan con tu escena)
onready var camera_rig = $CameraRig 

var input_provider
var external_input_provided := false

func _ready():
	input_provider = InputProviderV2.new()
	# La captura del mouse ahora es gestionada por SessionManager.

func _input(event):
	# La única responsabilidad en _input es acumular el delta del mouse
	# para que el InputProvider lo consuma en el frame de física.
	if event is InputEventMouseMotion:
		if input_provider:
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
		emit_signal("jumped") # Emitimos la señal del evento de salto

	# --- APPLY ---
	velocity = move_and_slide(velocity, UP)

func _physics_process(_delta):
	# Si otro sistema (SessionManager) ya llamó a step() con el input de este frame,
	# evitamos consumir el provider dos veces. Solo limpiamos el acumulador.
	if external_input_provided:
		external_input_provided = false
		# acumulador ya fue limpiado por el provider en modo LIVE
		return

	var input = input_provider.get_input()
	step(FIXED_DT, input)
	# Nota: el proveedor ya limpia `mouse_delta_accum` en _read_live_input()
