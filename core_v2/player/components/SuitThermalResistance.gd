extends Node
class_name SuitThermalResistance

# FD-051: la resistencia térmica del traje de mantenimiento de Elías.
#
# CAPA LÓGICA. Convierte el contacto de calor del FireSystem en degradación gradual antes
# de matar. El fuego no mata por contacto: agota el traje, y solo entonces Elías muere.
# Este nodo no sabe de respawn — solo reporta estado con `suit_breached`.

signal thermal_state_changed(ratio)
signal suit_breached()

# Integridad térmica total del traje.
export(float) var max_integrity := 100.0
# Recuperación por segundo fuera del calor.
export(float) var regen_per_second := 8.0
# Segundos sin contacto antes de empezar a regenerar.
export(float) var regen_delay := 2.0
# Si el traje se pierde, poner en false: el fuego mata de inmediato.
export(bool) var suit_equipped := true

var integrity := 0.0
var is_breached := false

var _regen_delay_timer := 0.0
# Acumula el dps recibido este frame físico; se consume en _physics_process.
var _pending_dps := 0.0
var _owner_body: Node = null
var _fire_system: Node = null
var _ice_level: Node = null

func _init() -> void:
	add_to_group("replay_sync")

func _ready() -> void:
	integrity = max_integrity if suit_equipped else 0.0
	is_breached = false
	_regen_delay_timer = 0.0
	_owner_body = _resolve_owner_body()
	call_deferred("_connect_fire_system")
	call_deferred("_connect_ice_level")
	emit_signal("thermal_state_changed", get_ratio())

func get_ratio() -> float:
	if max_integrity <= 0.0:
		return 0.0
	return clamp(integrity / max_integrity, 0.0, 1.0)

func is_taking_heat() -> bool:
	return _pending_dps > 0.0

# Vía pública de daño: la usa el FireSystem y cualquier otra fuente térmica.
func apply_heat(dps: float) -> void:
	if dps <= 0.0:
		return
	_pending_dps += dps

func reset() -> void:
	integrity = max_integrity if suit_equipped else 0.0
	is_breached = false
	_regen_delay_timer = 0.0
	_pending_dps = 0.0
	emit_signal("thermal_state_changed", get_ratio())

func _physics_process(delta: float) -> void:
	# En reproduccion de hotzone este componente no avanza con el reloj de pared: lo llama
	# HotzonePlayer con el delta grabado, en lockstep con el jugador. Sin esto derivaba
	# entre snapshots, y como la integridad del traje decide el dano, esa deriva entraba
	# en la simulacion del jugador.
	if _is_hotzone_playback():
		return
	step(delta)


func _is_hotzone_playback() -> bool:
	var sm = get_node_or_null("/root/SessionManager")
	return sm != null and bool(sm.get("is_hotzone_playback"))


# Avance determinista del estado termico. Separado de _physics_process para que el replay
# pueda invocarlo con el delta grabado.
func step(delta: float) -> void:
	# Reconexión perezosa: el FireSystem puede aparecer después que el jugador.
	if not is_instance_valid(_fire_system):
		_connect_fire_system()
	if not is_instance_valid(_ice_level):
		_connect_ice_level()

	var previous_ratio := get_ratio()

	if _pending_dps > 0.0:
		_regen_delay_timer = regen_delay
		if not is_breached:
			integrity = max(integrity - _pending_dps * delta, 0.0)
		_pending_dps = 0.0
	elif not is_breached:
		if _regen_delay_timer > 0.0:
			_regen_delay_timer = max(_regen_delay_timer - delta, 0.0)
		elif integrity < max_integrity:
			integrity = min(integrity + regen_per_second * delta, max_integrity)

	var ratio := get_ratio()
	if abs(ratio - previous_ratio) > 0.00001:
		emit_signal("thermal_state_changed", ratio)

	if integrity <= 0.0 and not is_breached:
		is_breached = true
		emit_signal("suit_breached")

func _resolve_owner_body() -> Node:
	var node: Node = get_parent()
	while is_instance_valid(node):
		if node.is_in_group("player") or node is KinematicBody:
			return node
		node = node.get_parent()
	return get_parent()

func _connect_fire_system() -> void:
	if not get_tree():
		return
	var systems: Array = get_tree().get_nodes_in_group("fire_system")
	if systems.empty():
		return
	var system: Node = systems[0]
	if not is_instance_valid(system):
		return
	_fire_system = system
	if not system.is_connected("heat_contact", self, "_on_heat_contact"):
		var _err = system.connect("heat_contact", self, "_on_heat_contact")

func _on_heat_contact(body: Node, dps: float, _in_core: bool) -> void:
	if body != _owner_body:
		return
	apply_heat(dps)

# El mismo aislamiento térmico protege de extremos fríos y calientes; mantenemos una
# única integridad determinista en vez de duplicar estados del traje.
func apply_cold(dps: float) -> void:
	apply_heat(dps)

func _connect_ice_level() -> void:
	if not get_tree():
		return
	var systems: Array = get_tree().get_nodes_in_group("ice_level")
	if systems.empty():
		return
	var system: Node = systems[0]
	if not is_instance_valid(system):
		return
	_ice_level = system
	if not system.is_connected("frost_contact", self, "_on_frost_contact"):
		var _err = system.connect("frost_contact", self, "_on_frost_contact")

func _on_frost_contact(body: Node, dps: float, _in_core: bool) -> void:
	if body != _owner_body:
		return
	apply_cold(dps)

# --- REPLAY ---

func get_snapshot() -> Dictionary:
	return {
		"integrity": integrity,
		"is_breached": is_breached,
		"regen_delay_timer": _regen_delay_timer
	}

func restore_snapshot(data: Dictionary) -> void:
	integrity = float(data.get("integrity", max_integrity))
	is_breached = bool(data.get("is_breached", false))
	_regen_delay_timer = float(data.get("regen_delay_timer", 0.0))
	_pending_dps = 0.0
	emit_signal("thermal_state_changed", get_ratio())
