extends "res://core_v2/ui/hud/HudWidget.gd"
class_name GlooWidget

# GlooWidget.gd - Widget de slot del gloo del multi-tool (FD-296 F2 / FD-298).
# Objeto equipable (no es un modo): el boton equipa/desequipa el gloo.

onready var _status_label: Label = get_node_or_null("Margin/VBox/StatusLabel")
onready var _charge_label: Label = get_node_or_null("Margin/VBox/ChargeLabel")
onready var _equip_button: Button = get_node_or_null("Margin/VBox/StatusRow/EquipButton")

var _equipped := false

func _ready() -> void:
	_bind_button(_equip_button, "_on_equip_pressed")

func default_title() -> String:
	return tr("Gloo")

func default_screen_id() -> String:
	return "player:gloo"

func _render(snapshot: Dictionary) -> void:
	_equipped = bool(snapshot.get("equipped", false))
	var active: int = int(snapshot.get("active", 0))
	var max_count: int = int(snapshot.get("max", 0))
	if _equipped:
		_set_dot(OdiseaOSTheme.STATE_ACTIVE)
	else:
		_set_dot(OdiseaOSTheme.STATE_NOMINAL)
	if _status_label != null:
		_status_label.text = tr("EQUIPADO") if _equipped else tr("LISTO")
	if _charge_label != null:
		_charge_label.text = tr("GLOO: %d / %d") % [active, max_count]
	if _equip_button != null:
		_equip_button.disabled = false
		_equip_button.text = tr("DESEQUIPAR") if _equipped else tr("EQUIPAR")

func _render_offline() -> void:
	_equipped = false
	if _status_label != null:
		_status_label.text = tr("OFFLINE")
	if _charge_label != null:
		_charge_label.text = tr("CARGA: --")
	if _equip_button != null:
		_equip_button.disabled = true
		_equip_button.text = tr("OFFLINE")

func _on_equip_pressed() -> void:
	_perform("equip", {"desired": not _equipped})
