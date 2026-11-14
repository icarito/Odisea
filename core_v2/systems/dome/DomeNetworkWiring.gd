extends Node

# DomeNetworkWiring.gd — cableado de las 4 redes al DomeNetworkStatus (FD-289 §7.8, T6/T7).
#
# Es la "glue" de la escena del domo: conecta las señales de estado de las máquinas que ya
# existen (CoolantLeak/LeakPatchPoint, PlasmaRoute, AuxPowerBus, PressureSection) con
# DomeNetworkStatus.mark_healthy() cuando la red queda sana, y traduce las acciones del
# timeline de DomeSystemDirector (T2) al arranque de cada avería.
#
# POR QUÉ UN NODO Y NO UN GRAFO (§3.1): cada red declara su verbo y su precondición como una
# lista simple. Acá no hay compuertas ni grafos: es un conjunto de conexiones explícitas,
# una por red, con el estado leído del propio componente (get_state()/is_powered()/señales).
# La red de energía no simula nada: el bus es de AuxPowerBus; la de plasma, de PlasmaRoute;
# la de aire, de PressureSection; la de criocoolant, del par CoolantLeak + LeakPatchPoint.
#
# Determinismo (AGENTS.md §5.3): no hay randf/randomize ni reloj de pared. Lo único que
# corre por tick es la inyección de presión mientras el jugador sostiene la bomba (en
# _physics_process, delta de física). get_snapshot()/restore_snapshot() guardan los flags de
# "avería armada" para que un replay no vuelva a armar una red ya resuelta.

# Nodo DomeNetworkStatus del domo (vive en la escena de nivel, no es autoload).
export(NodePath) var network_status_path := NodePath("../DomeNetworkStatus")
# Director del domo (autoload). Se le registra el DomeNetworkStatus para que avance los beats.
export(NodePath) var director_path := NodePath("/root/DomeSystemDirector")

# --- Redes (una lista explícita por red; vacío = red no cableada en esta escena) ---
# Criocoolant: la red queda sana cuando TODAS estas fugas fueron reparadas (ver _all_leaks_repaired).
export(Array, NodePath) var coolant_leak_paths: Array = []
# Plasma: PlasmaRoute.route_solved -> red sana (route_broken -> vuelve a no sana).
export(NodePath) var plasma_route_path := NodePath()
# Energía: AuxPowerBus.power_restored -> red sana (power_lost -> vuelve a no sana).
export(NodePath) var aux_power_bus_path := NodePath()
# Aire: PressureSection.pressure_stabilized (tras purgar) -> red sana.
export(NodePath) var pressure_section_path := NodePath()

# --- Interacción mínima que arranca los beats ---
# Interruptor principal: el primer accionar revela la fuga de coolant (beat 1).
export(NodePath) var master_switch_path := NodePath()
# Interruptor del bus: acciona AuxPowerBus.request_restore() (beat 2/3).
export(NodePath) var power_switch_path := NodePath()
# Bomba de aire: sostener inyecta presión en la PressureSection (beat 4).
export(NodePath) var air_pump_path := NodePath()

# Compuerta de piso (BlastDoorController, T3). El director ya la abre con blast_door_open vía
# el autoconnect del propio controlador; acá sólo se le relaya el semáforo de borde (§6.2)
# con la cantidad de redes HEALTHY. Vacío = la escena todavía no instancia la compuerta.
export(NodePath) var blast_door_path := NodePath()

var _status: Node = null
var _director: Node = null
var _leaks: Array = []
var _plasma_route: Node = null
var _plasma_conduit: Node = null
var _bus: Node = null
var _section: Node = null
var _pump: Node = null
var _blast_door: Node = null

# Una red "armada" ya tuvo su avería revelada por el timeline: recién ahí su reparación
# cuenta como red sana. Sin esto, una fuga que arranca HEALTHY se leería como sana en boot.
var _coolant_armed := false
var _plasma_armed := false
var _air_armed := false


func _ready() -> void:
	add_to_group("replay_sync")
	_resolve_refs()
	_register_with_director()
	_connect_sources()
	_relay_healthy_count()
	# La bomba inyecta por tick sólo mientras se la sostiene (hold_started/hold_released).
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _section != null and _pump != null and "inject" in _section and _pump.has_method("is_held") and bool(_pump.call("is_held")):
		_section.call("inject", delta)


# --- RESOLUCIÓN ---

func _resolve_refs() -> void:
	_status = _node(network_status_path)
	_director = _node(director_path)
	for path in coolant_leak_paths:
		var leak := _node(path)
		if leak != null:
			_leaks.append(leak)
	_plasma_route = _node(plasma_route_path)
	if _plasma_route != null and _plasma_route.has_method("get_conduit"):
		_plasma_conduit = _plasma_route.call("get_conduit")
	_bus = _node(aux_power_bus_path)
	_section = _node(pressure_section_path)
	_pump = _node(air_pump_path)
	_blast_door = _node(blast_door_path)


func _node(path: NodePath) -> Node:
	if path == null or path.is_empty():
		return null
	return get_node_or_null(path)


# --- REGISTRO ---

func _register_with_director() -> void:
	if _director == null or _status == null:
		return
	if _director.has_method("register_network_status"):
		_director.call("register_network_status", _status)


func _connect_sources() -> void:
	if _status != null and _status.has_signal("network_healthy"):
		if not _status.is_connected("network_healthy", self, "_on_network_healthy"):
			_status.connect("network_healthy", self, "_on_network_healthy")

	if _director != null and _director.has_signal("timeline_event"):
		if not _director.is_connected("timeline_event", self, "_on_timeline_event"):
			_director.connect("timeline_event", self, "_on_timeline_event")

	# Criocoolant
	for leak in _leaks:
		if leak.has_signal("leak_sealed") and not leak.is_connected("leak_sealed", self, "_on_coolant_changed"):
			leak.connect("leak_sealed", self, "_on_coolant_changed")
		if leak.has_signal("state_changed") and not leak.is_connected("state_changed", self, "_on_coolant_state_changed"):
			leak.connect("state_changed", self, "_on_coolant_state_changed")

	# Plasma
	if _plasma_route != null:
		if _plasma_route.has_signal("route_solved") and not _plasma_route.is_connected("route_solved", self, "_on_plasma_solved"):
			_plasma_route.connect("route_solved", self, "_on_plasma_solved")
		if _plasma_route.has_signal("route_broken") and not _plasma_route.is_connected("route_broken", self, "_on_plasma_broken"):
			_plasma_route.connect("route_broken", self, "_on_plasma_broken")

	# Energía
	if _bus != null:
		if _bus.has_signal("power_restored") and not _bus.is_connected("power_restored", self, "_on_power_restored"):
			_bus.connect("power_restored", self, "_on_power_restored")
		if _bus.has_signal("power_lost") and not _bus.is_connected("power_lost", self, "_on_power_lost"):
			_bus.connect("power_lost", self, "_on_power_lost")

	# Aire
	if _section != null and _section.has_signal("pressure_stabilized"):
		if not _section.is_connected("pressure_stabilized", self, "_on_pressure_stabilized"):
			_section.connect("pressure_stabilized", self, "_on_pressure_stabilized")

	# Interruptores / bomba
	_connect_switch(master_switch_path, "_on_master_switch")
	_connect_switch(power_switch_path, "_on_power_switch")
	if _pump != null:
		if _pump.has_signal("hold_started") and not _pump.is_connected("hold_started", self, "_on_pump_hold_changed"):
			_pump.connect("hold_started", self, "_on_pump_hold_changed")
		if _pump.has_signal("hold_released") and not _pump.is_connected("hold_released", self, "_on_pump_hold_changed"):
			_pump.connect("hold_released", self, "_on_pump_hold_changed")


func _connect_switch(path: NodePath, handler: String) -> void:
	var node := _node(path)
	if node == null:
		return
	if node.has_signal("lever_toggled") and not node.is_connected("lever_toggled", self, handler):
		node.connect("lever_toggled", self, handler)
	elif node.has_signal("activated") and not node.is_connected("activated", self, handler):
		node.connect("activated", self, handler)


# --- TIMELINE (acciones del director) ---

func _on_timeline_event(_event: String, action: String, _beat: int) -> void:
	match action:
		"spawn_coolant_leak":
			_arm_coolant()
		"enable_plasma_route":
			_arm_plasma()
		"enable_air_system":
			_arm_air()


func _arm_coolant() -> void:
	_coolant_armed = true
	for leak in _leaks:
		if leak.has_method("trigger_leak"):
			leak.call("trigger_leak")


func _arm_plasma() -> void:
	_plasma_armed = true
	if _plasma_conduit != null and _plasma_conduit.has_method("trigger_overheat"):
		_plasma_conduit.call("trigger_overheat")


func _arm_air() -> void:
	_air_armed = true
	if _section != null and _section.has_method("raise_pressure"):
		_section.call("raise_pressure")


# --- INTERACCIÓN ---

func _on_master_switch(_is_on = null) -> void:
	# El interruptor principal sólo dispara el beat 1 (el director lo ignora si ya pasó).
	if _director != null and _director.has_method("request_first_power_attempt"):
		_director.call("request_first_power_attempt")


func _on_power_switch(_is_on = null) -> void:
	if _bus != null and _bus.has_method("request_restore"):
		_bus.call("request_restore")


func _on_pump_hold_changed(_arg = null) -> void:
	if is_inside_tree() and _section != null and _pump != null and "inject" in _section:
		set_physics_process(_pump.has_method("is_held") and bool(_pump.call("is_held")))


# --- SALUD DE RED ---

func _on_coolant_changed(_arg = null) -> void:
	_evaluate_coolant()


func _on_coolant_state_changed(_new_state = null) -> void:
	_evaluate_coolant()


func _evaluate_coolant() -> void:
	if not _coolant_armed:
		return
	if _all_leaks_repaired():
		_mark_healthy("criocoolant")


# Una fuga está reparada sólo si volvió a HEALTHY (0) o quedó SEALED (3). DEPRESSURIZED (4) es
# el corte de caudal por la válvula aguas arriba, no una reparación (FD-266).
func _all_leaks_repaired() -> bool:
	if _leaks.empty():
		return false
	for leak in _leaks:
		if not leak.has_method("get_state"):
			return false
		var state: int = int(leak.call("get_state"))
		if state != 0 and state != 3:
			return false
	return true


func _on_plasma_solved() -> void:
	_mark_healthy("plasma")


func _on_plasma_broken() -> void:
	if _status != null and _status.has_method("mark_unhealthy"):
		_status.call("mark_unhealthy", "plasma")


func _on_power_restored() -> void:
	_mark_healthy("energia")


func _on_power_lost() -> void:
	if _status != null and _status.has_method("mark_unhealthy"):
		_status.call("mark_unhealthy", "energia")


func _on_pressure_stabilized() -> void:
	_mark_healthy("aire")


func _mark_healthy(network_id: String) -> void:
	if _status != null and _status.has_method("mark_healthy"):
		_status.call("mark_healthy", network_id)


# --- SEMÁFORO DE LA COMPUERTA (§6.2) ---

func _on_network_healthy(_network_id) -> void:
	_relay_healthy_count()


func _relay_healthy_count() -> void:
	if _blast_door == null or _status == null:
		return
	if not _blast_door.has_method("set_network_healthy_count"):
		return
	var count := 0
	if _status.has_method("healthy_count"):
		count = int(_status.call("healthy_count"))
	_blast_door.call("set_network_healthy_count", count)


# --- SNAPSHOT (Core V2 §5.3) ---

func get_snapshot() -> Dictionary:
	return {
		"v": 1,
		"coolant_armed": _coolant_armed,
		"plasma_armed": _plasma_armed,
		"air_armed": _air_armed,
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.empty():
		return
	_coolant_armed = bool(data.get("coolant_armed", _coolant_armed))
	_plasma_armed = bool(data.get("plasma_armed", _plasma_armed))
	_air_armed = bool(data.get("air_armed", _air_armed))
