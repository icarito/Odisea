extends GdUnitTestSuite

# test_protocol_widget.gd - FD-319 T4: ProtocolModel + ProtocolWidget + ProtocolScreen.
#
# Cubre los contratos de la tarea:
#   1) ProtocolModel: 6 pasos, UN solo ACTIVO a la vez, FALLO transitorio (el 4 sin el 3),
#      snapshot puro serializable (sin nodos, sin colores, sin ticks ni rand).
#   2) ProtocolWidget: pinta el checklist desde el snapshot; los 4 estados mapeados a
#      OdiseaOSTheme (OFFLINE/ACTIVE/ALARM/NOMINAL); el verbo siempre como instruccion;
#      HECHO se oscurece con su tick.
#   3) ProtocolScreen: mismo dato, contrato HUDable (id, widget, vista, solo lectura).

const ProtocolModel = preload("res://core_v2/ui/hud/ProtocolModel.gd")
const ProtocolWidgetScene = preload("res://core_v2/ui/hud/ProtocolWidget.tscn")
const ProtocolScreenScript = preload("res://core_v2/ui/hud/ProtocolScreen.gd")
const ProtocolScreenViewScript = preload("res://core_v2/ui/hud/ProtocolScreenView.gd")
const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")

const VERBS := [
	"Restablecer respaldo de emergencia",
	"Ejecutar secuencia de arranque",
	"Sellar fuga del circuito de refrigeración",
	"Reacoplar el reactor",
	"Igualar presión del sector",
	"Abrir esclusa inferior del domo",
]


func _new_model():
	return ProtocolModel.new()


func _new_widget():
	var widget = auto_free(ProtocolWidgetScene.instance())
	add_child(widget)
	return widget


func _count_state(steps: Array, state: String) -> int:
	var count := 0
	for step in steps:
		if String(step.get("state", "")) == state:
			count += 1
	return count


func _assert_color_eq(got: Color, want: Color) -> void:
	assert_bool(got == want).override_failure_message("%s != %s" % [got, want]).is_true()


func _assert_pure_data(value) -> void:
	var kind := typeof(value)
	if kind == TYPE_DICTIONARY:
		for key in value.keys():
			assert_bool(typeof(key) == TYPE_STRING) \
				.override_failure_message("clave no serializable").is_true()
			_assert_pure_data(value[key])
	elif kind == TYPE_ARRAY:
		for entry in value:
			_assert_pure_data(entry)
	else:
		assert_bool(kind == TYPE_STRING or kind == TYPE_BOOL or kind == TYPE_INT) \
			.override_failure_message("valor no serializable: %s" % str(value)).is_true()


# --- ProtocolModel -----------------------------------------------------------------

func test_model_starts_with_six_steps_and_only_the_first_active() -> void:
	var model = _new_model()
	var snap: Dictionary = model.snapshot()
	assert_int(snap["steps"].size()).is_equal(6)
	assert_str(model.active_id()).is_equal("aux_power")
	assert_int(_count_state(snap["steps"], ProtocolModel.STATE_PENDING)).is_equal(5)
	assert_int(_count_state(snap["steps"], ProtocolModel.STATE_ACTIVE)).is_equal(1)
	assert_bool(snap["done"]).is_false()
	# ACTIVO pide notice (FD-319: el checklist es la agenda, no una alarma).
	assert_str(String(snap["urgency"])).is_equal(OdiseaOSTheme.URGENCY_NOTICE)


func test_snapshot_is_pure_serializable_data_and_repeatable() -> void:
	var model = _new_model()
	model.fail("main_power")
	_assert_pure_data(model.snapshot())
	# Dictionary == en Godot 3 compara identidad: dos lecturas se comparan por hash.
	assert_int(model.snapshot().hash()).is_equal(model.snapshot().hash()) \
		.override_failure_message("dos lecturas del mismo estado deben ser iguales")


func test_advance_walks_one_active_at_a_time_until_done() -> void:
	var model = _new_model()
	var ids := ["aux_power", "boot_sequence", "coolant", "main_power", "atmosphere", "hangar_access"]
	for i in range(ids.size()):
		assert_str(model.active_id()).is_equal(ids[i])
		var steps: Array = model.snapshot()["steps"]
		assert_int(_count_state(steps, ProtocolModel.STATE_ACTIVE)).is_equal(1) \
			.override_failure_message("siempre UN solo ACTIVO")
		assert_bool(model.advance()).is_true()
		assert_str(model.step_state(ids[i])).is_equal(ProtocolModel.STATE_DONE)
	assert_bool(model.is_done()).is_true()
	assert_str(model.active_id()).is_equal("")
	assert_bool(model.advance()).is_false()
	assert_int(_count_state(model.snapshot()["steps"], ProtocolModel.STATE_DONE)).is_equal(6)
	assert_bool(model.snapshot()["done"]).is_true()


func test_complete_only_accepts_the_active_step() -> void:
	var model = _new_model()
	assert_bool(model.complete("coolant")).is_false()
	assert_str(model.step_state("coolant")).is_equal(ProtocolModel.STATE_PENDING)
	assert_bool(model.complete("aux_power")).is_true()
	assert_str(model.step_state("aux_power")).is_equal(ProtocolModel.STATE_DONE)
	assert_str(model.active_id()).is_equal("boot_sequence")


func test_fail_out_of_order_is_transient_and_keeps_the_active_step() -> void:
	# FD-319 verificacion 3: intentar el 4 sin el 3 marca FALLO transitorio, sin mover
	# el foco del checklist.
	var model = _new_model()
	model.advance()
	model.advance()
	assert_str(model.active_id()).is_equal("coolant")
	assert_bool(model.fail("main_power")).is_true()
	assert_str(model.step_state("main_power")).is_equal(ProtocolModel.STATE_FAIL)
	assert_str(model.active_id()).is_equal("coolant")
	var snap: Dictionary = model.snapshot()
	assert_str(String(snap["urgency"])).is_equal(OdiseaOSTheme.URGENCY_URGENT)
	assert_bool(model.clear_fail("main_power")).is_true()
	assert_str(model.step_state("main_power")).is_equal(ProtocolModel.STATE_PENDING)


func test_fail_on_active_step_returns_to_active_after_clear() -> void:
	var model = _new_model()
	assert_bool(model.fail("aux_power")).is_true()
	assert_str(model.step_state("aux_power")).is_equal(ProtocolModel.STATE_FAIL)
	assert_str(model.active_id()).is_equal("aux_power")
	assert_bool(model.clear_fail("aux_power")).is_true()
	assert_str(model.step_state("aux_power")).is_equal(ProtocolModel.STATE_ACTIVE)


func test_advance_clears_stale_fallos() -> void:
	var model = _new_model()
	model.fail("main_power")
	model.advance()
	assert_str(model.step_state("main_power")).is_equal(ProtocolModel.STATE_PENDING)
	assert_str(model.active_id()).is_equal("boot_sequence")


func test_fail_rejects_a_done_step_and_unknown_ids() -> void:
	var model = _new_model()
	model.advance()
	assert_bool(model.fail("aux_power")).is_false()
	assert_bool(model.fail("paso_inexistente")).is_false()
	assert_bool(model.clear_fail("aux_power")).is_false()


func test_step_urgency_can_rise_but_not_below_its_state_floor() -> void:
	var model = _new_model()
	model.set_urgency("coolant", "alarm")
	var snap: Dictionary = model.snapshot()
	assert_str(String(snap["steps"][2]["urgency"])).is_equal(OdiseaOSTheme.URGENCY_ALARM)
	model.fail("coolant")
	model.set_urgency("coolant", "quiet") # el FALLO nunca baja de urgent
	assert_str(String(model.snapshot()["steps"][2]["urgency"])).is_equal(OdiseaOSTheme.URGENCY_URGENT)


func test_step_carry_system_verb_and_accent_in_order() -> void:
	var steps: Array = _new_model().snapshot()["steps"]
	for i in range(steps.size()):
		assert_str(String(steps[i]["verb"])).is_equal(VERBS[i])
	assert_str(String(steps[0]["accent"])).is_equal("ship")
	assert_str(String(steps[2]["accent"])).is_equal("suit")
	assert_str(String(steps[3]["accent"])).is_equal("alt")
	assert_str(String(steps[4]["accent"])).is_equal("ink")


# --- ProtocolWidget ----------------------------------------------------------------

func test_widget_paints_the_checklist_from_the_model_snapshot() -> void:
	var model = _new_model()
	var widget = _new_widget()
	widget.set_snapshot(model.snapshot())
	var rows: Array = widget.painted_rows()
	assert_int(rows.size()).is_equal(6)
	for i in range(6):
		assert_bool(rows[i]["visible"]).is_true()
		assert_str(String(rows[i]["text"])).is_equal(VERBS[i])
	# PENDIENTE en gris apagado (STATE_OFFLINE); el ACTIVO lleva el punto de estado
	# activo y el texto en el color del sistema (identidad, eje 1).
	_assert_color_eq(rows[0]["dot"], OdiseaOSTheme.STATE_ACTIVE)
	_assert_color_eq(rows[0]["color"], OdiseaOSTheme.SHIP_ACCENT)
	# El paso 2 pendiente no declara sistema y esta apagado: gris de OFFLINE.
	_assert_color_eq(rows[1]["dot"], OdiseaOSTheme.STATE_OFFLINE)
	_assert_color_eq(rows[1]["color"], OdiseaOSTheme.STATE_OFFLINE)


func test_widget_paints_single_active_transition_and_dimmed_done() -> void:
	var model = _new_model()
	var widget = _new_widget()
	widget.set_snapshot(model.snapshot())
	model.advance()
	widget.set_snapshot(model.snapshot())
	var rows: Array = widget.painted_rows()
	assert_str(String(rows[0]["text"])).is_equal("[OK] %s" % VERBS[0])
	_assert_color_eq(rows[0]["dot"], OdiseaOSTheme.STATE_NOMINAL)
	# "HECHO ... se oscurece" (FD-319): el modulate de la fila baja.
	var done_label: Label = widget.get_node("Margin/VBox/StepRow0/StepLabel0")
	assert_float(done_label.modulate.a).is_less(1.0)
	assert_str(String(rows[1]["text"])).is_equal(VERBS[1])
	_assert_color_eq(rows[1]["dot"], OdiseaOSTheme.STATE_ACTIVE)
	_assert_color_eq(rows[1]["color"], OdiseaOSTheme.SUIT_DIM)
	# El paso 3 activo es cian (Criocoolant), el color del sistema, no del estado.
	model.advance()
	widget.set_snapshot(model.snapshot())
	rows = widget.painted_rows()
	_assert_color_eq(rows[2]["color"], OdiseaOSTheme.SUIT_ACCENT)
	_assert_color_eq(rows[2]["dot"], OdiseaOSTheme.STATE_ACTIVE)


func test_widget_paints_transient_fallo_and_alarms_the_header() -> void:
	var model = _new_model()
	model.advance()
	model.advance()
	model.fail("main_power")
	var widget = _new_widget()
	widget.set_snapshot(model.snapshot())
	var rows: Array = widget.painted_rows()
	_assert_color_eq(rows[3]["dot"], OdiseaOSTheme.STATE_ALARM)
	_assert_color_eq(rows[3]["color"], OdiseaOSTheme.STATE_ALARM)
	# El verbo NO se cambia por telemetria (regla dura 2): sigue la instruccion.
	assert_str(String(rows[3]["text"])).is_equal(VERBS[3])
	var header_dot: ColorRect = widget.get_node("Margin/VBox/Header/StatusDot")
	_assert_color_eq(header_dot.color, OdiseaOSTheme.STATE_ALARM)
	# La urgencia agregada que llega del snapshot es la que la base pinta.
	assert_str(widget.urgency()).is_equal(OdiseaOSTheme.URGENCY_URGENT)
	# Y al pasar el rato del FALLO (T5), todo vuelve.
	model.clear_fail("main_power")
	widget.set_snapshot(model.snapshot())
	rows = widget.painted_rows()
	_assert_color_eq(rows[3]["dot"], OdiseaOSTheme.STATE_OFFLINE)


func test_widget_hides_rows_when_the_reading_has_no_steps() -> void:
	var widget = _new_widget()
	widget.set_snapshot({})
	var rows: Array = widget.painted_rows()
	for row in rows:
		assert_bool(row["visible"]).is_false()
	assert_str(widget.get_node("Margin/VBox/Header/TitleLabel").text).is_equal("Protocolo de arranque")


func test_widget_offline_shows_no_steps_and_quiets_urgency() -> void:
	var model = _new_model()
	var widget = _new_widget()
	widget.set_snapshot(model.snapshot())
	var offline: Dictionary = {"source": "offline", "steps": model.snapshot()["steps"]}
	widget.set_snapshot(offline)
	var rows: Array = widget.painted_rows()
	for row in rows:
		assert_bool(row["visible"]).is_false()
		assert_str(String(row["text"])).is_equal("--")
	assert_str(widget.urgency()).is_equal(OdiseaOSTheme.URGENCY_QUIET)


func test_widget_reads_unknown_states_as_offline() -> void:
	var widget = _new_widget()
	widget.set_snapshot({"steps": [{"id": "x", "verb": "hacer algo", "state": "banana", "urgency": "quiet"}]})
	var rows: Array = widget.painted_rows()
	_assert_color_eq(rows[0]["dot"], OdiseaOSTheme.STATE_OFFLINE)


# --- ProtocolScreen ----------------------------------------------------------------

func test_screen_declares_the_suit_protocol_contract() -> void:
	var screen = auto_free(ProtocolScreenScript.new())
	assert_str(screen.screen_id()).is_equal("suit:protocol")
	assert_str(screen.screen_title()).is_equal("Protocolo de arranque")
	assert_bool(screen.widget_scene() == ProtocolWidgetScene).is_true()
	assert_bool(screen.allowed_actions().empty()).is_true()
	assert_bool(bool(screen.perform_action("advance")["ok"])).is_false()
	assert_bool(screen.view_size() == Vector2(520.0, 420.0)).is_true()
	if ClassDB.class_exists("ImGuiCanvas"):
		assert_bool(screen.view_scene() != null).is_true()
	else:
		assert_bool(screen.view_scene() == null).is_true()


func test_screen_serves_the_model_snapshot_or_offline() -> void:
	var screen = auto_free(ProtocolScreenScript.new())
	var without_model: Dictionary = screen.widget_snapshot()
	assert_str(String(without_model["source"])).is_equal("offline")
	var model = _new_model()
	screen.set_model(model)
	var snap: Dictionary = screen.widget_snapshot()
	assert_str(String(snap["id"])).is_equal("suit:protocol")
	assert_str(String(snap["title"])).is_equal("Protocolo de arranque")
	assert_str(String(snap["source"])).is_equal("online")
	assert_int(snap["steps"].size()).is_equal(6)
	# La pantalla es un espejo del modelo, no un canal propio: T5 marca, aca se lee.
	model.advance()
	assert_str(model.step_state("aux_power")).is_equal(ProtocolModel.STATE_DONE)
	assert_str(String(screen.widget_snapshot()["steps"][0]["state"])).is_equal(ProtocolModel.STATE_DONE)


func test_screen_view_stores_the_snapshot_it_receives() -> void:
	var view = auto_free(ProtocolScreenViewScript.new())
	var model = _new_model()
	view.update_snapshot(model.snapshot())
	assert_str(String(view.snapshot["urgency"])).is_equal(OdiseaOSTheme.URGENCY_NOTICE)
	assert_str(view.screen_id).is_equal("suit:protocol")
	model.advance()
	view.set_snapshot(model.snapshot())
	assert_str(String(view.snapshot["steps"][0]["state"])).is_equal(ProtocolModel.STATE_DONE)
