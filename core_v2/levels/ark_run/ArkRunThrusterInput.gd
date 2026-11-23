extends Node

# FD-324 F1 - propulsores de vuelo (LT del mando + tecla configurable).
#
# Mapeo determinista de intents: solo produce una direccion y un delta-v finito.
# El impulso se delega en SpinRealPhysicsV2.apply_spin_thruster(dir, dt), que
# mantiene el presupuesto finito `spin_thruster_dv_max`; este modulo nunca
# escribe transform ni posicion. LT (JOY_ANALOG_L2) es el gatillo del mando
# (decision #6) y la tecla de teclado es configurable por scancode o por action.

const EPSILON := 1e-6
const DEFAULT_DEADZONE := 0.25
const DEFAULT_KEY_SCANCODE := KEY_Q

export(float) var deadzone := DEFAULT_DEADZONE
export(int) var keyboard_thruster_scancode := DEFAULT_KEY_SCANCODE
export(String) var keyboard_thruster_action := ""
export(int) var gamepad_device := 0

# --- API pura (determinista, testeable headless) ---

static func is_thrusting(
	left_trigger: float, keyboard_pressed: bool, deadzone_value: float = DEFAULT_DEADZONE
) -> bool:
	return keyboard_pressed or left_trigger > deadzone_value

# Misma convencion que PlayerControllerV2._get_move_direction (FREE):
# right * move.x + forward * (-move.y), proyectado sobre el horizonte del up.
static func thrust_direction(move_vec: Vector2, heading_basis: Basis, up: Vector3) -> Vector3:
	var sim_up: Vector3 = up.normalized() if up.length_squared() > EPSILON else Vector3.UP
	var forward: Vector3 = -heading_basis.z
	forward -= sim_up * forward.dot(sim_up)
	if forward.length_squared() > EPSILON:
		forward = forward.normalized()
	else:
		forward = Vector3.FORWARD
	var right: Vector3 = heading_basis.x
	right -= sim_up * right.dot(sim_up)
	if right.length_squared() > EPSILON:
		right = right.normalized()
	else:
		right = Vector3.RIGHT
	var direction: Vector3 = right * move_vec.x + forward * (-move_vec.y)
	if direction.length_squared() <= EPSILON:
		return Vector3.ZERO
	return direction.normalized()

# Aplica un tick de propulsor delegando en SpinRealPhysicsV2. Devuelve el delta-v
# realmente aplicado (0 si el gatillo/tecla esta inactivo o el presupuesto se agoto).
static func apply(
	physics, dt: float, direction: Vector3, left_trigger: float,
	keyboard_pressed: bool, deadzone_value: float = DEFAULT_DEADZONE
) -> float:
	if physics == null or not is_instance_valid(physics) or dt <= 0.0:
		return 0.0
	if not is_thrusting(left_trigger, keyboard_pressed, deadzone_value):
		return 0.0
	if direction.length_squared() <= EPSILON:
		return 0.0
	return float(physics.apply_spin_thruster(direction, dt))

# Tick completo: aplica el propulsor, consume el impulso del tick y delega la
# integracion de vuelo libre en SpinRealPhysicsV2.air_step. Determinista.
static func step_with_thrust(
	physics, position: Vector3, velocity: Vector3, dt: float, direction: Vector3,
	left_trigger: float, keyboard_pressed: bool,
	deadzone_value: float = DEFAULT_DEADZONE
) -> Dictionary:
	if physics == null or not is_instance_valid(physics):
		return {"position": position, "velocity": velocity, "dv": 0.0}
	var dv: float = apply(
		physics, dt, direction, left_trigger, keyboard_pressed, deadzone_value
	)
	var impulse: Vector3 = Vector3.ZERO
	if physics != null and is_instance_valid(physics):
		var raw = physics.get("_thruster_delta_v")
		if typeof(raw) == TYPE_VECTOR3:
			impulse = raw
		physics.set("_thruster_delta_v", Vector3.ZERO)
	var state: Dictionary = physics.air_step(position, velocity + impulse, dt)
	return {"position": state["position"], "velocity": state["velocity"], "dv": dv}

# --- Nodo: lectura de input real ---

# LT: recorre TODOS los devices (id 0 no es garantía) y combina eje + botón.
func read_left_trigger() -> float:
	var value: float = 0.0
	for device in Input.get_connected_joypads():
		value = max(value, Input.get_joy_axis(device, JOY_ANALOG_L2))
		if Input.is_joy_button_pressed(device, JOY_L2):
			value = 1.0
	return value

func read_keyboard_pressed() -> bool:
	# FD-325: `thruster_boost` (tecla Shift/Q + LT del mando) es la acción oficial; el botón
	# táctil IMPULSO la sintetiza con Input.action_press, así que este camino cubre touch y
	# teclado sin distinguir la fuente.
	if InputMap.has_action("thruster_boost") and Input.is_action_pressed("thruster_boost"):
		return true
	if keyboard_thruster_action != "" and InputMap.has_action(keyboard_thruster_action):
		if Input.is_action_pressed(keyboard_thruster_action):
			return true
	return Input.is_key_pressed(keyboard_thruster_scancode) or Input.is_key_pressed(KEY_Q)

func apply_input(physics, dt: float, move_vec: Vector2, heading_basis: Basis, up: Vector3) -> float:
	var direction: Vector3 = thrust_direction(move_vec, heading_basis, up)
	return apply(
		physics, dt, direction, read_left_trigger(), read_keyboard_pressed(), deadzone
	)
