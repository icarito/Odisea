extends "res://core_v2/ui/hud/HudWidget.gd"

# SuitWidget.gd - Widget de slot del traje de Elias (pantalla "Traje").
#
# Es la cara compacta de SuitScreen/SuitModel: de un vistazo dice como esta el traje,
# cual es el objetivo activo y cuantos mensajes sin leer hay. Todo sale del snapshot
# (Manual §8: sin nodos vivos adentro); la rama OFFLINE la maneja la base HudWidget.
#
# No tiene class_name a proposito (ver HudWidget.gd): registrar una clase global exige
# que el editor reescriba project.godot. El host la instancia por su escena.
#
# Contrato con el host: hereda update_snapshot/set_snapshot -> _render/_render_offline.
# No sobrescribir update_snapshot/set_snapshot.

const SuitModel = preload("res://core_v2/ui/hud/SuitModel.gd")

onready var _state_label: Label = get_node_or_null("Margin/VBox/StateRow/StateLabel")
onready var _objective_label: Label = get_node_or_null("Margin/VBox/ObjRow/ObjLabel")
onready var _comms_label: Label = get_node_or_null("Margin/VBox/CommsRow/CommsLabel")

# Ultima lectura, para quien quiera leerla sin reimplementar la rama OFFLINE (mismo
# patron que FlashlightWidget/ProtocolWidget). set_snapshot() sigue siendo el contrato.
var _last_snapshot := {}


func default_title() -> String:
	return tr("Traje")


func default_screen_id() -> String:
	return SuitModel.SCREEN_ID


func _render(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot
	var state: Dictionary = snapshot.get("state", {})
	var status := String(state.get("status", SuitModel.STATUS_OFFLINE))
	_set_dot(OdiseaOSTheme.state(status))

	if _state_label != null:
		_state_label.text = _format_state(state)
		var state_color := OdiseaOSTheme.STATE_ALARM if status == SuitModel.STATUS_ALARM \
			else (OdiseaOSTheme.STATE_CAUTION if status == SuitModel.STATUS_CAUTION else OdiseaOSTheme.INK)
		_set_font_color(_state_label, state_color)

	if _objective_label != null:
		_objective_label.text = _format_objective(snapshot)
		var objective_color := OdiseaOSTheme.SUIT_DIM
		var active: Dictionary = snapshot.get("active_objective", {})
		if not active.empty():
			objective_color = OdiseaOSTheme.SUIT_ACCENT
		_set_font_color(_objective_label, objective_color)

	if _comms_label != null:
		_comms_label.text = _format_comms(state, snapshot)
		_set_font_color(_comms_label, OdiseaOSTheme.SUIT_DIM)


func _render_offline() -> void:
	_last_snapshot = {"source": "offline"}
	if _state_label != null:
		_state_label.text = tr("SIN LECTURA")
		_set_font_color(_state_label, OdiseaOSTheme.STATE_OFFLINE)
	if _objective_label != null:
		_objective_label.text = "--"
		_set_font_color(_objective_label, OdiseaOSTheme.STATE_OFFLINE)
	if _comms_label != null:
		_comms_label.text = "--"
		_set_font_color(_comms_label, OdiseaOSTheme.STATE_OFFLINE)


# Lo que efectivamente quedo pintado, para tests y debugging (misma verdad que los
# nodos, sin asomar el arbol).
func painted() -> Dictionary:
	var entry := {
		"dot": Color(0, 0, 0),
		"state": "",
		"objective": "",
		"comms": "",
	}
	if _status_dot != null:
		entry["dot"] = _status_dot.color
	if _state_label != null:
		entry["state"] = _state_label.text
	if _objective_label != null:
		entry["objective"] = _objective_label.text
	if _comms_label != null:
		entry["comms"] = _comms_label.text
	return entry


# Lectura cruda, mismo patron que FlashlightWidget.snapshot().
func snapshot() -> Dictionary:
	return _last_snapshot


# --- formato ------------------------------------------------------------------

func _format_state(state: Dictionary) -> String:
	var text := "INT %d%% O2 %d%%" % [
		int(state.get("integrity", 0)),
		int(state.get("oxygen", 0)),
	]
	if bool(state.get("breach", false)):
		text += " !FALLA"
	return text


func _format_objective(snapshot: Dictionary) -> String:
	var active: Dictionary = snapshot.get("active_objective", {})
	if not active.empty():
		return "> %s" % String(active.get("text", ""))
	# Sin activo: si hay alguno hecho, se muestra; si no, la linea queda vacia.
	for obj in snapshot.get("objectives", []):
		if String(obj.get("state", "")) == SuitModel.OBJ_DONE:
			return "[OK] %s" % String(obj.get("text", ""))
	return "OBJ --"


func _format_comms(state: Dictionary, snapshot: Dictionary) -> String:
	return "COMMS %d  %dC" % [int(snapshot.get("unread_comms", 0)), int(state.get("temperature", 0))]
