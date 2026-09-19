# tools/i18n_build_translations.gd
#
# Genera las .translation de locale/ui_strings.csv sin abrir el editor.
#
# Replica exacto lo que hace ResourceImporterCSVTranslation (una Translation por
# columna, c_unescape en cada celda, PHashTranslation si compress) para que el
# resultado sea el mismo que produce un reimport. Existe porque abrir el editor
# solo para esto dispara un reimport completo de texturas: minutos y un diff de
# .import/ que no tiene nada que ver con el cambio.
#
#   tools/godot --no-window --script tools/i18n_build_translations.gd
extends SceneTree

const CSV_PATH = "res://locale/ui_strings.csv"
const COMPRESS = true

func _init():
	var f = File.new()
	if f.open(CSV_PATH, File.READ) != OK:
		push_error("no pude abrir %s" % CSV_PATH)
		quit(1)
		return

	var header = f.get_csv_line(",")
	if header.size() <= 1:
		push_error("header invalido en %s" % CSV_PATH)
		f.close()
		quit(1)
		return

	var locales = []
	var translations = []
	for i in range(1, header.size()):
		var locale = TranslationServer.standardize_locale(header[i])
		var t = Translation.new()
		t.locale = locale
		locales.append(locale)
		translations.append(t)

	var rows = 0
	while not f.eof_reached():
		var line = f.get_csv_line(",")
		if line.size() != header.size():
			continue
		if line[0] == "":
			continue
		for i in range(1, line.size()):
			translations[i - 1].add_message(line[0], line[i].c_unescape())
		rows += 1
	f.close()

	var base = CSV_PATH.get_basename()
	for i in range(translations.size()):
		var out = translations[i]
		if COMPRESS:
			var packed = PHashTranslation.new()
			packed.generate(out)
			out = packed
		var path = "%s.%s.translation" % [base, locales[i]]
		if ResourceSaver.save(path, out) != OK:
			push_error("no pude guardar %s" % path)
			quit(1)
			return
		print("  %s  (%d mensajes)" % [path, rows])

	print("[i18n] %d filas -> %d locales: %s" % [rows, locales.size(), PoolStringArray(locales).join(", ")])
	quit(0)
