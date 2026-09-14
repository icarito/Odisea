extends Reference

# Haptics.gd - Toda la vibracion del juego pasa por aca: respeta la opcion "Vibracion"
# (SettingsManager.vibration) y llega al telefono (vibrate_handheld) y a los gamepads conectados
# (start_joy_vibration, el Anbernic y cualquier mando). Es solo salida: no toca el stream de input.

# Detente del dial o cambio de destino al arrastrar: casi imperceptible, se siente como un clic.
const TICK_MSEC := 12
# Elegir en el dial u oprimir el boton de un widget: la accion se dio (en el control remoto el
# efecto se ve en el host, no bajo el dedo).
const CONFIRM_MSEC := 30
# Levantar y soltar un widget o un item del radial.
const LIFT_MSEC := 40
const DROP_MSEC := 20
# Un temblor largo no deja el telefono zumbando: la camara sigue temblando, la vibracion no.
const MAX_MSEC := 1500
# iOS sin CoreHaptics (iPad, iPhone 7 o anterior, iOS < 13) solo tiene un zumbido fijo de ~0.4 s: un
# tick de 12 ms sonaria como una alarma. Ahi solo vibran los eventos largos (un temblor).
const IOS_FIXED_BUZZ_MIN_MSEC := 200

static func enabled() -> bool:
	var tree = Engine.get_main_loop()
	var settings = tree.root.get_node_or_null("SettingsManager") if tree is SceneTree else null
	return settings == null or bool(settings.get("vibration"))

static func tick() -> void:
	pulse(TICK_MSEC, 0.35)

static func confirm() -> void:
	pulse(CONFIRM_MSEC, 0.6)

# strength 0..1: los gamepads la usan; vibrate_handheld de Godot 3 solo sabe de duracion.
static func pulse(msec: int, strength: float = 1.0) -> void:
	msec = int(min(msec, MAX_MSEC))
	if msec <= 0 or not enabled():
		return
	# ponytail: sonda para tests (Engine meta, sin variables estaticas en GDScript 3).
	if Engine.has_meta("haptics_probe"):
		Engine.get_meta("haptics_probe").append(msec)
	if _handheld_can_play(msec):
		Input.vibrate_handheld(msec)
	strength = clamp(strength, 0.0, 1.0)
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, strength, strength * 0.6, msec / 1000.0)

static func _handheld_can_play(msec: int) -> bool:
	if OS.get_name() != "iOS" or not Engine.has_singleton("iOS"):
		return true
	var ios = Engine.get_singleton("iOS")
	if not ios.supports_haptic_engine():
		return msec >= IOS_FIXED_BUZZ_MIN_MSEC
	# Godot 3 crea el CHHapticEngine pero nadie lo arranca, y con auto-shutdown se apaga al quedar
	# ocioso (o al ir la app a segundo plano). Arrancarlo ya andando no hace nada.
	ios.start_haptic_engine()
	return true
