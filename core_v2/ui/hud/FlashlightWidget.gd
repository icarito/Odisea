extends "res://core_v2/ui/hud/HudWidget.gd"
class_name FlashlightWidget

# FlashlightWidget.gd - Widget de slot de la linterna de casco (FD-298).
#
# Migrado a HudWidget: la base se ocupa del titulo, el punto de estado, la rama OFFLINE
# (Manual §7) y el despacho de la accion. Aca queda solo lo propio de la linterna.

onready var _meter_label: Label = get_node_or_null("Margin/VBox/MeterLabel")
onready var _status_label: Label = get_node_or_null("Margin/VBox/StatusRow/StatusLabel")
onready var _toggle_button: Button = get_node_or_null("Margin/VBox/StatusRow/ToggleButton")

func _ready() -> void:
	_bind_button(_toggle_button, "_on_toggle_pressed")

func default_title() -> String:
	return tr("Linterna")

func default_screen_id() -> String:
	return "player:flashlight"

func _render(snapshot: Dictionary) -> void:
	var on: bool = bool(snapshot.get("on", false))
	var low: bool = bool(snapshot.get("low", false))
	var battery: float = float(snapshot.get("battery", 100.0))
	var battery_max: float = float(snapshot.get("battery_max", 100.0))

	if _toggle_button != null:
		_toggle_button.disabled = false
		_toggle_button.text = tr("APAGAR") if on else tr("ENCENDER")

	if on:
		_set_dot(OdiseaOSTheme.STATE_ALARM if low else OdiseaOSTheme.STATE_ACTIVE)
		if _status_label != null:
			_status_label.text = tr("BAT. BAJA") if low else tr("ENCENDIDA")
	else:
		_set_dot(OdiseaOSTheme.STATE_OFFLINE)
		if _status_label != null:
			_status_label.text = tr("APAGADA")

	if _meter_label != null:
		_meter_label.text = _format_battery_bar(battery, battery_max)
		_set_font_color(_meter_label, OdiseaOSTheme.STATE_ALARM if (low and on) else OdiseaOSTheme.INK)

func _render_offline() -> void:
	if _meter_label != null:
		_meter_label.text = "BAT: [----------]"
	if _status_label != null:
		_status_label.text = tr("OFFLINE")
	if _toggle_button != null:
		_toggle_button.disabled = true
		_toggle_button.text = tr("OFFLINE")

# ASCII: la fuente del tema no trae los bloques (blocks) y la barra salia vacia
# ("BAT: []").
func _format_battery_bar(val: float, max_val: float) -> String:
	if max_val <= 0.0:
		return "BAT: [..........]"
	var ratio := clamp(val / max_val, 0.0, 1.0)
	var total_segments := 10
	var filled_segments := int(round(ratio * total_segments))
	var bar := ""
	for i in range(total_segments):
		if i < filled_segments:
			bar += "|"
		else:
			bar += "."
	return "BAT: [%s]" % bar

func _on_toggle_pressed() -> void:
	_perform("toggle")
