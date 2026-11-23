extends "res://core_v2/ui/hud/HudWidget.gd"

# FD-324 — widget compacto de Propulsores (player:thrusters).
# Muestra la barra/porcentaje de Δv disponible y el estado ACTIVO/LISTO/VACÍO.
# El widget no piensa: pinta la última lectura del armazón y nada más.

onready var _delta_label: Label = get_node_or_null("Margin/VBox/DeltaLabel")
onready var _delta_bar: ProgressBar = get_node_or_null("Margin/VBox/DeltaBar")
onready var _status_label: Label = get_node_or_null("Margin/VBox/StatusLabel")


func default_title() -> String:
	return tr("Propulsores")


func default_screen_id() -> String:
	return "player:thrusters"


func _render(snapshot: Dictionary) -> void:
	var ratio: float = clamp(float(snapshot.get("dv_ratio", 0.0)), 0.0, 1.0)
	var active: bool = bool(snapshot.get("active", false))
	var state: String = String(snapshot.get("state", ""))
	if state.empty():
		state = "ACTIVE" if active else ("READY" if ratio > 0.0 else "EMPTY")

	if _delta_label != null:
		_delta_label.text = "Δv %d%%" % int(round(ratio * 100.0))
	if _delta_bar != null:
		_delta_bar.value = ratio * 100.0
	if _status_label != null:
		_status_label.text = _state_text(state)

	if state == "EMPTY":
		_set_dot(OdiseaOSTheme.STATE_ALARM)
	elif state == "ACTIVE":
		_set_dot(OdiseaOSTheme.STATE_ACTIVE)
	else:
		_set_dot(OdiseaOSTheme.STATE_NOMINAL)


func _state_text(state: String) -> String:
	match state:
		"ACTIVE":
			return tr("ACTIVO")
		"EMPTY":
			return tr("VACÍO")
		_:
			return tr("LISTO")


func _render_offline() -> void:
	if _delta_label != null:
		_delta_label.text = tr("Δv --")
	if _delta_bar != null:
		_delta_bar.value = 0.0
	if _status_label != null:
		_status_label.text = tr("--")
