extends "res://core_v2/ui/hud/HudWidget.gd"

# FD-324 F4 — widget compacto de "Navegación del Arca" (ship:ark_nav).
# Muestra el mini corte del cilindro, la barra proa↔popa, la gravedad local en g,
# la lista de destinos con nombre y el aviso de encendido. Es sólo lectura salvo
# los botones de destino, que despachan la acción al SuitOS local o remoto.

onready var _minimap = get_node_or_null("Margin/VBox/Minimap")
onready var _previous_button: Button = get_node_or_null("Margin/VBox/DestinationRow/PrevButton")
onready var _next_button: Button = get_node_or_null("Margin/VBox/DestinationRow/NextButton")
onready var _destination_label: Label = get_node_or_null(
	"Margin/VBox/DestinationRow/DestinationLabel")
onready var _destinations_label: Label = get_node_or_null("Margin/VBox/DestinationsLabel")
onready var _gravity_label: Label = get_node_or_null("Margin/VBox/GravityLabel")
onready var _ignition_label: Label = get_node_or_null("Margin/VBox/IgnitionLabel")


func default_title() -> String:
	return tr("Navegación del Arca")


func default_screen_id() -> String:
	return "ship:ark_nav"


func _on_previous_destination() -> void:
	_perform("cycle_destination", {"step": -1})


func _on_next_destination() -> void:
	_perform("cycle_destination", {"step": 1})


func _render(snapshot: Dictionary) -> void:
	_bind_button(_previous_button, "_on_previous_destination")
	_bind_button(_next_button, "_on_next_destination")
	if _minimap != null and _minimap.has_method("set_nav_snapshot"):
		_minimap.set_nav_snapshot(snapshot)

	var destination: Dictionary = snapshot.get("destination", {})
	var active_id := String(destination.get("id", ""))
	if _destination_label != null:
		var label := String(destination.get("label", "--")).to_upper()
		_destination_label.text = "DESTINO: %s" % label
	if _destinations_label != null:
		var parts := PoolStringArray()
		for entry in snapshot.get("destinations", []):
			var entry_id := String(entry.get("id", ""))
			var entry_label := String(entry.get("label", ""))
			if entry_id == active_id:
				parts.append("[%s]" % entry_label)
			else:
				parts.append(entry_label)
		_destinations_label.text = parts.join(" · ")

	var gravity: Dictionary = snapshot.get("gravity", {})
	if _gravity_label != null:
		# Magnitud |g_eff|/9.8 con flecha de abajo (centrífuga) → popa (encendido).
		var suffix := ""
		if bool(gravity.get("toward_pop", false)):
			suffix = " ↓POPA"
		var arrow: Array = gravity.get("arrow", [0.0, 1.0])
		var glyph := "↓" if abs(float(arrow[0])) < 0.3 else "↘"
		_gravity_label.text = "G: %.2fg %s%s" % [float(gravity.get("g", 0.0)), glyph, suffix]

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
	else:
		_set_dot(OdiseaOSTheme.STATE_NOMINAL)


func _render_offline() -> void:
	if _minimap != null and _minimap.has_method("set_nav_snapshot"):
		_minimap.set_nav_snapshot({})
	if _destination_label != null:
		_destination_label.text = "DESTINO: --"
	if _destinations_label != null:
		_destinations_label.text = "--"
	if _gravity_label != null:
		_gravity_label.text = "G: --"
	if _ignition_label != null:
		_ignition_label.text = "MOTOR: --"

