extends PanelContainer
class_name FlashlightWidget

# FlashlightWidget.gd - Compact HUD widget for Helmet Flashlight status (FD-298)

onready var _title_label: Label = get_node_or_null("Margin/VBox/Header/TitleLabel")
onready var _status_dot: ColorRect = get_node_or_null("Margin/VBox/Header/StatusDot")
onready var _meter_label: Label = get_node_or_null("Margin/VBox/MeterLabel")
onready var _status_label: Label = get_node_or_null("Margin/VBox/StatusRow/StatusLabel")
onready var _toggle_button: Button = get_node_or_null("Margin/VBox/StatusRow/ToggleButton")

func _ready() -> void:
	if _toggle_button != null:
		if not _toggle_button.is_connected("pressed", self, "_on_toggle_pressed"):
			_toggle_button.connect("pressed", self, "_on_toggle_pressed")

func update_snapshot(snapshot: Dictionary) -> void:
	set_snapshot(snapshot)

func set_snapshot(snapshot: Dictionary) -> void:
	var title: String = String(snapshot.get("title", "LINTERNA"))
	var source: String = String(snapshot.get("source", "online"))
	var on: bool = bool(snapshot.get("on", false))
	var battery: float = float(snapshot.get("battery", 100.0))
	var battery_max: float = float(snapshot.get("battery_max", 100.0))
	var low: bool = bool(snapshot.get("low", false))

	if _title_label != null:
		_title_label.text = title

	if source == "offline":
		if _status_dot != null:
			_status_dot.color = Color(0.5, 0.5, 0.5, 0.8)
		if _meter_label != null:
			_meter_label.text = "BAT: [----------]"
		if _status_label != null:
			_status_label.text = "ESTADO: OFFLINE"
		if _toggle_button != null:
			_toggle_button.disabled = true
			_toggle_button.text = "OFFLINE"
		return

	if _toggle_button != null:
		_toggle_button.disabled = false
		_toggle_button.text = "APAGAR" if on else "ENCENDER"

	if _status_dot != null:
		if on:
			_status_dot.color = Color(0.9, 0.2, 0.2, 0.9) if low else Color(0.18, 0.88, 0.78, 0.9)
		else:
			_status_dot.color = Color(0.5, 0.5, 0.5, 0.8)

	if _status_label != null:
		if on:
			_status_label.text = "ESTADO: ENCENDIDA" if not low else "ESTADO: BATERÍA BAJA"
		else:
			_status_label.text = "ESTADO: APAGADA"

	if _meter_label != null:
		_meter_label.text = _format_battery_bar(battery, battery_max)
		if low and on:
			_meter_label.add_color_override("font_color", Color(1.0, 0.35, 0.2, 1.0))
		else:
			_meter_label.add_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))

func _format_battery_bar(val: float, max_val: float) -> String:
	if max_val <= 0.0:
		return "BAT: [░░░░░░░░░░]"
	var ratio := clamp(val / max_val, 0.0, 1.0)
	var total_segments := 10
	var filled_segments := int(round(ratio * total_segments))
	var bar := ""
	for i in range(total_segments):
		if i < filled_segments:
			bar += "█"
		else:
			bar += "░"
	return "BAT: [%s]" % bar

func _on_toggle_pressed() -> void:
	if has_node("/root/SuitOS"):
		var suit_os = get_node("/root/SuitOS")
		if suit_os.has_method("perform_action"):
			suit_os.perform_action("player:flashlight", "toggle")
