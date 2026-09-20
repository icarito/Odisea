extends "res://core_v2/ui/hud/HudWidget.gd"
class_name SystemStatusWidget

# SystemStatusWidget.gd - Compact HUD widget for Ship System Status (FD-296 F2)

const STATE_OK := 0
const STATE_DEGRADADO := 1
const STATE_FALLO := 2
const STATE_OFFLINE := 3

# Rows for each system
onready var _row_crio_dot: ColorRect = get_node_or_null("Margin/VBox/Rows/CrioRow/Dot")
onready var _row_crio_lbl: Label = get_node_or_null("Margin/VBox/Rows/CrioRow/Label")

onready var _row_plasma_dot: ColorRect = get_node_or_null("Margin/VBox/Rows/PlasmaRow/Dot")
onready var _row_plasma_lbl: Label = get_node_or_null("Margin/VBox/Rows/PlasmaRow/Label")

onready var _row_atmos_dot: ColorRect = get_node_or_null("Margin/VBox/Rows/AtmosRow/Dot")
onready var _row_atmos_lbl: Label = get_node_or_null("Margin/VBox/Rows/AtmosRow/Label")

onready var _row_power_dot: ColorRect = get_node_or_null("Margin/VBox/Rows/PowerRow/Dot")
onready var _row_power_lbl: Label = get_node_or_null("Margin/VBox/Rows/PowerRow/Label")

func default_title() -> String:
	return tr("Domo")

func _render(snapshot: Dictionary) -> void:
	var systems: Dictionary = snapshot.get("systems", {})

	_update_sys_row("criocoolant", "CRIOCOOLANT", _row_crio_dot, _row_crio_lbl, systems)
	_update_sys_row("plasma", "PLASMA", _row_plasma_dot, _row_plasma_lbl, systems)
	_update_sys_row("atmosfera", "ATMÓSFERA", _row_atmos_dot, _row_atmos_lbl, systems)
	_update_sys_row("energia", "ENERGÍA", _row_power_dot, _row_power_lbl, systems)

func _render_offline() -> void:
	_set_row(_row_crio_dot, _row_crio_lbl, "CRIOCOOLANT", STATE_OFFLINE, "OFFLINE")
	_set_row(_row_plasma_dot, _row_plasma_lbl, "PLASMA", STATE_OFFLINE, "OFFLINE")
	_set_row(_row_atmos_dot, _row_atmos_lbl, "ATMÓSFERA", STATE_OFFLINE, "OFFLINE")
	_set_row(_row_power_dot, _row_power_lbl, "ENERGÍA", STATE_OFFLINE, "OFFLINE")

func _update_sys_row(sys_key: String, sys_name: String, dot: ColorRect, lbl: Label, systems: Dictionary) -> void:
	var sys_data: Dictionary = systems.get(sys_key, {})
	var state: int = int(sys_data.get("state", STATE_OFFLINE))
	var detail: String = String(sys_data.get("detail", "sin fuente"))
	_set_row(dot, lbl, sys_name, state, detail)

func _set_row(dot: ColorRect, lbl: Label, sys_name: String, state: int, detail: String) -> void:
	if lbl != null:
		lbl.text = "%s: %s" % [sys_name, detail]
	if dot != null:
		match state:
			STATE_OK:
				dot.color = OdiseaOSTheme.STATE_NOMINAL
			STATE_DEGRADADO:
				dot.color = OdiseaOSTheme.STATE_CAUTION
			STATE_FALLO:
				dot.color = OdiseaOSTheme.STATE_ALARM
			_:
				dot.color = OdiseaOSTheme.STATE_OFFLINE
