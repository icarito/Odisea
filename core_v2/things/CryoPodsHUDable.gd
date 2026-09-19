extends HUDableComponent
class_name CryoPodsHUDable

# CryoPodsHUDable.gd - La bahia de criocapsulas como pantalla de OdiseaOS (FD-304 §10).
#
# UNA instancia por bahia, no una por capsula: registrar 28 Pod_NN en el radial no le aporta nada
# al jugador, que lo que quiere saber es "como esta la bahia" y, si algo pasa, cual capsula.
# Las capsulas del domo son geometria horneada (DomeIntro_CriopodsSource), asi que el roster es
# declarativo: lo que tiene ocupante se declara, y el resto se completa como capsulas vacias.
#
# La alerta NO se inventa aca: sale del sistema de criocoolant del ShipSystemBus, que ya existe y
# ya lo miran otras pantallas. Cuando el circuito falla, la bahia entera esta en riesgo.
#
# La ficha por capsula (camara interior, panel del ocupante) es FD-307 y vive en otro componente:
# aca solo esta el roster agregado y su telemetria.

const WidgetScene = preload("res://core_v2/ui/hud/CryoPodsWidget.tscn")

# Cuantas capsulas tiene la bahia. Las que no esten en el roster se reportan vacias y nominales.
export(int) var pod_count: int = 28
# Roster declarado, una capsula por linea: "id|ocupante|estado". Estado vacio = NOMINAL.
export(Array, String) var pod_roster: Array = []
# ShipSystemBus del nivel. Opcional: sin el, la bahia reporta nominal.
export(NodePath) var bus_path: NodePath = NodePath("")
# Que sistema del bus habla por la bahia.
export(String) var coolant_system_id: String = "criocoolant"

var _focused: int = 0

func _init() -> void:
	hud_screen_id = "ship:cryopods"
	hud_screen_title = "Criocápsulas"
	hud_widget_scene = WidgetScene
	default_relevance = 0.05
	allowed_actions_list = ["scan", "select"]

func _ready() -> void:
	call_deferred("_bind_bus")

func _bind_bus() -> void:
	var bus = _get_bus()
	if is_instance_valid(bus) and bus.has_signal("systems_changed") \
			and not bus.is_connected("systems_changed", self, "_on_systems_changed"):
		bus.connect("systems_changed", self, "_on_systems_changed")

func _on_systems_changed(_arg = null) -> void:
	notify_state_changed()

# FD-304 §4: A escanea la capsula enfocada. Salir es de la capa HUD (X/B), no una operacion de
# esta pantalla, asi que no se declara: declararla obligaria a inventar un op que no hace nada.
func hud_gamepad_actions() -> Array:
	return [{
		"button": "a", "op": "scan", "label": "Escanear",
		"icon": "", "enabled": true, "confirm": true
	}]

func widget_snapshot() -> Dictionary:
	var pods: Array = pods_state()
	var alarms: int = 0
	for pod in pods:
		if bool(pod["alarm"]):
			alarms += 1
	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"source": "online",
		"pods": pods,
		"alarms": alarms,
		"alarm": alarms > 0,
		"focused": int(clamp(_focused, 0, max(0, pods.size() - 1)))
	}

# JSON-safe: lo que viaja al control remoto son datos, no nodos.
func pods_state() -> Array:
	var declared: Dictionary = {}
	for line in pod_roster:
		var parts: Array = String(line).split("|", true)
		if parts.empty() or String(parts[0]).empty():
			continue
		declared[String(parts[0])] = {
			"occupant": String(parts[1]) if parts.size() > 1 else "",
			"status": String(parts[2]) if parts.size() > 2 and not String(parts[2]).empty() else "NOMINAL"
		}
	var failing: bool = _coolant_failing()
	var pods: Array = []
	for i in range(max(pod_count, declared.size())):
		var id: String = "Pod_%02d" % (i + 1)
		var row: Dictionary = declared.get(id, {"occupant": "", "status": "NOMINAL"})
		var occupied: bool = not String(row["occupant"]).empty()
		var status: String = String(row["status"])
		# Una capsula vacia no puede estar en alarma: no hay nadie adentro a quien le pase algo.
		var alarm: bool = occupied and (status != "NOMINAL" or failing)
		pods.append({
			"id": id,
			"occupant": String(row["occupant"]),
			"status": "ALERTA" if alarm and status == "NOMINAL" else status,
			"vitals": 0.0 if not occupied else (0.42 if alarm else 1.0),
			"alarm": alarm
		})
	return pods

# Base baja; sube fuerte con cualquier capsula en alarma (mismo patron que SystemStatusScreen con
# STATE_FALLO): la bahia solo pide atencion cuando algo le pasa a alguien.
func relevance(context: Dictionary = {}) -> float:
	var rel: float = default_relevance
	for pod in pods_state():
		if bool(pod["alarm"]):
			rel += 0.7
			break
	return clamp(rel, 0.0, 1.0)

func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
	var pods: Array = pods_state()
	if pods.empty():
		return {"ok": false, "error": "Bahía sin cápsulas"}
	if op == "select":
		var target: int = int(args["index"]) if args.has("index") else _focused + int(args.get("delta", 1))
		_focused = int(clamp(target, 0, pods.size() - 1))
		notify_state_changed()
		return {"ok": true, "focused": _focused, "pod": pods[_focused]["id"]}
	if op == "scan":
		var index: int = _focused
		if args.has("pod"):
			for i in range(pods.size()):
				if String(pods[i]["id"]) == String(args["pod"]):
					index = i
					break
		notify_state_changed()
		return {"ok": true, "pod": pods[index]}
	return {"ok": false, "error": "Action '%s' not supported" % op}

func _coolant_failing() -> bool:
	var bus = _get_bus()
	if not is_instance_valid(bus) or not bus.has_method("get_summary"):
		return false
	var system = bus.get_summary().get(coolant_system_id, null)
	if typeof(system) != TYPE_DICTIONARY:
		return false
	return int(system.get("state", 3)) == 2 # STATE_FALLO

func _get_bus() -> Node:
	return get_node_or_null(bus_path) if not String(bus_path).empty() else null
