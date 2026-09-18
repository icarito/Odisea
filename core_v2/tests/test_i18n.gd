# res://core_v2/tests/test_i18n.gd
extends GdUnitTestSuite

func before_test():
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.apply_locale_settings()

func test_english_translation():
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.ui_language = "en"
		sm.apply_locale_settings()
	else:
		TranslationServer.set_locale("en")

	assert_str(TranslationServer.tr("NUEVA PARTIDA")).is_equal("NEW GAME")
	assert_str(TranslationServer.tr("OPCIONES")).is_equal("OPTIONS")
	assert_str(TranslationServer.tr("VOLVER")).is_equal("BACK")

func test_spanish_translation():
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.ui_language = "es"
		sm.apply_locale_settings()
	else:
		TranslationServer.set_locale("es")

	assert_str(TranslationServer.tr("NUEVA PARTIDA")).is_equal("NUEVA PARTIDA")
	assert_str(TranslationServer.tr("OPCIONES")).is_equal("OPCIONES")
	assert_str(TranslationServer.tr("VOLVER")).is_equal("VOLVER")

func test_missing_key_fallback():
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.ui_language = "en"
		sm.apply_locale_settings()
	else:
		TranslationServer.set_locale("en")

	var missing_key = "NON_EXISTENT_KEY_12345"
	assert_str(TranslationServer.tr(missing_key)).is_equal(missing_key)

func test_settings_manager_locale():
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		var orig_lang = sm.ui_language
		sm.ui_language = "en"
		sm.apply_locale_settings()
		assert_str(TranslationServer.get_locale()).is_equal("en")
		assert_str(TranslationServer.tr("NUEVA PARTIDA")).is_equal("NEW GAME")

		sm.ui_language = "es"
		sm.apply_locale_settings()
		assert_str(TranslationServer.get_locale()).is_equal("es")
		assert_str(TranslationServer.tr("NUEVA PARTIDA")).is_equal("NUEVA PARTIDA")

		sm.ui_language = orig_lang
		sm.apply_locale_settings()
