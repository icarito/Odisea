extends "res://addons/gdUnit3/src/GdUnitTestSuite.gd"

# FD-292. La pantalla se muestra al pulsar Nueva Partida la primera vez, no al abrir
# el menu, y los botones de aceptar/rechazar recien aparecen cuando la barra llega al
# final. Eso ultimo es lo que se cuida aca: si la eleccion pudiera hacerse antes, la
# pantalla dejaria de ser el rato de lectura que justifica su existencia.

func _make_screen():
	var packed = load("res://core_v2/ui/FirstRunConsent.tscn")
	assert_bool(packed != null).is_true()
	var screen = packed.instance()
	add_child(screen)
	return screen

func test_settings_manager_expone_el_gate():
	assert_bool(SettingsManager != null).is_true()
	assert_bool(SettingsManager.has_method("needs_privacy_consent")).is_true()

func test_los_botones_estan_ocultos_hasta_el_100():
	var screen = _make_screen()
	assert_bool(screen._choice_box.visible).is_false()
	screen._on_ok_pressed()
	assert_bool(screen._telemetry_panel.visible).is_true()
	# Con la carga a medias no debe poder elegirse todavia.
	screen._on_transition_progress(screen.target_scene_path, 0.4)
	screen._refresh_progress()
	assert_bool(screen._choice_box.visible).is_false()
	screen._on_transition_completed(screen.target_scene_path, null, {})
	screen._refresh_progress()
	assert_bool(screen._choice_box.visible).is_true()

func test_aceptar_prende_la_telemetria():
	var screen = _make_screen()
	screen._on_choice(true)
	assert_bool(SettingsManager.telemetry_enabled).is_true()
	assert_bool(SettingsManager.error_reports_enabled).is_true()
	assert_bool(SettingsManager.consent_asked).is_true()
	assert_bool(SettingsManager.needs_privacy_consent()).is_false()

func test_rechazar_la_deja_apagada():
	var screen = _make_screen()
	screen._on_choice(false)
	assert_bool(SettingsManager.telemetry_enabled).is_false()
	assert_bool(SettingsManager.error_reports_enabled).is_false()
	assert_bool(SettingsManager.consent_asked).is_true()
	assert_bool(SettingsManager.needs_privacy_consent()).is_false()
