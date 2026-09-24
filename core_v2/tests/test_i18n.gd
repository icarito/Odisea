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


# Guard de integridad de traducciones (O16): toda clave del CSV debe existir en cada .translation
# compilado. Los .translation del importador son PHashTranslation (guardan solo hashes y valores,
# no las claves fuente), asi que un grep sobre el binario no prueba nada: hay que preguntarle al
# recurso con get_message(). Sin este guard, editar el CSV sin reimportar (o una fila con la
# cantidad de campos equivocada, que corta el importador) deja claves sin traducir en silencio.
const UI_STRINGS_CSV := "res://locale/ui_strings.csv"
const UI_STRINGS_LOCALES := ["es", "en", "ko", "pt_BR", "de", "fr", "nl"]

func _read_ui_strings_csv() -> Dictionary:
	var f := File.new()
	var err := f.open(UI_STRINGS_CSV, File.READ)
	assert_int(err).is_equal(OK)
	var header := f.get_csv_line(",")
	var locales := []
	for i in range(1, header.size()):
		locales.append(header[i])
	var keys := []
	var malformed := []
	while not f.eof_reached():
		var line := f.get_csv_line(",")
		if line.size() == 1 and line[0] == "":
			continue
		if line.size() != header.size():
			malformed.append(line[0])
			continue
		if line[0] != "":
			keys.append(line[0])
	f.close()
	return {"locales": locales, "keys": keys, "malformed": malformed}

func test_every_csv_key_exists_in_every_compiled_translation() -> void:
	var csv := _read_ui_strings_csv()
	assert_bool(csv["malformed"].empty()).override_failure_message(
		"Filas del CSV con cantidad de campos incorrecta (cortan el import): %s" % [csv["malformed"]]).is_true()
	var keys: Array = csv["keys"]
	assert_int(keys.size()).is_greater(0)
	for code in csv["locales"]:
		var trans = load("res://locale/ui_strings.%s.translation" % code) as Translation
		assert_object(trans).is_not_null()
		var missing := []
		for key in keys:
			if String(trans.get_message(key)) == "":
				missing.append(key)
		assert_bool(missing.empty()).override_failure_message(
			"Claves del CSV sin traducir en '%s': %s" % [code, missing]).is_true()

func test_pause_menu_main_menu_key_resolves_in_every_locale() -> void:
	# O16: la clave de la escena PauseMenu.tscn (nodo MainMenu) debe resolver en cada idioma.
	var key := "MAIN_MENU"
	for code in UI_STRINGS_LOCALES:
		var trans = load("res://locale/ui_strings.%s.translation" % code) as Translation
		assert_object(trans).is_not_null()
		assert_bool(String(trans.get_message(key)) != "").override_failure_message(
			"'%s' no resuelve en '%s'" % [key, code]).is_true()
	var en_trans = load("res://locale/ui_strings.en.translation") as Translation
	assert_str(String(en_trans.get_message(key))).is_equal("MAIN MENU")
