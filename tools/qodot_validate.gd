extends SceneTree

# qodot_validate.gd — Chequeo de integridad de la integracion Qodot/TrenchBroom.
#
# Corre en CI o antes de tocar TrenchBroom. Verifica, en este orden:
#   1. qodot_fgd.tres carga y no quedaron huecos null en entity_definitions
#   2. cada point class resuelve su scene_file / script_class y no hay classnames
#      duplicados ni vacios
#   3. Qodot.fgd en disco coincide con lo que generan los .tres
#   4. las texturas especiales existen (special/clip, special/skip) y toda textura
#      referenciada por un .map se resuelve a un archivo real
#   5. addons/qodot/src/nodes/qodot_map.gd sigue compilando
#
# Run: godot3-bin --no-window -s tools/qodot_validate.gd

const FGD_RESOURCE := "res://addons/qodot/game_definitions/fgd/qodot_fgd.tres"
const FGD_TEXT := "res://Qodot.fgd"
const MAPS_DIR := "res://maps"
const TEXTURE_DIR := "res://textures"
const TEXTURE_EXTS := ["png", "jpg", "jpeg", "tga", "bmp", "webp"]
# TrenchBroom usa este nombre para caras sin textura asignada; no hay archivo.
const TB_PLACEHOLDER := "__TB_empty"

var _errors := []
var _warnings := []

func _init() -> void:
	_check_fgd_resource()
	_check_fgd_text()
	_check_textures()
	_check_qodot_map()

	for w in _warnings:
		print("  AVISO: ", w)
	for e in _errors:
		printerr("  ERROR: ", e)
	if _errors.empty():
		print("qodot_validate: OK (%d avisos)" % _warnings.size())
		quit(0)
	else:
		printerr("qodot_validate: %d errores" % _errors.size())
		quit(1)

func _check_fgd_resource() -> void:
	var fgd = load(FGD_RESOURCE)
	if fgd == null:
		_errors.append("no carga %s" % FGD_RESOURCE)
		return

	var nulls := 0
	for ent_def in fgd.entity_definitions:
		if ent_def == null:
			nulls += 1
	if nulls > 0:
		_errors.append("entity_definitions tiene %d huecos null" % nulls)

	var seen := {}
	for ent in fgd.get_fgd_classes():
		var cn: String = ent.classname
		if cn.strip_edges() == "":
			_errors.append("classname vacio en %s" % ent.resource_path)
			continue
		if seen.has(cn):
			_errors.append("classname duplicado: %s" % cn)
		seen[cn] = true

		if not String(ent.resource_path).begins_with("res://core_v2/"):
			continue
		if ent is QodotFGDPointClass:
			if ent.scene_file == null and ent.script_class == null:
				_errors.append("%s: point class sin scene_file ni script_class" % cn)
		elif ent is QodotFGDSolidClass:
			if ent.script_class == null and ent.node_class == "":
				_warnings.append("%s: solid class sin script_class ni node_class" % cn)
	print("fgd: %d clases" % fgd.get_fgd_classes().size())

func _check_fgd_text() -> void:
	var fgd = load(FGD_RESOURCE)
	if fgd == null:
		return
	var f := File.new()
	if f.open(FGD_TEXT, File.READ) != OK:
		_errors.append("falta %s" % FGD_TEXT)
		return
	var disk := f.get_as_text()
	f.close()
	if disk != fgd.build_class_text():
		_errors.append("Qodot.fgd desactualizado; corre tools/qodot_export_fgd.gd")

func _check_textures() -> void:
	for special in ["special/clip", "special/skip"]:
		if _resolve_texture(special) == "":
			_errors.append("falta la textura especial %s (la piden brush_clip_texture / face_skip_texture)" % special)

	var missing := {}
	var total := 0
	var d := Directory.new()
	if d.open(MAPS_DIR) != OK:
		return
	d.list_dir_begin(true, true)
	var name := d.get_next()
	while name != "":
		if name.ends_with(".map"):
			for tex in _map_textures(MAPS_DIR + "/" + name):
				total += 1
				if tex == TB_PLACEHOLDER:
					continue
				if _resolve_texture(tex) == "":
					missing[tex] = name
		name = d.get_next()
	d.list_dir_end()

	for tex in missing:
		_errors.append("%s pide la textura %s y no existe bajo %s" % [missing[tex], tex, TEXTURE_DIR])
	print("texturas: %d nombres distintos en los .map, %d sin archivo" % [total, missing.size()])

func _resolve_texture(rel: String) -> String:
	var f := File.new()
	for ext in TEXTURE_EXTS:
		var path := "%s/%s.%s" % [TEXTURE_DIR, rel, ext]
		if f.file_exists(path):
			return path
	return ""

# Devuelve los nombres de textura distintos de un .map. Sirve tanto para el formato
# Standard (TEX ox oy rot sx sy) como para Valve 220 (TEX [ u ] [ v ] rot sx sy):
# en ambos la textura es el token que sigue al ultimo ")" del plano.
func _map_textures(path: String) -> Array:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return []
	var text := f.get_as_text()
	f.close()

	var found := {}
	for line in text.split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.begins_with("("):
			continue
		var close := stripped.find_last(")")
		if close == -1:
			continue
		var tail: String = stripped.substr(close + 1, stripped.length()).strip_edges()
		var space := tail.find(" ")
		if space == -1:
			continue
		found[tail.substr(0, space)] = true
	return found.keys()

func _check_qodot_map() -> void:
	if load("res://addons/qodot/src/nodes/qodot_map.gd") == null:
		_errors.append("qodot_map.gd no compila")
