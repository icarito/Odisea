extends "res://core_v2/ui/hud/HudWidget.gd"
class_name MultiToolWidget

# MultiToolWidget.gd - Compact HUD widget for Multi-tool status (FD-296 F2)

onready var _mode_label: Label = get_node_or_null("Margin/VBox/ModeLabel")
onready var _charge_label: Label = get_node_or_null("Margin/VBox/ChargeLabel")

func default_title() -> String:
	return tr("Multi-tool")

func _render(snapshot: Dictionary) -> void:
	var mode: String = String(snapshot.get("mode", "LASER"))
	var charge: Dictionary = snapshot.get("charge", {})

	_set_dot(OdiseaOSTheme.STATE_ACTIVE if mode == "GLOO" else OdiseaOSTheme.STATE_NOMINAL)

	if _mode_label != null:
		_mode_label.text = tr("MODO: %s") % mode

	if _charge_label != null:
		var active_gloo: int = int(charge.get("active", 0))
		var max_gloo: int = int(charge.get("max", 18))
		if mode == "GLOO":
			_charge_label.text = tr("GLOO ACTIVO: %d / %d") % [active_gloo, max_gloo]
		else:
			_charge_label.text = tr("LASER: LISTO")

func _render_offline() -> void:
	if _mode_label != null:
		_mode_label.text = tr("MODO: OFFLINE")
	if _charge_label != null:
		_charge_label.text = tr("CARGA: --")
