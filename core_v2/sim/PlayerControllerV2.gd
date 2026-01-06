extends KinematicBody

const InputProviderV2 = preload("../input/InputProviderV2.gd")
const PlayerJumpV2 = preload("PlayerJumpV2.gd")
const PlayerMovementV2 = preload("PlayerMovementV2.gd")

const FIXED_DT := 1.0 / 60.0
const UP := Vector3.UP


# --- EXPORTED TUNING ---
export(float) var mouse_sensitivity := 0.005 setget set_mouse_sensitivity, get_mouse_sensitivity

# Métodos de acceso para export (opcional, para Inspector)
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
	yaw = data.get("yaw", 0.0)
	pitch = data.get("pitch", 0.0)
	
	# APLICACIÓN: Unificamos la lógica de rotación con la de step() para garantizar determinismo.
	if camera_rig:
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)

# state
var velocity := Vector3()
var yaw := 0.0
var pitch := 0.0

# Nodos (Asegúrate de que los nombres coincidan con tu escena)
onready var camera_rig = $CameraRig 
onready var animator = $Visual/Pivot

var input_provider
var external_input_provided := false

var jump_logic: PlayerJumpV2
var movement_logic: PlayerMovementV2

func _ready():
	input_provider = InputProviderV2.new()
	jump_logic = PlayerJumpV2.new()
	movement_logic = PlayerMovementV2.new()
	# Ya no necesitamos copiar variables, los componentes tienen sus propios exports

const DEFAULT_BASIS = Basis.IDENTITY

func get_camera_basis() -> Basis:
	return camera_rig.transform.basis if camera_rig else DEFAULT_BASIS

func _input(event):
	# La única responsabilidad en _input es acumular el delta del mouse
	# para que el InputProvider lo consuma en el frame de física.
	if event is InputEventMouseMotion:
		if input_provider:
			input_provider.mouse_delta_accum += event.relative

func step(dt: float, input: InputDataV2) -> void:
	# --- ROTATION ---
	# Acumulamos los ángulos
	yaw   -= input.mouse_delta.x * mouse_sensitivity
	pitch -= input.mouse_delta.y * mouse_sensitivity
	
	# Limitamos el Pitch para no dar una voltereta (aprox -85 a 85 grados)
	pitch = clamp(pitch, deg2rad(-85), deg2rad(85))

	# APLICACIÓN:
	# El cuerpo (self) ya NO rota. El CameraRig rota en AMBOS ejes para controlar la vista.
	# IMPORTANTE: No asignar yaw/pitch a rotation.y/x por separado, ya que puede causar
	# problemas de Gimbal Lock. Es más robusto construir una nueva base de rotación.
	if camera_rig:
		camera_rig.transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	
	# --- GRAVITY CLEANUP ---
	# Set velocity.y to 0 if on floor to prevent gravity force accumulation against CSG/Physics collision.
	if is_on_floor():
		velocity.y = 0
	
	# 1. Actualizar timers de los componentes
	if is_on_floor():
		jump_logic.reset_on_floor()
	else:
		jump_logic.on_air_tick(dt)
		
	if input.jump:
		jump_logic.buffer_jump()

	# 2. Delegar movimiento horizontal
	var basis = get_camera_basis()
	movement_logic.process_movement(dt, input.move_vec, basis, input.sprint, is_on_floor())
	var h_vel = movement_logic.get_horizontal_velocity()
	
	velocity.x = h_vel.x
	velocity.z = h_vel.z

	# 3. Aplicar Salto o Gravedad
	if jump_logic.can_jump(is_on_floor()):
		velocity.y = jump_logic.get_jump_force()
		jump_logic.consume_jump()
		emit_signal("jumped")
	else:
		velocity.y += jump_logic.get_gravity() * dt

	# 4. Movimiento Final y Animación
	velocity = move_and_slide(velocity, UP)
	
	if animator:
		animator.step_animator(dt, velocity)
	
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

func get_wish_direction() -> Vector3:
	"""
	Devuelve la dirección de movimiento deseada por el jugador, en coordenadas globales.
	Es usada por el animador para orientar el modelo visual.
	"""
	return movement_logic.wish_direction

func _process(_delta):
	if Engine.get_frames_per_second() < 20: # Si baja de 60fps bruscamente
		print("[PERF] Caída de frames detectada! Velocity: ", velocity, " OnFloor: ", is_on_floor())