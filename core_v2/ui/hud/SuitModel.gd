extends Reference

# SuitModel.gd - Modelo de datos puro del traje de Elias (pantalla "Traje").
#
# La pantalla "Traje" (core_v2/things/SuitScreen.gd) reune tres cosas en una sola
# superficie, cada una con su seccion:
#   1) ESTADO del traje (integridad, oxigeno, temperatura, energia, enlace).
#   2) COMUNICACIONES (log de mensajes guionado: Odisea IA, Cargol).
#   3) OBJETIVOS (la lista de tareas; el primero es "Encender las luces").
#
# CONTRATO DE DETERMINISMO (AGENTS §5.3): sin nodos, sin OS.get_ticks, sin rand.
# Todo estado es String/bool/int serializable; los mensajes se numeran con un contador
# propio (_comms_seq), no con un reloj. Es data pura: el snapshot entero se puede pasar
# por to_json()/parse_json() sin perder nada.
#
# CONTRATO DEL SNAPSHOT (lo que consumen SuitWidget y SuitScreenImGui):
#   {
#     "proto": 1,
#     "id": "suit:status",
#     "title": "Traje",
#     "source": "online",
#     "urgency": String,              # maximo entre el estado y los objetivos
#     "state": {                      # enteros (porcentajes), no floats
#       "integrity": int, "oxygen": int, "temperature": int,
#       "power": int, "link": int, "breach": bool,
#       "status": "nominal|caution|alarm|offline"
#     },
#     "objectives": [ {"id": String, "text": String, "state": String, "urgency": String} ],
#     "active_objective": {"id": String, "text": String}, # {} si no hay activo
#     "comms": [ {"seq": int, "from": String, "text": String, "channel": String,
#                 "unread": bool} ],
#     "unread_comms": int
#   }
# Los colores NO viajan: el estado viaja como nombre y quien dibuja lo resuelve contra
# OdiseaOSTheme (unica fuente del mapeo).

const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")

const SCREEN_ID := "suit:status"
const SCREEN_TITLE := "Traje"

# Estados de objetivo (mismo vocabulario en toda la interfaz del traje).
const OBJ_ACTIVE := "activo"
const OBJ_PENDING := "pendiente"
const OBJ_DONE := "hecho"

# Estado del traje, en el vocabulario de OdiseaOSTheme.STATE_BY_NAME.
const STATUS_NOMINAL := "nominal"
const STATUS_CAUTION := "caution"
const STATUS_ALARM := "alarm"
const STATUS_OFFLINE := "offline"

# El primer objetivo del traje. Por decision de producto es DATA por ahora: el cableado
# al sistema real de luces (AuxPowerBus) queda para una tarea posterior.
const FIRST_OBJECTIVE := {"id": "lights", "text": "Encender las luces"}

# Estado nominal de arranque. Todos los valores son enteros: la lectura es data pura
# serializable (sin floats), tal como la consumen los widgets.
const NOMINAL_STATE := {
	"integrity": 100,
	"oxygen": 100,
	"temperature": 21,
	"power": 100,
	"link": 100,
	"breach": false,
}

# Urgencia que aporta cada estado de objetivo al maximo agregado.
const OBJECTIVE_URGENCY := {
	OBJ_ACTIVE: "notice",
	OBJ_PENDING: "quiet",
	OBJ_DONE: "quiet",
}

var _state: Dictionary = {}
var _objectives: Array = []
var _comms: Array = []
var _comms_seq: int = 0
var _unread: int = 0


func _init() -> void:
	reset()


# Vuelve el modelo al estado de arranque: traje nominal, primer objetivo activo y el
# primer par de mensajes de Odisea. Es la unica fuente de la siembra (determinista).
func reset() -> void:
	_state = NOMINAL_STATE.duplicate(true)
	_objectives = [{
		"id": String(FIRST_OBJECTIVE["id"]),
		"text": String(FIRST_OBJECTIVE["text"]),
		"state": OBJ_ACTIVE,
	}]
	_comms = []
	_comms_seq = 0
	_unread = 0
	add_comms("ODISEA", "Oficial Elias, bienvenido. Sistemas del sector en reserva.", "odisea")
	add_comms("ODISEA", "Prioridad: restablecer la iluminacion del sector.", "odisea")


# --- ESTADO DEL TRAJE ---------------------------------------------------------

func get_state_value(key: String):
	return _state.get(key, null)


func set_state_field(key: String, value) -> bool:
	if not NOMINAL_STATE.has(key):
		return false
	_state[key] = value
	return true


func set_breach(value: bool) -> void:
	_state["breach"] = value


# Nombre de estado del traje (OdiseaOSTheme) derivado del estado actual. Un traje
# agujereado o muy danado es alarma; oxigeno/energia bajos o frio son caution.
func status() -> String:
	if bool(_state.get("breach", false)) or int(_state.get("integrity", 100)) <= 25:
		return STATUS_ALARM
	if int(_state.get("oxygen", 100)) <= 30 or int(_state.get("power", 100)) <= 30 \
			or int(_state.get("temperature", 21)) <= -20:
		return STATUS_CAUTION
	return STATUS_NOMINAL


# --- OBJETIVOS ----------------------------------------------------------------

func objective_ids() -> Array:
	var ids: Array = []
	for obj in _objectives:
		ids.append(String(obj["id"]))
	return ids


func objective_state(id: String) -> String:
	var index := _index_of_objective(id)
	if index < 0:
		return ""
	return String(_objectives[index]["state"])


# Agrega un objetivo. Un id repetido se rechaza (la lista no tiene duplicados).
func add_objective(id: String, text: String, state: String = OBJ_PENDING) -> bool:
	if id.empty() or _index_of_objective(id) >= 0:
		return false
	_objectives.append({"id": id, "text": text, "state": _normalize_objective_state(state)})
	return true


func set_objective_state(id: String, state: String) -> bool:
	var index := _index_of_objective(id)
	if index < 0:
		return false
	_objectives[index]["state"] = _normalize_objective_state(state)
	return true


func complete_objective(id: String) -> bool:
	return set_objective_state(id, OBJ_DONE)


# El primer objetivo ACTIVO, o {} si no hay ninguno. Solo hay uno a la vez por diseño.
func active_objective() -> Dictionary:
	for obj in _objectives:
		if String(obj["state"]) == OBJ_ACTIVE:
			return {"id": String(obj["id"]), "text": String(obj["text"])}
	return {}


# --- COMUNICACIONES -----------------------------------------------------------

# Agrega un mensaje al log. El seq es un contador propio del modelo (nunca un reloj):
# el replay reproduce exactamente el mismo orden.
func add_comms(from: String, text: String, channel: String = "odisea") -> Dictionary:
	var entry := {
		"seq": _comms_seq,
		"from": from,
		"text": text,
		"channel": channel,
		"unread": true,
	}
	_comms_seq += 1
	_comms.append(entry)
	_unread += 1
	return entry


func mark_comms_read() -> void:
	for entry in _comms:
		entry["unread"] = false
	_unread = 0


func unread_comms() -> int:
	return _unread


# --- LECTURA ------------------------------------------------------------------

func snapshot() -> Dictionary:
	var objectives_out: Array = []
	var worst := OdiseaOSTheme.urgency_level(_state_urgency())
	var active := {}
	for obj in _objectives:
		var state := String(obj["state"])
		var level := OdiseaOSTheme.urgency_level(String(OBJECTIVE_URGENCY.get(state, OdiseaOSTheme.URGENCY_QUIET)))
		worst = int(max(worst, level))
		objectives_out.append({
			"id": String(obj["id"]),
			"text": String(obj["text"]),
			"state": state,
			"urgency": OdiseaOSTheme.URGENCY_ORDER[level],
		})
		if state == OBJ_ACTIVE and active.empty():
			active = {"id": String(obj["id"]), "text": String(obj["text"])}
	return {
		"proto": 1,
		"id": SCREEN_ID,
		"title": SCREEN_TITLE,
		"source": "online",
		"urgency": OdiseaOSTheme.URGENCY_ORDER[worst],
		"state": {
			"integrity": int(_state.get("integrity", 100)),
			"oxygen": int(_state.get("oxygen", 100)),
			"temperature": int(_state.get("temperature", 21)),
			"power": int(_state.get("power", 100)),
			"link": int(_state.get("link", 100)),
			"breach": bool(_state.get("breach", false)),
			"status": status(),
		},
		"objectives": objectives_out,
		"active_objective": active,
		"comms": _comms.duplicate(true),
		"unread_comms": _unread,
	}


# --- helpers ------------------------------------------------------------------

func _state_urgency() -> String:
	match status():
		STATUS_ALARM:
			return OdiseaOSTheme.URGENCY_ALARM
		STATUS_CAUTION:
			return OdiseaOSTheme.URGENCY_URGENT
	return OdiseaOSTheme.URGENCY_QUIET


func _index_of_objective(id: String) -> int:
	for i in range(_objectives.size()):
		if String(_objectives[i]["id"]) == id:
			return i
	return -1


func _normalize_objective_state(state: String) -> String:
	# Un estado desconocido cae a PENDIENTE: no inventa un objetivo cumplido ni activo.
	if state == OBJ_ACTIVE or state == OBJ_DONE:
		return state
	return OBJ_PENDING


# Estado de objetivo -> nombre de estado de OdiseaOSTheme.state(). Unica fuente del
# mapeo, igual que ProtocolModel.theme_state_of(): ACTIVO -> active, HECHO -> nominal,
# PENDIENTE -> offline (apagado).
static func objective_theme_state(state: String) -> String:
	if state == OBJ_ACTIVE:
		return "active"
	if state == OBJ_DONE:
		return "nominal"
	return "offline"
