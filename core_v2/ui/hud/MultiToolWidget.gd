extends PanelContainer
class_name MultiToolWidget

# MultiToolWidget.gd - Compact HUD widget for Multi-tool status (FD-296 F2)

onready var _title_label: Label = get_node_or_null("Margin/VBox/Header/TitleLabel")
onready var _status_dot: ColorRect = get_node_or_null("Margin/VBox/Header/StatusDot")
onready var _mode_label: Label = get_node_or_null("Margin/VBox/ModeLabel")
onready var _charge_label: Label = get_node_or_null("Margin/VBox/ChargeLabel")

func update_snapshot(snapshot: Dictionary) -> void:
	set_snapshot(snapshot)

func set_snapshot(snapshot: Dictionary) -> void:
	var title: String = String(snapshot.get("title", "Multi-tool"))
	var source: String = String(snapshot.get("source", "online"))
	var mode: String = String(snapshot.get("mode", "LASER"))
	var charge: Dictionary = snapshot.get("charge", {})

	if _title_label != null:
		_title_label.text = title

	if source == "offline":
		if _status_dot != null:
			_status_dot.color = Color(0.5, 0.5, 0.5, 0.8)
		if _mode_label != null:
			_mode_label.text = "MODO: OFFLINE"
		if _charge_label != null:
			_charge_label.text = "CARGA: --"
		return

	if _status_dot != null:
		_status_dot.color = Color(0.18, 0.88, 0.78, 0.9) if mode == "GLOO" else Color(1.0, 0.3, 0.1, 0.9)

	if _mode_label != null:
		_mode_label.text = "MODO: %s" % mode

	if _charge_label != null:
		var active_gloo: int = int(charge.get("active", 0))
		var max_gloo: int = int(charge.get("max", 18))
		if mode == "GLOO":
			_charge_label.text = "GLOO ACTIVO: %d / %d" % [active_gloo, max_gloo]
		else:
			_charge_label.text = "LASER: LISTO"
