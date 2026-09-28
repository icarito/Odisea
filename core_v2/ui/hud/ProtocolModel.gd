extends Reference

# ProtocolModel.gd - Modelo de datos puro del protocolo de arranque (FD-319 T4).
#
# Spec: docs/features/FD-319_ejes_traje_protocolo_arranque.md §"Protocolo de arranque".
# Es la agenda de Elias: 6 pasos mapeados 1:1 al grafo de progresion, UN solo paso
# ACTIVO a la vez, y FALLO transitorio (p. ej. intentar el 4 sin el 3).
#
# CONTRATO DE DETERMINISMO (AGENTS §5.3, FD-319 §Riesgos): sin nodos, sin
# OS.get_ticks, sin rand. Todo estado es String/bool/int serializable y nace de las
# llamadas de quien lo conduce (T5: el grafo de progresion), nunca de un reloj.
#
# CONTRATO DEL SNAPSHOT (lo que consumen ProtocolWidget y ProtocolScreenImGui):
#   {
#     "proto": 1,
#     "id": "suit:protocol",
#     "title": "Protocolo de arranque",
#     "source": "online",
#     "done": bool,
#     "urgency": String,            # nivel agregado: el maximo entre los pasos
#     "steps": [                    # en orden, 6 entradas
#       {"id": "aux_power", "system": "...", "verb": "...", "accent": "ship",
#        "state": "pendiente|activo|fallo|hecho", "urgency": "quiet|notice|urgent|alarm"},
#       ...
#     ]
#   }
# Los colores NO viajan: la identidad viaja como token ("accent") y el estado como
# nombre; quien dibuja los resuelve contra OdiseaOSTheme (ver theme_state_of e
# identity_color aca abajo, unica fuente de ambos mapeos).

const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")

const SCREEN_ID := "suit:protocol"
const SCREEN_TITLE := "Protocolo de arranque"

const STATE_PENDING := "pendiente"
const STATE_ACTIVE := "activo"
const STATE_FAIL := "fallo"
const STATE_DONE := "hecho"

# El verbo es la instruccion (FD-319 regla dura 2): nunca "criocoolant: fallo",
# siempre "sellar fuga...". "accent" es el token de identidad (FD-319 eje 1):
# ship=verde, suit=cian, alt=ambar, ink=blanco; vacio = neutro del traje.
const STEPS := [
	{"id": "aux_power", "system": "Energía auxiliar", "verb": "Restablecer respaldo de emergencia", "accent": "ship"},
	{"id": "boot_sequence", "system": "Secuencia de arranque", "verb": "Ejecutar secuencia de arranque", "accent": ""},
	{"id": "coolant", "system": "Criocoolant", "verb": "Sellar fuga del circuito de refrigeración", "accent": "suit"},
	{"id": "main_power", "system": "Energía principal", "verb": "Reacoplar el reactor", "accent": "alt"},
	{"id": "atmosphere", "system": "Atmósfera", "verb": "Igualar presión del sector", "accent": "ink"},
	{"id": "hangar_access", "system": "Acceso hangar", "verb": "Abrir esclusa inferior del domo", "accent": ""},
]

# Estado de paso -> nombre de estado de OdiseaOSTheme.state(). Un estado desconocido
# se lee "offline" ("sin lectura"), que es la verdad (Manual §7).
const STEP_STATE_TO_THEME := {
	STATE_PENDING: "offline",
	STATE_ACTIVE: "active",
	STATE_FAIL: "alarm",
	STATE_DONE: "nominal",
}

# Urgencia por defecto segun estado (FD-319: ACTIVO pulsa notice; FALLO es un fallo
# activo del sistema, urgent). set_urgency() puede elevar, nunca bajar de este piso.
const STATE_URGENCY := {
	STATE_PENDING: "quiet",
	STATE_ACTIVE: "notice",
	STATE_FAIL: "urgent",
	STATE_DONE: "quiet",
}

var _states: Array = []
var _urgency_overrides := {}
var _current: int = 0 # indice del UNICO paso activo; -1 = protocolo terminado


func _init() -> void:
	for _i in range(STEPS.size()):
		_states.append(STATE_PENDING)
	# El protocolo arranca enfocado: el paso 1 es el UNICO activo desde el inicio.
	if not _states.empty():
		_states[0] = STATE_ACTIVE


# --- consulta --------------------------------------------------------------------

func step_count() -> int:
	return STEPS.size()


func step_id(index: int) -> String:
	if index < 0 or index >= STEPS.size():
		return ""
	return String(STEPS[index].get("id", ""))


func step_state(step_id: String) -> String:
	var index := _index_of(step_id)
	if index < 0:
		return ""
	return String(_states[index])


func active_id() -> String:
	if _current < 0:
		return ""
	return step_id(_current)


func is_done() -> bool:
	return _current < 0


func set_urgency(step_id: String, level: String) -> void:
	# Piso por estado + techo por vocabulario (normalize). El FALLO nunca baja de
	# urgent: es un fallo activo, no una nota al margen.
	_urgency_overrides[step_id] = OdiseaOSTheme.normalize_urgency(level)


func snapshot() -> Dictionary:
	var steps: Array = []
	var worst := 0
	for i in range(STEPS.size()):
		var definition: Dictionary = STEPS[i]
		var state := String(_states[i])
		var default_urgency := String(STATE_URGENCY.get(state, "quiet"))
		var override := String(_urgency_overrides.get(step_id(i), ""))
		var level := int(max(OdiseaOSTheme.urgency_level(default_urgency), OdiseaOSTheme.urgency_level(override)))
		worst = int(max(worst, level))
		steps.append({
			"id": String(definition.get("id", "")),
			"system": String(definition.get("system", "")),
			"verb": String(definition.get("verb", "")),
			"accent": String(definition.get("accent", "")),
			"state": state,
			"urgency": OdiseaOSTheme.URGENCY_ORDER[level],
		})
	return {
		"proto": 1,
		"id": SCREEN_ID,
		"title": SCREEN_TITLE,
		"source": "online",
		"done": is_done(),
		"urgency": OdiseaOSTheme.URGENCY_ORDER[worst],
		"steps": steps,
	}


# --- mutacion (API para T5) ------------------------------------------------------

# Completa el paso activo y activa el siguiente. Los FALLO que quedaron colgando eran
# transitorios: al avanzar, mueren. En el ultimo paso deja el protocolo en done.
func advance() -> bool:
	if _current < 0:
		return false
	_states[_current] = STATE_DONE
	_urgency_overrides.erase(step_id(_current))
	for i in range(_states.size()):
		if String(_states[i]) == STATE_FAIL:
			_states[i] = STATE_PENDING
	_current += 1
	if _current >= STEPS.size():
		_current = -1
	else:
		_states[_current] = STATE_ACTIVE
	return true


# Alias explicito del verbo del checklist: solo el paso ACTIVO puede quedar HECHO.
func complete(step_id: String) -> bool:
	if step_id != active_id():
		return false
	return advance()


# Marca FALLO transitorio. Sirve tanto para el paso activo (el intento falla) como
# para un paso pendiente intentado fuera de orden (el caso del FD: el 4 sin el 3).
# No cambia cual paso es el activo. Un paso HECHO no puede fallar.
func fail(step_id: String) -> bool:
	var index := _index_of(step_id)
	if index < 0 or String(_states[index]) == STATE_DONE:
		return false
	_states[index] = STATE_FAIL
	return true


# Se acaba el rato del FALLO (lo temporiza T5 con su propio reloj de gameplay): el paso
# vuelve a PENDIENTE, o a ACTIVO si era el paso corriente.
func clear_fail(step_id: String) -> bool:
	var index := _index_of(step_id)
	if index < 0 or String(_states[index]) != STATE_FAIL:
		return false
	_states[index] = STATE_ACTIVE if index == _current else STATE_PENDING
	return true


# --- helpers ---------------------------------------------------------------------

func _index_of(step_id: String) -> int:
	for i in range(STEPS.size()):
		if String(STEPS[i].get("id", "")) == step_id:
			return i
	return -1


# Nombre de estado de OdiseaOSTheme para un estado de paso. Unica fuente del mapeo;
# el color sale de OdiseaOSTheme.state(), nunca de aca.
static func theme_state_of(step_state: String) -> String:
	if STEP_STATE_TO_THEME.has(step_state):
		return String(STEP_STATE_TO_THEME[step_state])
	return "offline"


# Token "accent" del snapshot -> color de identidad de OdiseaOSTheme. Unica fuente del
# vocabulario de identidad del checklist; un token desconocido es el neutro del traje.
static func identity_color(accent: String) -> Color:
	match accent:
		"ship":
			return OdiseaOSTheme.SHIP_ACCENT
		"suit":
			return OdiseaOSTheme.SUIT_ACCENT
		"alt":
			return OdiseaOSTheme.SHIP_ALT
		"ink":
			return OdiseaOSTheme.INK
	return OdiseaOSTheme.SUIT_DIM
