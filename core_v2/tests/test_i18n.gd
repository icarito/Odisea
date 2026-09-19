# res://core_v2/tests/test_i18n.gd
extends GdUnitTestSuite

var _orig_lang: String = "auto"

func before_test():
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		_orig_lang = sm.ui_language
		sm.apply_locale_settings()

func after_test():
	# El locale es estado global del TranslationServer: si no se devuelve, la
	# suite siguiente corre en el ultimo idioma que toco este archivo.
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.ui_language = _orig_lang
		sm.apply_locale_settings()
	else:
		TranslationServer.set_locale("es")

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

func test_korean_translation():
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.ui_language = "ko"
		sm.apply_locale_settings()
	else:
		TranslationServer.set_locale("ko")

	assert_str(TranslationServer.get_locale()).is_equal("ko")
	assert_str(TranslationServer.tr("NUEVA PARTIDA")).is_equal("새 게임")
	assert_str(TranslationServer.tr("OPCIONES")).is_equal("설정")
	assert_str(TranslationServer.tr("VOLVER")).is_equal("뒤로")

func test_portuguese_translation():
	var sm = get_node_or_null("/root/SettingsManager")
	if sm:
		sm.ui_language = "pt_BR"
		sm.apply_locale_settings()
	else:
		TranslationServer.set_locale("pt_BR")

	assert_str(TranslationServer.get_locale()).is_equal("pt_BR")
	assert_str(TranslationServer.tr("NUEVA PARTIDA")).is_equal("NOVO JOGO")
	assert_str(TranslationServer.tr("OPCIONES")).is_equal("OPÇÕES")
	assert_str(TranslationServer.tr("VOLVER")).is_equal("VOLTAR")

func test_korean_font_has_hangul():
	# El fallback de fuente es lo unico que separa al coreano del tofu: Ac437
	# (TinyFont: prompts, pistas y subtitulos) no tiene un solo glifo Hangul.
	var font = load("res://TinyFont.tres") as DynamicFont
	assert_object(font).is_not_null()
	assert_int(font.get_fallback_count()).is_greater(0)
	# Sin un fallback que cubra Hangul, la silaba no mide mas que el espacio vacio.
	assert_bool(font.get_string_size("가").x > font.get_string_size(" ").x).is_true()
	# El mismo fallback tapa los 13 acentos que le faltan a Ac437 (FD-308 §5):
	# sin el, "ã" y "õ" son tofu justo en los subtitulos y en los prompts.
	assert_bool(font.get_string_size("ã").x > font.get_string_size(" ").x).is_true()
	assert_bool(font.get_string_size("õ").x > font.get_string_size(" ").x).is_true()

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
