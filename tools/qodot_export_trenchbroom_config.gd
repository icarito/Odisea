extends SceneTree

# qodot_export_trenchbroom_config.gd — Instala GameConfig.cfg + Icon.png en TrenchBroom.
#
# El boton `export_file` de TrenchBroomGameConfig solo corre con el editor de Godot
# abierto (Engine.is_editor_hint()), igual que el del FGD. Esto hace lo mismo desde
# consola, con una diferencia deliberada: NO copia el .fgd.
#
# El .fgd se instala como symlink al repo (scripts/link_trenchbroom_fgd.sh), asi que
# se actualiza solo cada vez que se regenera. Copiarlo aca lo reemplazaria por una
# copia muerta que hay que acordarse de refrescar.
#
# Run:   godot3-bin --no-window -s tools/qodot_export_trenchbroom_config.gd
# Check: QODOT_TB_CHECK=1 godot3-bin --no-window -s tools/qodot_export_trenchbroom_config.gd
#
# El destino sale de trenchbroom_games_folder + game_name del .tres, o de
# $TRENCHBROOM_ODISEA_GAME_DIR si esta definida (mismo override que usa
# scripts/link_trenchbroom_fgd.sh).

const CONFIG_RESOURCE := "res://addons/qodot/game_definitions/trenchbroom/trenchbroom_game_config.tres"
# GameConfig.cfg declara "initialmap": "initial_valve.map" para el formato Valve.
const INITIAL_MAP_SOURCE := "res://maps/templates/initial_valve.map"
const INITIAL_MAP_NAME := "initial_valve.map"

func _init() -> void:
	var config = load(CONFIG_RESOURCE)
	if config == null:
		printerr("No se pudo cargar ", CONFIG_RESOURCE)
		quit(1)
		return

	var folder := OS.get_environment("TRENCHBROOM_ODISEA_GAME_DIR")
	if folder == "":
		if config.trenchbroom_games_folder == "":
			printerr("El .tres no define trenchbroom_games_folder y no hay TRENCHBROOM_ODISEA_GAME_DIR")
			quit(1)
			return
		folder = config.trenchbroom_games_folder + "/" + config.game_name

	if config.fgd_files.empty():
		printerr("El .tres no referencia ningun FGD")
		quit(1)
		return

	# build_class_text() lee fgd_filenames, que normalmente llena set_export_file().
	config.fgd_filenames = []
	for fgd in config.fgd_files:
		config.fgd_filenames.append(fgd.fgd_name + ".fgd")

	var text: String = config.build_class_text()
	var cfg_path := folder + "/GameConfig.cfg"

	if OS.get_environment("QODOT_TB_CHECK") != "":
		var f := File.new()
		if f.open(cfg_path, File.READ) != OK:
			printerr("FALTA ", cfg_path, " — corre tools/qodot_export_trenchbroom_config.gd")
			quit(1)
			return
		var current := f.get_as_text()
		f.close()
		if current != text:
			printerr("GameConfig.cfg instalado esta desactualizado. Corre:")
			printerr("  godot3-bin --no-window -s tools/qodot_export_trenchbroom_config.gd")
			quit(1)
			return
		print("GameConfig.cfg al dia en ", folder)
		quit(0)
		return

	var d := Directory.new()
	if not d.dir_exists(folder):
		if d.make_dir_recursive(folder) != OK:
			printerr("No se pudo crear ", folder)
			quit(1)
			return

	var out := File.new()
	if out.open(cfg_path, File.WRITE) != OK:
		printerr("No se pudo escribir ", cfg_path)
		quit(1)
		return
	out.store_string(text)
	out.close()
	print("GameConfig.cfg -> ", cfg_path)

	if config.icon != null:
		var img: Image = config.icon.get_data()
		if img.is_compressed():
			img.decompress()
		# Los Icon.png que trae TrenchBroom son 32x32 RGBA. El nuestro salia RGB
		# (colortype 2) porque la fuente es un JPEG sin canal alfa.
		img.convert(Image.FORMAT_RGBA8)
		img.resize(32, 32, Image.INTERPOLATE_LANCZOS)
		var icon_path := folder + "/Icon.png"
		img.save_png(icon_path)
		print("Icon.png     -> ", icon_path)

	# Plantilla de mapa nuevo: TrenchBroom la copia en File > New. Es lo unico que
	# hace que un mapa nuevo arranque con las colecciones de textura habilitadas,
	# porque _tb_textures se guarda por mapa.
	var tpl := File.new()
	if tpl.open(INITIAL_MAP_SOURCE, File.READ) == OK:
		var tpl_text := tpl.get_as_text()
		tpl.close()
		var dst := File.new()
		var dst_path := folder + "/" + INITIAL_MAP_NAME
		if dst.open(dst_path, File.WRITE) == OK:
			dst.store_string(tpl_text)
			dst.close()
			print("%-12s -> %s" % [INITIAL_MAP_NAME, dst_path])
		else:
			printerr("No se pudo escribir ", dst_path)
	else:
		printerr("Falta ", INITIAL_MAP_SOURCE)

	var fgd_path: String = folder + "/" + config.fgd_filenames[0]
	var probe := File.new()
	if not probe.file_exists(fgd_path):
		print("")
		print("Falta el FGD en ", fgd_path, ". Enlazalo con:")
		print("  bash scripts/link_trenchbroom_fgd.sh")

	print("")
	print("En TrenchBroom: cerrar y reabrir para que relea GameConfig.cfg")
	print("(File > Reload Entity Definitions solo recarga el .fgd, no la config).")
	quit(0)
