extends SceneTree

# qodot_export_fgd.gd — Regenera Qodot.fgd desde los .tres.
#
# El boton `export_file` de QodotFGDFile solo funciona con el editor abierto
# (Engine.is_editor_hint()), asi que en CI / en consola no sirve. Esto usa el MISMO
# build_class_text() del plugin, de modo que el .fgd no se escribe a mano nunca:
# la fuente de verdad son addons/qodot/game_definitions/fgd/qodot_fgd.tres y los
# .tres de core_v2/qodot_fgd/props/.
#
# Run:  godot3-bin --no-window -s tools/qodot_export_fgd.gd
# Check (no escribe, falla si el archivo quedo viejo):
#       QODOT_FGD_CHECK=1 godot3-bin --no-window -s tools/qodot_export_fgd.gd
#
# Despues de regenerar, scripts/link_trenchbroom_fgd.sh lo enlaza a ~/.TrenchBroom.

const FGD_RESOURCE := "res://addons/qodot/game_definitions/fgd/qodot_fgd.tres"
const OUT_PATH := "res://Qodot.fgd"

func _init() -> void:
	var fgd = load(FGD_RESOURCE)
	if fgd == null:
		printerr("No se pudo cargar ", FGD_RESOURCE)
		quit(1)
		return

	var classes: Array = fgd.get_fgd_classes()
	var names := {}
	var problems := []
	for ent in classes:
		var cn: String = ent.classname
		if cn == "":
			problems.append("classname vacio en %s" % ent.resource_path)
		elif names.has(cn):
			problems.append("classname duplicado: %s" % cn)
		else:
			names[cn] = true
		# signal / receiver son marcadores de cableado del propio Qodot: no instancian
		# nada a proposito. Solo importa que una point class NUESTRA no quede vacia.
		var own: bool = String(ent.resource_path).begins_with("res://core_v2/")
		if own and ent is QodotFGDPointClass and ent.scene_file == null and ent.script_class == null:
			problems.append("%s: point class sin scene_file ni script_class" % cn)

	# entity_definitions guarda nulls cuando una entrada quedo colgada; get_fgd_classes
	# los filtra en silencio, asi que hay que contarlos aparte.
	var nulls := 0
	for ent_def in fgd.entity_definitions:
		if ent_def == null:
			nulls += 1

	var text: String = fgd.build_class_text()

	if OS.get_environment("QODOT_FGD_CHECK") != "":
		var f := File.new()
		if f.open(OUT_PATH, File.READ) != OK:
			printerr("FALTA ", OUT_PATH)
			quit(1)
			return
		var current := f.get_as_text()
		f.close()
		if current != text:
			printerr("Qodot.fgd esta desactualizado respecto de los .tres. Corre:")
			printerr("  godot3-bin --no-window -s tools/qodot_export_fgd.gd")
			quit(1)
			return
		print("Qodot.fgd al dia (%d clases, %d huecos null)" % [classes.size(), nulls])
		quit(0)
		return

	var out := File.new()
	if out.open(OUT_PATH, File.WRITE) != OK:
		printerr("No se pudo escribir ", OUT_PATH)
		quit(1)
		return
	out.store_string(text)
	out.close()

	print("Qodot.fgd: %d clases, %d huecos null en entity_definitions" % [classes.size(), nulls])
	for p in problems:
		printerr("  AVISO: ", p)
	quit(1 if problems.size() > 0 else 0)
