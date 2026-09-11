extends PanelContainer
class_name HoloTerminalWidget

# HoloTerminalWidget.gd - Compact HUD widget for HoloTerminal HUDable screens (FD-296 F1.5)

onready var _title_label: Label = $Margin/VBox/Header/TitleLabel
onready var _status_dot: ColorRect = $Margin/VBox/Header/StatusDot
onready var _status_label: Label = $Margin/VBox/StatusLabel
onready var _mode_label: Label = $Margin/VBox/ModeLabel

func update_snapshot(snapshot: Dictionary) -> void:
	set_snapshot(snapshot)

func set_snapshot(snapshot: Dictionary) -> void:
	var title: String = String(snapshot.get("title", "HoloTerminal"))
	var is_active: bool = bool(snapshot.get("active", false))
	var is_focused: bool = bool(snapshot.get("focused", false))
	var status_text: String = String(snapshot.get("status_text", ""))
	var source: String = String(snapshot.get("source", "online"))

	if is_inside_tree():
		if _title_label != null:
			_title_label.text = title

		if _status_dot != null:
			if source == "offline":
				_status_dot.color = Color(0.5, 0.5, 0.5, 0.8)
			elif is_active:
				_status_dot.color = Color(0.1, 0.9, 0.4, 0.9)
			else:
				_status_dot.color = Color(0.9, 0.3, 0.2, 0.8)

		if _status_label != null:
			if source == "offline":
				_status_label.text = "OFFLINE"
			elif status_text != "":
				_status_label.text = status_text
			elif is_active:
				_status_label.text = "ESTADO: OPERATIVO"
			else:
				_status_label.text = "ESTADO: EN ESPERA"

		if _mode_label != null:
			if source == "offline":
				_mode_label.text = "[SIN CONEXION]"
			elif is_focused:
				_mode_label.text = "[EN FOCO]"
			elif is_active:
				_mode_label.text = "[DISPONIBLE]"
			else:
				_mode_label.text = "[INACTIVO]"
