extends "res://core_v2/ui/hud/HudWidget.gd"

# FD-324 — widget compacto de Cuerda (player:rope).
# Muestra el estado SIN ANCLAJE / EN RANGO / ENGANCHADA y, si está enganchada,
# la longitud activa. El widget no piensa: pinta la última lectura del armazón.

onready var _status_label: Label = get_node_or_null("Margin/VBox/StatusLabel")
onready var _length_label: Label = get_node_or_null("Margin/VBox/LengthLabel")


func default_title() -> String:
	return tr("Cuerda")


func default_screen_id() -> String:
	return "player:rope"


func _render(snapshot: Dictionary) -> void:
	var attached: bool = bool(snapshot.get("attached", false))
	var anchor_ready: bool = bool(snapshot.get("anchor_ready", false))
	var state: String = String(snapshot.get("state", ""))
	if state.empty():
		state = "ATTACHED" if attached else ("IN_RANGE" if anchor_ready else "NO_ANCHOR")

	if _status_label != null:
		_status_label.text = _state_text(state)
	if _length_label != null:
		if attached:
			_length_label.text = tr("LARGO: %.1f m") % float(snapshot.get("length", 0.0))
		else:
			_length_label.text = tr("LARGO: --")

	if state == "ATTACHED":
		_set_dot(OdiseaOSTheme.STATE_ALARM)
	elif state == "IN_RANGE":
		_set_dot(OdiseaOSTheme.STATE_CAUTION)
	else:
		_set_dot(OdiseaOSTheme.STATE_NOMINAL)


func _state_text(state: String) -> String:
	match state:
		"ATTACHED":
			return tr("ENGANCHADA")
		"IN_RANGE":
			return tr("EN RANGO")
		_:
			return tr("SIN ANCLAJE")


func _render_offline() -> void:
	if _status_label != null:
		_status_label.text = tr("--")
	if _length_label != null:
		_length_label.text = tr("LARGO: --")
