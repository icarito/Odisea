extends "res://core_v2/ui/hud/HudWidget.gd"

# ProtocolWidget.gd - Checklist del protocolo de arranque (FD-319 T4, Q-2: slot fijo
# del HUD mientras dure el protocolo; quien lo monta y lo reabsorbe es el host/T5).
#
# Es la agenda de Elias (a diferencia del SystemStatusWidget, que es diagnostico
# pasivo): 6 pasos, UN solo ACTIVO a la vez, y el verbo siempre visible como
# instruccion (FD-319 regla dura 2: dice "sellar fuga...", nunca "criocoolant: fallo").
#
# Todo lo dibujado sale del snapshot (Manual §8, sin nodos vivos adentro): la lista
# "steps" que produce ProtocolModel.snapshot(). Los colores no viajan en la lectura:
#   - el punto de cada fila = estado del paso, via OdiseaOSTheme.state() con el mapeo
#     unico ProtocolModel.theme_state_of() (pendiente->OFFLINE, activo->ACTIVE,
#     fallo->ALARM, hecho->NOMINAL);
#   - el texto del paso ACTIVO toma el color de identidad del sistema (token "accent",
#     ProtocolModel.identity_color()); PENDIENTE queda gris, FALLO en alarma y HECHO
#     se oscurece con su tick "[OK]".
# El pulso de urgencia vive en el punto de cabecera y lo maneja la base HudWidget con
# la "urgency" agregada del snapshot: presentacion, no estado; sin _process propio.

const ProtocolModel = preload("res://core_v2/ui/hud/ProtocolModel.gd")

const DONE_DIM := 0.55 # "HECHO ... se oscurece" (FD-319): modulate de la fila hecha

onready var _rows: Array = [
	get_node_or_null("Margin/VBox/StepRow0"),
	get_node_or_null("Margin/VBox/StepRow1"),
	get_node_or_null("Margin/VBox/StepRow2"),
	get_node_or_null("Margin/VBox/StepRow3"),
	get_node_or_null("Margin/VBox/StepRow4"),
	get_node_or_null("Margin/VBox/StepRow5"),
]
onready var _dots: Array = [
	get_node_or_null("Margin/VBox/StepRow0/StepDot0"),
	get_node_or_null("Margin/VBox/StepRow1/StepDot1"),
	get_node_or_null("Margin/VBox/StepRow2/StepDot2"),
	get_node_or_null("Margin/VBox/StepRow3/StepDot3"),
	get_node_or_null("Margin/VBox/StepRow4/StepDot4"),
	get_node_or_null("Margin/VBox/StepRow5/StepDot5"),
]
onready var _labels: Array = [
	get_node_or_null("Margin/VBox/StepRow0/StepLabel0"),
	get_node_or_null("Margin/VBox/StepRow1/StepLabel1"),
	get_node_or_null("Margin/VBox/StepRow2/StepLabel2"),
	get_node_or_null("Margin/VBox/StepRow3/StepLabel3"),
	get_node_or_null("Margin/VBox/StepRow4/StepLabel4"),
	get_node_or_null("Margin/VBox/StepRow5/StepLabel5"),
]

# Ultima lectura, mismo patron que FlashlightWidget: queda escrita por
# _render()/_render_offline() para quien la quiera leer sin reimplementar la rama
# OFFLINE (ProtocolModel.snapshot() sigue siendo la fuente y set_snapshot() el contrato).
var _last_snapshot := {}


func default_title() -> String:
	return tr("Protocolo de arranque")


func default_screen_id() -> String:
	return ProtocolModel.SCREEN_ID


func _render(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot
	var steps: Array = snapshot.get("steps", [])
	var has_fail := false
	for i in range(_rows.size()):
		if i >= steps.size():
			if _rows[i] != null:
				_rows[i].visible = false
			continue
		var step: Dictionary = steps[i]
		var state := String(step.get("state", ProtocolModel.STATE_PENDING))
		var verb := String(step.get("verb", ""))
		var is_done := state == ProtocolModel.STATE_DONE
		has_fail = has_fail or state == ProtocolModel.STATE_FAIL

		if _dots[i] != null:
			_dots[i].color = OdiseaOSTheme.state(ProtocolModel.theme_state_of(state))
			_dots[i].modulate.a = DONE_DIM if is_done else 1.0
		if _labels[i] != null:
			# El verbo es la instruccion y esta siempre presente; el tick [OK] es ASCII
			# a proposito (la fuente del tema no trae glifos de check, ver FlashlightWidget).
			_labels[i].text = ("[OK] %s" % verb) if is_done else verb
			_set_font_color(_labels[i], _text_color(step, state))
			_labels[i].modulate.a = DONE_DIM if is_done else 1.0

	# El punto de cabecera resume el checklist: en fallo, alarma; avanzando, activo.
	if has_fail:
		_set_dot(OdiseaOSTheme.STATE_ALARM)
	elif _all_done(steps):
		_set_dot(OdiseaOSTheme.STATE_NOMINAL)
	else:
		_set_dot(OdiseaOSTheme.STATE_ACTIVE)


func _render_offline() -> void:
	# Sin lectura (Manual §7): la agenda no inventa pasos ni estados; se va a "--" y el
	# punto de cabecera ya quedo gris en set_snapshot().
	_last_snapshot = {"source": "offline"}
	for i in range(_rows.size()):
		if _rows[i] != null:
			_rows[i].visible = false
		if _labels[i] != null:
			_labels[i].text = "--"
			_set_font_color(_labels[i], OdiseaOSTheme.STATE_OFFLINE)


# Lo que efectivamente quedo pintado, para tests y debugging (misma verdad que los
# nodos, sin asomar el arbol). Una entrada por fila: dot/texto/color de texto/visible.
func painted_rows() -> Array:
	var rows: Array = []
	for i in range(_rows.size()):
		var row: Control = _rows[i]
		var entry := {"visible": false, "dot": Color(0, 0, 0), "text": "", "color": Color(0, 0, 0)}
		if row != null:
			entry.visible = row.visible
		if _dots[i] != null:
			entry.dot = _dots[i].color
		if _labels[i] != null:
			entry.text = _labels[i].text
			entry.color = _labels[i].get_color("font_color")
		rows.append(entry)
	return rows


# Lectura cruda para la cara ImGui del widget si algun dia la necesita (patron
# FlashlightWidget.snapshot()): el canvas lee esto, no los Controls.
func snapshot() -> Dictionary:
	return _last_snapshot


func _text_color(step: Dictionary, state: String) -> Color:
	# ACTIVO: el color del sistema es identidad (FD-319 eje 1) y nunca cambia por
	# estado ni por urgencia. El resto de los estados usan el color de su estado.
	if state == ProtocolModel.STATE_ACTIVE:
		return ProtocolModel.identity_color(String(step.get("accent", "")))
	return OdiseaOSTheme.state(ProtocolModel.theme_state_of(state))


func _all_done(steps: Array) -> bool:
	if steps.empty():
		return false
	for step in steps:
		if String(step.get("state", "")) != ProtocolModel.STATE_DONE:
			return false
	return true
