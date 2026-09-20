extends "res://core_v2/ui/hud/HudWidget.gd"
class_name HoloTerminalWidget

# HoloTerminalWidget.gd - Compact HUD widget for HoloTerminal HUDable screens (FD-296 F1.5)

onready var _status_label: Label = get_node_or_null("Margin/VBox/StatusLabel")
onready var _mode_label: Label = get_node_or_null("Margin/VBox/ActionRow/ModeLabel")
onready var _action_button: Button = get_node_or_null("Margin/VBox/ActionRow/ActionButton")

func _ready() -> void:
	_bind_button(_action_button, "_on_action_pressed")

# Mismo patron que FlashlightWidget: la accion del interactuable se oprime desde el
# widget, sin tener que ir a buscar el objeto en el mundo.
func _on_action_pressed() -> void:
	_perform("toggle_focus")

func default_title() -> String:
	return tr("HoloTerminal")

func _render(snapshot: Dictionary) -> void:
	var is_active: bool = bool(snapshot.get("active", false))
	var is_focused: bool = bool(snapshot.get("focused", false))
	var status_text: String = String(snapshot.get("status_text", ""))
	var can_focus: bool = bool(snapshot.get("can_focus", false))

	if is_inside_tree():
		if _action_button != null:
			_action_button.disabled = not can_focus
			_action_button.text = tr("SALIR") if is_focused else tr("ABRIR")

		_set_dot(OdiseaOSTheme.STATE_NOMINAL if is_active else OdiseaOSTheme.STATE_OFFLINE)

		if _status_label != null:
			if status_text != "":
				_status_label.text = tr(status_text)
			elif is_active:
				_status_label.text = tr("OPERATIVO")
			else:
				_status_label.text = tr("EN ESPERA")

		if _mode_label != null:
			if is_focused:
				_mode_label.text = tr("[EN FOCO]")
			elif is_active:
				_mode_label.text = tr("[DISPONIBLE]")
			else:
				_mode_label.text = tr("[INACTIVO]")

		# Estado del sistema que diagnostica el terminal (Criogenia), si el snapshot lo
		# trae: lecturas de sala en la linea de estado, y el estado del circuito en la
		# de modo. Sin la clave queda el texto generico de arriba (HoloTerminal generico).
		var cryo: Dictionary = snapshot.get("cryo", {}) if typeof(snapshot.get("cryo", {})) == TYPE_DICTIONARY else {}
		if not cryo.empty():
			_apply_cryo_summary(cryo, _status_label, _mode_label)


func _render_offline() -> void:
	if is_inside_tree():
		if _action_button != null:
			_action_button.disabled = true
			_action_button.text = tr("OFFLINE")
		if _status_label != null:
			_status_label.text = tr("OFFLINE")
		if _mode_label != null:
			_mode_label.text = tr("[SIN CONEXION]")


# Lecturas de sala en una linea ("TEMP 20.3°C PRES 1.02atm TOX 0%") y lo mas urgente del
# circuito en la otra (fuga activa > tanque bajo > valvulas cerradas > OK).
func _apply_cryo_summary(cryo: Dictionary, status_label: Label, mode_label: Label) -> void:
	var room: Dictionary = cryo.get("room", {}) if typeof(cryo.get("room", {})) == TYPE_DICTIONARY else {}
	if status_label != null and not room.empty():
		var temp_str := "--°C"
		if room.has("temperature"):
			temp_str = "%.1f°C" % float(room.get("temperature", 0.0))
		var pres_str := "--atm"
		if room.has("pressure"):
			pres_str = "%.2fatm" % float(room.get("pressure"))
		var tox_str := "--%"
		if room.has("contamination"):
			tox_str = "%d%%" % int(round(float(room.get("contamination")) * 100.0))
		status_label.text = tr("TEMP %s  PRES %s  TOX %s") % [temp_str, pres_str, tox_str]

	if mode_label == null:
		return
	var alerts: Array = []
	var schematic: Dictionary = cryo.get("schematic", {}) if typeof(cryo.get("schematic", {})) == TYPE_DICTIONARY else {}
	if not schematic.empty():
		var leaks: int = _count_compromised(schematic)
		if leaks > 0:
			alerts.append("%d FUGA%s" % [leaks, "S" if leaks > 1 else ""])
	var tanks: Dictionary = cryo.get("tanks", {}) if typeof(cryo.get("tanks", {})) == TYPE_DICTIONARY else {}
	var tank_list: Array = tanks.get("tanks", []) if typeof(tanks.get("tanks", [])) == TYPE_ARRAY else []
	for tank in tank_list:
		var level: float = clamp(float(tank.get("level", 1.0)), 0.0, 1.0)
		if level <= 0.5:
			var side := "ESTE" if bool(tank.get("east", false)) else "OESTE"
			alerts.append("TANQUE %s %d%%" % [side, int(round(level * 100.0))])
	if alerts.empty() and not schematic.empty():
		alerts.append("CIRCUITO OK")
	if not alerts.empty():
		mode_label.text = " · ".join(alerts)


func _count_compromised(schematic: Dictionary) -> int:
	var leak_states = preload("res://core_v2/systems/cryo/CoolantLeak.gd").State
	var count := 0
	for key in ["west_states", "east_states", "west_rings", "east_rings"]:
		var states: Array = schematic.get(key, []) if typeof(schematic.get(key, [])) == TYPE_ARRAY else []
		for state in states:
			if int(state) == leak_states.LEAKING or int(state) == leak_states.WARNING:
				count += 1
	return count
