extends GdUnitTestSuite

# test_suit_screen.gd - Pantalla "Traje" (OdiseaOS): SuitModel + SuitWidget + SuitScreen.
#
# Cubre los contratos:
#   1) SuitModel: estado del traje, objetivos (el primero "Encender las luces") y
#      comunicaciones; snapshot puro serializable, repetible y determinista (sin nodos,
#      sin colores, sin ticks ni rand).
#   2) SuitWidget: pinta estado/objetivo/comunicaciones desde el snapshot y su rama OFFLINE.
#   3) SuitScreen/SuitScreenView: contrato HUDable (id, widget, vista, solo lectura).

const SuitModel = preload("res://core_v2/ui/hud/SuitModel.gd")
const SuitWidgetScene = preload("res://core_v2/ui/hud/SuitWidget.tscn")
const SuitScreenScript = preload("res://core_v2/things/SuitScreen.gd")
const SuitScreenViewScript = preload("res://core_v2/ui/hud/SuitScreenView.gd")
const OdiseaOSTheme = preload("res://core_v2/ui/OdiseaOSTheme.gd")


func before_test() -> void:
	TranslationServer.set_locale("es")


func _new_model():
	return SuitModel.new()


func _new_widget():
	var widget = auto_free(SuitWidgetScene.instance())
	add_child(widget)
	return widget


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


# --- SuitModel ---------------------------------------------------------------------

func test_model_starts_nominal_with_lights_as_the_first_objective() -> void:
	var model = _new_model()
	var snap: Dictionary = model.snapshot()
	assert_str(String(snap["id"])).is_equal("suit:status")
	assert_str(String(snap["title"])).is_equal("Traje")
	assert_str(String(snap["state"]["status"])).is_equal(SuitModel.STATUS_NOMINAL)
	assert_str(String(model.active_objective()["id"])).is_equal("lights")
	assert_str(String(model.active_objective()["text"])).is_equal("Encender las luces")
	assert_int(snap["objectives"].size()).is_equal(1)
	assert_str(String(snap["objectives"][0]["state"])).is_equal(SuitModel.OBJ_ACTIVE)
	# El objetivo activo pide notice; el estado nominal no eleva.
	assert_str(String(snap["urgency"])).is_equal(OdiseaOSTheme.URGENCY_NOTICE)


func test_model_seeds_a_scripted_communication_log() -> void:
	var model = _new_model()
	var snap: Dictionary = model.snapshot()
	assert_int(snap["comms"].size()).is_equal(2)
	assert_int(int(snap["unread_comms"])).is_equal(2)
	assert_str(String(snap["comms"][0]["from"])).is_equal("ODISEA")
	assert_int(int(snap["comms"][1]["seq"])).is_equal(1)
	model.mark_comms_read()
	assert_int(int(model.snapshot()["unread_comms"])).is_equal(0)


func test_snapshot_is_pure_serializable_data_and_repeatable() -> void:
	var model = _new_model()
	model.set_state_field("oxygen", 12)
	model.set_breach(true)
	_assert_pure_data(model.snapshot())
	# Dictionary == en Godot 3 compara identidad: dos lecturas se comparan por hash.
	assert_int(model.snapshot().hash()).is_equal(model.snapshot().hash()) \
		.override_failure_message("dos lecturas del mismo estado deben ser iguales")


func test_snapshot_survives_json_round_trip() -> void:
	var model = _new_model()
	model.add_comms("CARGOL", "Unidad en espera.", "cargol")
	var snap: Dictionary = model.snapshot()
	assert_str(to_json(parse_json(to_json(snap)))).is_equal(to_json(snap))


func test_state_derives_status_and_urgency() -> void:
	var model = _new_model()
	model.set_state_field("oxygen", 20)
	assert_str(model.status()).is_equal(SuitModel.STATUS_CAUTION)
	assert_str(String(model.snapshot()["urgency"])).is_equal(OdiseaOSTheme.URGENCY_URGENT)
	model.set_breach(true)
	assert_str(model.status()).is_equal(SuitModel.STATUS_ALARM)
	assert_str(String(model.snapshot()["urgency"])).is_equal(OdiseaOSTheme.URGENCY_ALARM)


func test_state_rejects_unknown_fields() -> void:
	var model = _new_model()
	assert_bool(model.set_state_field("warp_core", 42)).is_false()
	assert_bool(model.set_state_field("integrity", 80)).is_true()
	assert_int(int(model.get_state_value("integrity"))).is_equal(80)


func test_objectives_only_ever_have_one_active_and_reject_duplicate_ids() -> void:
	var model = _new_model()
	assert_bool(model.add_objective("coolant", "Sellar el circuito")).is_true()
	assert_bool(model.add_objective("coolant", "otra vez")).is_false()
	assert_str(model.objective_state("coolant")).is_equal(SuitModel.OBJ_PENDING)
	# Completar el primero no activa el siguiente: sigue sin haber un ACTIVO nuevo.
	assert_bool(model.complete_objective("lights")).is_true()
	assert_str(model.objective_state("lights")).is_equal(SuitModel.OBJ_DONE)
	assert_bool(model.active_objective().empty()).is_true()
	assert_str(String(model.snapshot()["urgency"])).is_equal(OdiseaOSTheme.URGENCY_QUIET)
	assert_bool(model.complete_objective("inexistente")).is_false()


func test_objective_theme_state_is_the_single_mapping() -> void:
	assert_str(SuitModel.objective_theme_state(SuitModel.OBJ_ACTIVE)).is_equal("active")
	assert_str(SuitModel.objective_theme_state(SuitModel.OBJ_DONE)).is_equal("nominal")
	assert_str(SuitModel.objective_theme_state(SuitModel.OBJ_PENDING)).is_equal("offline")
	assert_str(SuitModel.objective_theme_state("banana")).is_equal("offline")


# --- SuitWidget --------------------------------------------------------------------

func test_widget_paints_state_objective_and_comms_from_the_snapshot() -> void:
	var model = _new_model()
	var widget = _new_widget()
	widget.set_snapshot(model.snapshot())
	var painted: Dictionary = widget.painted()
	assert_str(String(painted["state"])).is_equal("INT 100% O2 100%")
	assert_str(String(painted["objective"])).is_equal("> Encender las luces")
	assert_str(String(painted["comms"])).is_equal("COMMS 2  21C")
	_assert_color_eq(painted["dot"], OdiseaOSTheme.STATE_NOMINAL)


func test_widget_warns_breach_and_alarms_the_header() -> void:
	var model = _new_model()
	model.set_breach(true)
	var widget = _new_widget()
	widget.set_snapshot(model.snapshot())
	var painted: Dictionary = widget.painted()
	assert_str(String(painted["state"])).contains("!FALLA")
	_assert_color_eq(painted["dot"], OdiseaOSTheme.STATE_ALARM)
	assert_str(widget.urgency()).is_equal(OdiseaOSTheme.URGENCY_ALARM)


func test_widget_shows_done_objective_when_none_is_active() -> void:
	var model = _new_model()
	model.complete_objective("lights")
	var widget = _new_widget()
	widget.set_snapshot(model.snapshot())
	assert_str(String(widget.painted()["objective"])).is_equal("[OK] Encender las luces")


func test_widget_offline_shows_no_reading_and_quiets_urgency() -> void:
	var widget = _new_widget()
	widget.set_snapshot({"source": "offline"})
	var painted: Dictionary = widget.painted()
	assert_str(String(painted["state"])).is_equal("SIN LECTURA")
	assert_str(String(painted["objective"])).is_equal("--")
	assert_str(String(painted["comms"])).is_equal("--")
	_assert_color_eq(painted["dot"], OdiseaOSTheme.STATE_OFFLINE)
	assert_str(widget.urgency()).is_equal(OdiseaOSTheme.URGENCY_QUIET)


# --- SuitScreen / SuitScreenView ---------------------------------------------------

func test_screen_declares_the_suit_contract() -> void:
	var screen = auto_free(SuitScreenScript.new())
	assert_str(screen.screen_id()).is_equal("suit:status")
	assert_str(screen.screen_title()).is_equal("Traje")
	assert_bool(screen.widget_scene() == SuitWidgetScene).is_true()
	assert_bool(screen.allowed_actions().empty()).is_true()
	assert_bool(bool(screen.perform_action("complete")["ok"])).is_false()
	assert_bool(screen.view_size() == Vector2(560.0, 480.0)).is_true()
	if ClassDB.class_exists("ImGuiCanvas"):
		assert_bool(screen.view_scene() != null).is_true()
	else:
		assert_bool(screen.view_scene() == null).is_true()


func test_screen_asks_for_a_large_opaque_surface() -> void:
	var screen = auto_free(SuitScreenScript.new())
	var config: Dictionary = screen.view_hud_config()
	# Pantalla de lectura a pantalla casi completa: no el default chico y translucido.
	assert_float(float(config.get("scale", 0.0))).is_greater(0.5)
	assert_float(float(config.get("background_alpha", 0.0))).is_greater(0.15)


func test_screen_serves_the_model_snapshot_or_offline() -> void:
	var screen = auto_free(SuitScreenScript.new())
	var without_model: Dictionary = screen.widget_snapshot()
	assert_str(String(without_model["source"])).is_equal("offline")
	var model = _new_model()
	screen.set_model(model)
	var snap: Dictionary = screen.widget_snapshot()
	assert_str(String(snap["id"])).is_equal("suit:status")
	assert_str(String(snap["title"])).is_equal("Traje")
	assert_str(String(snap["source"])).is_equal("online")
	assert_str(String(snap["active_objective"]["text"])).is_equal("Encender las luces")
	# La pantalla es un espejo del modelo: quien lo conduce marca, aca se lee.
	model.complete_objective("lights")
	assert_str(String(screen.widget_snapshot()["objectives"][0]["state"])).is_equal(SuitModel.OBJ_DONE)


func test_screen_relevance_elevates_on_alarm_and_unread() -> void:
	var screen = auto_free(SuitScreenScript.new())
	var model = _new_model()
	screen.set_model(model)
	var base: float = screen.relevance()
	model.set_breach(true)
	assert_float(screen.relevance()).is_greater(base)


func test_screen_view_stores_the_snapshot_it_receives() -> void:
	var view = auto_free(SuitScreenViewScript.new())
	var model = _new_model()
	model.set_breach(true)
	view.update_snapshot(model.snapshot())
	assert_str(view.screen_id).is_equal("suit:status")
	assert_str(String(view.snapshot["state"]["status"])).is_equal(SuitModel.STATUS_ALARM)
	view.set_snapshot(model.snapshot())
	assert_str(String(view.snapshot["active_objective"]["id"])).is_equal("lights")


# El traje se registra en SuitOS al montarse en el jugador. Se comprueba sobre el .tscn
# (no instanciando el piloto entero y su equipo), mismo criterio que test_cryopods_hudable.
func test_screen_is_mounted_on_the_player() -> void:
	var file := File.new()
	assert_int(file.open("res://core_v2/actors/Pilot_v2.tscn", File.READ)).is_equal(OK)
	var text: String = file.get_as_text()
	file.close()
	assert_str(text).contains("res://core_v2/things/SuitScreen.tscn")
	assert_str(text).contains('[node name="SuitScreen" parent="." instance=ExtResource( 73 )]')
