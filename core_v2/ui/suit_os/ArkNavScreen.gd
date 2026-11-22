extends HUDableComponent

# FD-324 F4 — pantalla diegética "Navegación del Arca" (ship:ark_nav).
#
# Backend puro de presentación: consume SpinFrame para el corte radial, la barra
# proa↔popa y la gravedad efectiva. No escribe estado físico ni usa relojes: el
# host de F4/F6 sólo le pasa posición/omega/a_axial y el estado del encendido.

const WidgetScene = preload("res://core_v2/ui/suit_os/ArkNavWidget.tscn")
const Model = preload("res://core_v2/ui/suit_os/ArkRunNavigationModel.gd")
const SpinFrame = preload("res://core_v2/systems/SpinFrame.gd")

signal ignition_alert(state, countdown)
signal destination_changed(destination)

var position := Vector3.ZERO
var omega := 0.0
var a_axial := 0.0
var hull_radius := Model.DEFAULT_HULL_RADIUS
var slice_length := Model.DEFAULT_SLICE_LENGTH
var ignition_state := "IDLE"
var ignition_countdown := 0.0

var _destination_id := Model.DEFAULT_DESTINATION_ID


func _init() -> void:
	hud_screen_id = "ship:ark_nav"
	hud_screen_title = "Navegación del Arca"
	hud_widget_scene = WidgetScene
	default_relevance = 0.35
	allowed_actions_list = ["cycle_destination", "set_destination"]
	if omega <= 0.0:
		omega = SpinFrame.omega_for()


# Llamado por el host del slice (10 Hz como máximo, no por frame) o por tests.
func update_navigation(position_value: Vector3, omega_value: float = -1.0,
		axial_accel: float = 0.0) -> void:
	var next_omega: float = omega_value if omega_value >= 0.0 else SpinFrame.omega_for()
	var changed: bool = position != position_value \
		or abs(next_omega - omega) > 0.000001 \
		or abs(axial_accel - a_axial) > 0.000001
	position = position_value
	omega = next_omega
	a_axial = axial_accel
	if changed:
		notify_state_changed()


func set_ignition_state(state: String, countdown: float = 0.0) -> void:
	var ignition := Model.ignition_snapshot(state, countdown)
	var new_state := String(ignition["state"])
	var new_countdown := float(ignition["countdown"])
	var state_changed := new_state != ignition_state
	var value_changed := state_changed or abs(new_countdown - ignition_countdown) > 0.001
	ignition_state = new_state
	ignition_countdown = new_countdown
	if state_changed:
		emit_signal("ignition_alert", ignition_state, ignition_countdown)
	if value_changed:
		notify_state_changed()


func set_destination(id: String) -> bool:
	var destination := Model.destination_by_id(id)
	if destination.empty():
		return false
	if String(destination.get("id", "")) == _destination_id:
		return true
	_destination_id = String(destination.get("id", ""))
	emit_signal("destination_changed", Model.destination_snapshot(destination))
	notify_state_changed()
	return true


func cycle_destination(step: int = 1) -> Dictionary:
	var next_id: String = Model.next_destination_id(_destination_id, step)
	set_destination(next_id)
	return Model.destination_by_id(_destination_id)


func get_destination_id() -> String:
	return _destination_id


func get_destination() -> Dictionary:
	return Model.destination_by_id(_destination_id)


func widget_snapshot() -> Dictionary:
	var map := Model.minimap(position, hull_radius, slice_length)
	var gravity := Model.gravity_reading(position, omega, a_axial)
	var destination := get_destination()
	var ignition := Model.ignition_snapshot(ignition_state, ignition_countdown)
	var destination_position: Vector3 = destination.get("position", Vector3.ZERO)
	var destination_map := Model.minimap(destination_position, hull_radius, slice_length)
	return {
		"proto": 1,
		"id": screen_id(),
		"title": screen_title(),
		"source": "online",
		"position": [position.x, position.y, position.z],
		"map": map,
		"destination_map": destination_map,
		"gravity": gravity,
		"destination": Model.destination_snapshot(destination),
		"destinations": Model.destinations_snapshot(),
		"ignition": ignition,
		"urgency": Model.urgency_for_ignition(ignition_state),
	}


func relevance(context: Dictionary = {}) -> float:
	var rel: float = default_relevance
	if ignition_state == "ACTIVE":
		rel = 1.0
	elif ignition_state == "WARNING":
		rel = 0.85
	elif bool(context.get("ark_run", false)):
		rel = 0.7
	return clamp(rel, 0.0, 1.0)


func perform_action(op: String, args: Dictionary = {}) -> Dictionary:
	if op == "cycle_destination":
		var destination := cycle_destination(int(args.get("step", 1)))
		return {"ok": true, "destination": Model.destination_snapshot(destination)}
	if op == "set_destination":
		var id := String(args.get("id", ""))
		if set_destination(id):
			return {"ok": true, "destination": Model.destination_snapshot(get_destination())}
		return {"ok": false, "error": "unknown destination '%s'" % id}
	return {"ok": false, "error": "Action '%s' not supported" % op}
