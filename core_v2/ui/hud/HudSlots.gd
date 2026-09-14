extends Reference

# HudSlots.gd - Reglas y geometria de los 4 slots de widgets de OdiseaOS, compartidas entre el
# host (SuitOS + SuitOSWidgetHost) y el telefono (RemoteControlHome), que antes duplicaban
# la geometria. Indices 0..3 en codigo; el jugador los ve y los acciona como 1..4.

const COUNT := 4
const SLOT_ROW_HEIGHT := 96.0 # el widget mas alto hoy (SystemStatusWidget) mide 90
const SLOT_GAP := 8.0
const SLOT_PADDING := 16.0
# Vibracion del arrastre a un slot (widget o item del radial): al levantar y al soltar en un slot.
# Local al dispositivo, no por SuitOS.trigger_haptic, que la reenvia al telefono emparejado.
const LIFT_VIBRATION_MSEC := 40
const DROP_VIBRATION_MSEC := 20

static func slot_key(index: int) -> String:
	return "slot_%d" % (index + 1)

static func index_of(slot: String) -> int:
	for i in range(COUNT):
		if slot == slot_key(i):
			return i
	return -1

static func action(index: int) -> String:
	return "hud_slot_%d" % (index + 1)

# 1 y 2 a la izquierda, 3 y 4 a la derecha.
static func is_right(index: int) -> bool:
	return index >= 2

static func empty_pins() -> Array:
	var pins: Array = []
	for _i in range(COUNT):
		pins.append("")
	return pins

# Fijar en un slot concreto (tecla o widget del slot): la pantalla sale de donde estuviera,
# nunca ocupa dos slots.
static func pin_to(pins: Array, index: int, id: String) -> Array:
	var result: Array = pins.duplicate()
	if index < 0 or index >= COUNT:
		return result
	for i in range(COUNT):
		if result[i] == id:
			result[i] = ""
	result[index] = id
	return result

# Esquina superior del slot. `safe` es el area util (safe area) y `widget_size` el tamaño ya
# escalado, ambos en las unidades de quien ubica; `k` es la escala de UI de esas unidades.
static func slot_position(index: int, widget_size: Vector2, safe: Rect2, k: float = 1.0) -> Vector2:
	var row: int = index % 2
	var y: float = safe.position.y + (SLOT_PADDING + row * (SLOT_ROW_HEIGHT + SLOT_GAP)) * k
	if is_right(index):
		return Vector2(safe.end.x - SLOT_PADDING * k - widget_size.x, y)
	return Vector2(safe.position.x + SLOT_PADDING * k, y)

# Swipe hacia afuera: hacia el borde del lado del slot, mas horizontal que vertical.
static func outward_swipe(index: int, delta: Vector2, threshold: float) -> bool:
	if abs(delta.x) <= abs(delta.y):
		return false
	var outward: float = delta.x if is_right(index) else -delta.x
	return outward >= threshold
