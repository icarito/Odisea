extends GdUnitTestSuite

const LogOverlayScript = preload("res://core_v2/levels/diag/LogOverlay.gd")
const ReporterScript = preload("res://core_v2/telemetry/ErrorLogReporter.gd")
const AdaptiveScript = preload("res://core_v2/systems/AdaptiveRenderScale.gd")
const SettingsScript = preload("res://core_v2/autoloads/SettingsManager.gd")


func test_el_overlay_de_log_es_de_sesion_y_no_se_persiste() -> void:
	# Si se guardara, un arranque con problemas dejaria el overlay tapando la pantalla
	# para siempre. La opcion existe, pero solo para la corrida actual.
	var f := File.new()
	assert_int(f.open("res://core_v2/autoloads/SettingsManager.gd", File.READ)).is_equal(OK)
	var code := f.get_as_text()
	f.close()
	assert_bool(code.find("log_overlay_enabled: bool = false") != -1).is_true()
	assert_bool(code.find('"log_overlay_enabled"') != -1).override_failure_message(
		"log_overlay_enabled no debe leerse ni escribirse en settings.cfg"
	).is_false()


func test_la_variable_de_entorno_prende_el_overlay_sin_tocar_la_opcion() -> void:
	assert_bool(LogOverlayScript._wants_overlay("1", false)).is_true()
	assert_bool(LogOverlayScript._wants_overlay(" ON ", false)).is_true()
	assert_bool(LogOverlayScript._wants_overlay("", true)).is_true()
	assert_bool(LogOverlayScript._wants_overlay("", false)).is_false()


func test_el_reportador_descarta_el_ruido_conocido() -> void:
	# "ERROR: NO GRAB" sale en cada arranque headless y no dice nada del dispositivo.
	assert_bool(ReporterScript._is_noise_in("ERROR: NO GRAB", ReporterScript.IGNORE)).is_true()
	assert_bool(ReporterScript._is_noise_in(
		"ERROR: shader link failed", ReporterScript.IGNORE)).is_false()


# El tiempo de arranque es lo unico que se sabe del aparato antes del primer frame. Solo
# puede BAJAR la escala inicial: el techo elegido por el jugador se respeta aparte.
func test_el_arranque_lento_elige_una_escala_inicial_menor() -> void:
	var e := [2500.0, 4500.0, 8000.0]
	assert_int(AdaptiveScript._indice_por_arranque(400.0, e[0], e[1], e[2])).is_equal(0)
	assert_int(AdaptiveScript._indice_por_arranque(2499.0, e[0], e[1], e[2])).is_equal(0)
	assert_int(AdaptiveScript._indice_por_arranque(2500.0, e[0], e[1], e[2])).is_equal(1)
	assert_int(AdaptiveScript._indice_por_arranque(5000.0, e[0], e[1], e[2])).is_equal(2)
	assert_int(AdaptiveScript._indice_por_arranque(12000.0, e[0], e[1], e[2])).is_equal(3)


func test_sin_medicion_de_arranque_no_se_toca_nada() -> void:
	# En tests, replays y otros puntos de entrada no pasa por Boot.tscn: sin dato, 1.0.
	assert_int(AdaptiveScript._indice_por_arranque(0.0, 2500.0, 4500.0, 8000.0)).is_equal(0)
	assert_int(AdaptiveScript._indice_por_arranque(-1.0, 2500.0, 4500.0, 8000.0)).is_equal(0)


func test_los_escalones_de_arranque_existen_en_la_tabla_de_escalas() -> void:
	# Los indices 1..3 tienen que ser 0.85 / 0.75 / 0.60; si alguien reordena ESCALAS,
	# la heuristica empieza a elegir otra cosa en silencio.
	assert_float(AdaptiveScript.ESCALAS[1]).is_equal_approx(0.85, 0.001)
	assert_float(AdaptiveScript.ESCALAS[2]).is_equal_approx(0.75, 0.001)
	assert_float(AdaptiveScript.ESCALAS[3]).is_equal_approx(0.6, 0.001)
