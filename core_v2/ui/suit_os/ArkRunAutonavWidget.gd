extends "res://core_v2/ui/hud/HudWidget.gd"

# FD-324 F4 — widget compacto del Autonavegador (player:autonav).
# Refleja si el jugador mantiene el modo asistido y cuál es el destino propuesto.
# Mantener el slot (R1 por defecto) o TAB conduce; soltar vuelve a manual en el
# mismo tick. El widget no escribe intents ni estado físico.

onready var _status_label: Label = get_node_or_null("Margin/VBox/StatusLabel")
onready var _destination_label: Label = get_node_or_null("Margin/VBox/DestinationLabel")
onready var _ignition_label: Label = get_node_or_null("Margin/VBox/IgnitionLabel")


func default_title() -> String:
	return tr("Autonavegador")


func default_screen_id() -> String:
	return "player:autonav"


func _render(snapshot: Dictionary) -> void:
	var assist: Dictionary = snapshot.get("assist", {})
	var active := bool(assist.get("active", false))
	if _status_label != null:
		_status_label.text = "ASISTIDO" if active else "MANUAL"

	var destination: Dictionary = snapshot.get("destination", {})
	if _destination_label != null:
		var label := String(destination.get("label", "--")).to_upper()
		_destination_label.text = "DESTINO: %s" % label

	var ignition: Dictionary = snapshot.get("ignition", {})
	var state := String(ignition.get("state", "IDLE"))
	if _ignition_label != null:
		if state == "WARNING":
			_ignition_label.text = "MOTOR: AVISO %.0fs" % float(ignition.get("countdown", 0.0))
		elif state == "ACTIVE":
			_ignition_label.text = "MOTOR: ACTIVO"
		else:
			_ignition_label.text = "MOTOR: IDLE"

	if state == "ACTIVE":
		_set_dot(OdiseaOSTheme.STATE_ALARM)
	elif state == "WARNING":
		_set_dot(OdiseaOSTheme.STATE_CAUTION)
	elif active:
		_set_dot(OdiseaOSTheme.STATE_ACTIVE)
	else:
		_set_dot(OdiseaOSTheme.STATE_NOMINAL)


func _render_offline() -> void:
	if _status_label != null:
		_status_label.text = "OFFLINE"
	if _destination_label != null:
		_destination_label.text = "DESTINO: --"
	if _ignition_label != null:
		_ignition_label.text = "MOTOR: --"
