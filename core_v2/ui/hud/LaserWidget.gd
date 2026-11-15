extends "res://core_v2/ui/hud/HudWidget.gd"
class_name LaserWidget

# LaserWidget.gd - Widget de slot del laser del multi-tool (FD-296 F2 / FD-298).
# El laser es un objeto equipable: el boton del widget equipa/desequipa (la misma
# accion que el tap de hombro sobre el slot).

onready var _status_label: Label = get_node_or_null("Margin/VBox/StatusLabel")
onready var _equip_button: Button = get_node_or_null("Margin/VBox/StatusRow/EquipButton")

var _equipped := false

func _ready() -> void:
	_bind_button(_equip_button, "_on_equip_pressed")

func default_title() -> String:
	return tr("Láser")

func default_screen_id() -> String:
	return "player:laser"

func _render(snapshot: Dictionary) -> void:
	_equipped = bool(snapshot.get("equipped", false))
	if _equipped:
		_set_dot(OdiseaOSTheme.STATE_ACTIVE)
	else:
		_set_dot(OdiseaOSTheme.STATE_NOMINAL)
	if _status_label != null:
		_status_label.text = tr("EQUIPADO") if _equipped else tr("LISTO")
	if _equip_button != null:
		_equip_button.disabled = false
		_equip_button.text = tr("DESEQUIPAR") if _equipped else tr("EQUIPAR")

func _render_offline() -> void:
	_equipped = false
	if _status_label != null:
		_status_label.text = tr("OFFLINE")
	if _equip_button != null:
		_equip_button.disabled = true
		_equip_button.text = tr("OFFLINE")

func _on_equip_pressed() -> void:
	_perform("equip", {"desired": not _equipped})
