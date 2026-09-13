extends GdUnitTestSuite

# test_export_includes_preloaded_assets.gd - Un asset que usa el juego tiene que entrar al paquete.
#
# El preset exporta en modo "resources": Godot sigue dependencias SOLO desde los recursos elegidos
# (export_files). Lo que entra por include_filter se copia tal cual, sin arrastrar nada: ni los
# preload() de un script ni los ext_resource de una escena que no este en export_files. Y en
# include_filter "assets/**/*.png" no casa con un .png suelto en assets/ (el ** de Godot pide al
# menos una carpeta). Paso con el fondo del control remoto: tests en verde y en el telefono la
# pantalla no compilaba ("No loader found").

# Pre-existentes, no de este cambio: revisar si la escena que los usa se exporta.
const KNOWN_UNEXPORTED := ["res://assets/odisea_icon.png <- res://core_v2/props/parallax_assets/parallax_material.tres (escena fuera de export_files)"]
const MEDIA_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "svg", "tga", "ogg", "wav", "mp3", "ttf", "otf", "exr"]
const SCAN_ROOTS := ["res://core_v2", "res://scenes"]

func test_media_used_by_scripts_and_filtered_scenes_is_exported_on_android():
	var preset: Dictionary = _android_preset()
	var filters: Array = preset.get("filters", [])
	assert_bool(filters.empty()).is_false()

	# Lo que Godot SI arrastra: todo lo alcanzable por ext_resource desde export_files.
	var reachable: Dictionary = {}
	var pending: Array = preset.get("files", []).duplicate()
	while not pending.empty():
		var path: String = pending.pop_back()
		if reachable.has(path):
			continue
		reachable[path] = true
		if path.get_extension() in ["tscn", "tres"]:
			pending += _ext_resources(path)

	var missing: Array = []
	for root in SCAN_ROOTS:
		for script_path in _files(root, ["gd"]):
			if script_path.find("/tests/") == -1:
				for asset in _preloaded_media(script_path):
					if not _exported(asset, reachable, filters):
						missing.append("%s <- preload en %s" % [asset, script_path])
		for scene_path in _files(root, ["tscn", "tres"]):
			if scene_path.find("/tests/") != -1 or reachable.has(scene_path):
				continue # sus dependencias las arrastra el export
			for asset in _ext_resources(scene_path):
				if asset.get_extension().to_lower() in MEDIA_EXTENSIONS and not _exported(asset, reachable, filters):
					missing.append("%s <- %s (escena fuera de export_files)" % [asset, scene_path])
	for known in KNOWN_UNEXPORTED:
		missing.erase(known)
	assert_array(missing).is_empty()

func _exported(asset: String, reachable: Dictionary, filters: Array) -> bool:
	return reachable.has(asset) or _matches_any(asset.trim_prefix("res://"), filters)

func _android_preset() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		return {}
	for section in cfg.get_sections():
		if String(cfg.get_value(section, "name", "")) == "Android":
			var filters: Array = []
			for f in String(cfg.get_value(section, "include_filter", "")).split(","):
				if f.strip_edges() != "":
					filters.append(f.strip_edges())
			return {"filters": filters, "files": Array(cfg.get_value(section, "export_files", PoolStringArray()))}
	return {}

func _matches_any(path: String, filters: Array) -> bool:
	for f in filters:
		if path.matchn(f):
			return true
	return false

func _preloaded_media(script_path: String) -> Array:
	var file := File.new()
	if file.open(script_path, File.READ) != OK:
		return []
	var text := file.get_as_text()
	file.close()
	var out: Array = []
	var regex := RegEx.new()
	regex.compile("preload\\(\\s*\"(res://[^\"]+)\"\\s*\\)")
	for m in regex.search_all(text):
		var asset: String = m.get_string(1)
		if asset.get_extension().to_lower() in MEDIA_EXTENSIONS:
			out.append(asset)
	return out

# Solo la cabecera: los ext_resource van antes del primer nodo o recurso.
func _ext_resources(path: String) -> Array:
	var out: Array = []
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return out
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("[node") or line.begins_with("[sub_resource") or line.begins_with("[resource"):
			break
		if line.begins_with("[ext_resource"):
			var at := line.find("path=\"")
			if at != -1:
				var start := at + 6
				out.append(line.substr(start, line.find("\"", start) - start))
	file.close()
	return out

func _files(root: String, extensions: Array) -> Array:
	var out: Array = []
	var dir := Directory.new()
	if dir.open(root) != OK:
		return out
	dir.list_dir_begin(true, true)
	var name := dir.get_next()
	while name != "":
		var full := root.plus_file(name)
		if dir.current_is_dir():
			out += _files(full, extensions)
		elif name.get_extension() in extensions:
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out
