extends PanelContainer
class_name CargolWidget

# CargolWidget.gd - Compact HUD widget for Cargol defensive drone (FD-296 F2)

onready var _title_label: Label = get_node_or_null("Margin/VBox/Header/TitleLabel")
onready var _status_dot: ColorRect = get_node_or_null("Margin/VBox/Header/StatusDot")
onready var _status_label: Label = get_node_or_null("Margin/VBox/StatusLabel")
onready var _notif_label: Label = get_node_or_null("Margin/VBox/NotifLabel")

func update_snapshot(snapshot: Dictionary) -> void:
	set_snapshot(snapshot)

func set_snapshot(snapshot: Dictionary) -> void:
	var title: String = String(snapshot.get("title", "Cargol"))
	var source: String = String(snapshot.get("source", "online"))
	var drone_state: int = int(snapshot.get("drone_state", 0))
	var notification: String = String(snapshot.get("notification", ""))

	if _title_label != null:
		_title_label.text = title

	if source == "offline":
		if _status_dot != null:
			_status_dot.color = Color(0.5, 0.5, 0.5, 0.8)
		if _status_label != null:
			_status_label.text = "ESTADO: OFFLINE"
		if _notif_label != null:
			_notif_label.text = ""
		return

	var state_text := "ESTADO: OK"
	var dot_color := Color(0.2, 0.6, 1.0, 0.9) # Blue

	match drone_state:
		0:
			state_text = "ESTADO: LISTO"
			dot_color = Color(0.2, 0.6, 1.0, 0.9)
		1:
			state_text = "ESTADO: CARGANDO EMP"
			dot_color = Color(1.0, 0.6, 0.0, 0.9)
		2:
			state_text = "ESTADO: DISPARANDO EMP"
			dot_color = Color(1.0, 1.0, 1.0, 0.9)
		3:
			state_text = "ESTADO: RECARGANDO EMP"
			dot_color = Color(0.8, 0.4, 0.0, 0.9)
		4:
			state_text = "ESTADO: SEÑUELO ACTIVO"
			dot_color = Color(0.2, 1.0, 0.2, 0.9)
		5:
			state_text = "ESTADO: CARGOL CAÍDO"
			dot_color = Color(1.0, 0.1, 0.1, 0.9)
		6:
			state_text = "ESTADO: RETORNANDO"
			dot_color = Color(0.2, 1.0, 1.0, 0.9)

	if _status_dot != null:
		_status_dot.color = dot_color

	if _status_label != null:
		_status_label.text = state_text

	if _notif_label != null:
		_notif_label.text = notification
