extends "res://core_v2/ui/hud/HudWidget.gd"
class_name CargolWidget

# CargolWidget.gd - Compact HUD widget for Cargol defensive drone (FD-296 F2)

onready var _status_label: Label = get_node_or_null("Margin/VBox/StatusLabel")
onready var _notif_label: Label = get_node_or_null("Margin/VBox/NotifLabel")

func default_title() -> String:
	return tr("Cargol")

func _render(snapshot: Dictionary) -> void:
	var drone_state: int = int(snapshot.get("drone_state", 0))
	var notification: String = String(snapshot.get("notification", ""))

	var state_text := tr("OK")
	var dot_color: Color = OdiseaOSTheme.STATE_NOMINAL

	match drone_state:
		0:
			state_text = tr("LISTO")
			dot_color = OdiseaOSTheme.STATE_NOMINAL
		1:
			state_text = tr("CARGANDO EMP")
			dot_color = OdiseaOSTheme.STATE_CAUTION
		2:
			state_text = tr("DISPARANDO EMP")
			dot_color = OdiseaOSTheme.STATE_ACTIVE
		3:
			state_text = tr("RECARGANDO EMP")
			dot_color = OdiseaOSTheme.STATE_CAUTION
		4:
			state_text = tr("SEÑUELO ACTIVO")
			dot_color = OdiseaOSTheme.STATE_ACTIVE
		5:
			state_text = tr("CARGOL CAÍDO")
			dot_color = OdiseaOSTheme.STATE_ALARM
		6:
			state_text = tr("RETORNANDO")
			dot_color = OdiseaOSTheme.STATE_NOMINAL

	_set_dot(dot_color)

	if _status_label != null:
		_status_label.text = state_text

	if _notif_label != null:
		_notif_label.text = notification

func _render_offline() -> void:
	if _status_label != null:
		_status_label.text = tr("OFFLINE")
	if _notif_label != null:
		_notif_label.text = ""
