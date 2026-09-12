extends Control
class_name CryoDiagnosticsUI

# CryoDiagnosticsUI.gd - Puente de datos de la pantalla Criogenia (FD-296 F4).
# En el HOST: collect_state() junta lo que los tres paneles leen del mundo. Es lo unico
# que viaja (datos, no raster) dentro del snapshot de HoloTerminalHUDable.
# En el CONTROL REMOTO: update_snapshot() reparte esos datos a los paneles, que dibujan
# de ellos por no tener Room3D, valvulas ni tanques ahi.

onready var _dials: Control = get_node_or_null("RoomDialsPanel")
onready var _schematic: Control = get_node_or_null("CoolantSchematicPanel")
onready var _tanks: Control = get_node_or_null("CoolantSystemStatusUI")

# Cambio de estado del circuito (valvulas, fugas, tanques): eventos discretos, se pueden
# propagar de inmediato. La telemetria de sala (temperatura/presion/toxicidad) es la que
# puede venir en rafaga y esa la debounced HoloTerminalHUDable conectandose directo.
signal circuit_state_changed


func _ready() -> void:
	for panel in [_schematic, _tanks]:
		if panel != null and panel.has_signal("state_changed") \
				and not panel.is_connected("state_changed", self, "_on_circuit_state_changed"):
			panel.connect("state_changed", self, "_on_circuit_state_changed")


func _on_circuit_state_changed(_arg = null) -> void:
	emit_signal("circuit_state_changed")


func collect_state() -> Dictionary:
	var state: Dictionary = {}
	if _dials != null and _dials.has_method("collect_state"):
		var room: Dictionary = _dials.call("collect_state")
		if not room.empty():
			state["room"] = room
	if _schematic != null and _schematic.has_method("collect_state"):
		var schematic: Dictionary = _schematic.call("collect_state")
		if not schematic.empty():
			state["schematic"] = schematic
	if _tanks != null and _tanks.has_method("collect_state"):
		var tanks: Dictionary = _tanks.call("collect_state")
		if not tanks.empty():
			state["tanks"] = tanks
	return state


func update_snapshot(snap: Dictionary) -> void:
	var cryo: Dictionary = snap.get("cryo", {}) if typeof(snap.get("cryo", {})) == TYPE_DICTIONARY else {}
	if cryo.empty():
		return
	if _dials != null and _dials.has_method("apply_state") and cryo.has("room"):
		_dials.call("apply_state", cryo["room"])
	if _schematic != null and _schematic.has_method("apply_state") and cryo.has("schematic"):
		_schematic.call("apply_state", cryo["schematic"])
	if _tanks != null and _tanks.has_method("apply_state") and cryo.has("tanks"):
		_tanks.call("apply_state", cryo["tanks"])
