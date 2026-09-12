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

		# Estado del sistema que diagnostica el terminal (Criogenia), si el snapshot lo
		# trae: lecturas de sala en la linea de estado, y el estado del circuito en la
		# de modo. Sin la clave queda el texto generico de arriba (HoloTerminal generico).
		var cryo: Dictionary = snapshot.get("cryo", {}) if typeof(snapshot.get("cryo", {})) == TYPE_DICTIONARY else {}
		if not cryo.empty():
			_apply_cryo_summary(cryo, _status_label, _mode_label)


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
		status_label.text = "TEMP %s  PRES %s  TOX %s" % [temp_str, pres_str, tox_str]

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
