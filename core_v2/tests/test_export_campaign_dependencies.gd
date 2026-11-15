extends GdUnitTestSuite

# test_export_campaign_dependencies.gd - Lo que carga la campaña tiene que viajar en el paquete.
#
# El export corre en modo "resources": entra el cierre de dependencias de export_files mas lo que
# matchea include_filter (los globs NO caminan dependencias), y exclude_filter gana sobre ambos.
# Un exclude que tapa una dependencia de una escena de campaña no falla el export: falla en el
# jugador con "No loader found for resource" (rusty_metal_grid_disp_1k.png <- DomeShell_baked.mesh
# <- Dome_Base <- Dome_Intro, nightly de Linux). Las dependencias salen del motor
# (ResourceLoader.get_dependencies), que lee tambien los binarios comprimidos (RSCC).
#
# Raices: las escenas de la linea de campaña y los autoloads de project.godot. En los scripts se
# siguen ademas los literales "res://...tscn|tres" que existen en disco: asi entra lo que se carga
# por string (ProgrammerHoloNPC.SCENE_PATH -> ProgrammerHoloNPC.tscn -> models/Programmer.glb, que
# fallo en los nightlies de Android 772-780 segun los client-logs del central).

const CampaignRoute = preload("res://core_v2/tests/test_campaign_route.gd")
const PRESET_NAME := "Linux/X11 x86_64"
const DEV_PREFIXES := ["res://core_v2/tests/", "res://tests/", "res://addons/gdUnit3/"]

func test_campaign_scene_dependencies_are_exported_on_linux() -> void:
	var preset: Dictionary = _preset(PRESET_NAME)
	var include: Array = preset.get("include", [])
	var exclude: Array = preset.get("exclude", [])
	assert_bool(include.empty() or exclude.empty()).is_false()

	var rooted: Dictionary = _closure(preset.get("files", []), {}, false)
	var problems: Array = []
	for scene in CampaignRoute.REQUIRED_REACHABLE_SCENES:
		# la escena existe y el motor le ve dependencias
		assert_int(ResourceLoader.get_dependencies(scene).size()).is_greater(0)
	var roots: Array = CampaignRoute.REQUIRED_REACHABLE_SCENES + _autoloads()
	var parent: Dictionary = {}
	var deps: Dictionary = _closure(roots, parent, true)
	assert_bool(deps.has("res://core_v2/actors/ProgrammerHoloNPC.tscn")).is_true() # carga por string
	assert_bool(deps.has("res://models/Programmer.glb")).is_true()
	for dep in deps:
		var rel: String = String(dep).trim_prefix("res://")
		var hit: String = _first_match(rel, exclude)
		if hit != "":
			problems.append("exclude_filter '%s' tapa %s%s" % [hit, dep, _chain(dep, parent)])
		elif not rooted.has(dep) and _first_match(rel, include) == "":
			problems.append("fuera de include_filter y de export_files: %s%s" % [dep, _chain(dep, parent)])
	assert_array(problems).is_empty()

func _chain(dep: String, parent: Dictionary) -> String:
	var out := ""
	while parent.has(dep):
		dep = parent[dep]
		out += " <- " + dep
	return out

# Los autoloads cargan antes que cualquier escena: si a uno le falta algo, falla el arranque.
func _autoloads() -> Array:
	var out: Array = []
	for prop in ProjectSettings.get_property_list():
		var name: String = prop.name
		if name.begins_with("autoload/"):
			out.append(String(ProjectSettings.get_setting(name)).trim_prefix("*"))
	return out

# Escenas y recursos que un script nombra por string (SCENE_PATH, goto_scene, load): el export no
# los sigue, pero el juego los carga. Los arboles de desarrollo se excluyen a proposito.
# ponytail: solo .tscn/.tres. Otros literales (.gd opcionales, .js, .md, iconos .svg) son caminos
# con guardia y dan falsos positivos; el cruce amplio contra exclude_filter lo hace
# scripts/check_export_presets.py en el workflow de export.
func _script_literals(path: String) -> Array:
	var out: Array = []
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return out
	var text := file.get_as_text()
	file.close()
	var regex := RegEx.new()
	regex.compile("\"(res://[^\"]+\\.(?:tscn|tres))\"")
	for m in regex.search_all(text):
		var ref: String = m.get_string(1)
		if file.file_exists(ref) and not _is_dev_path(ref):
			out.append(ref)
	return out

func _is_dev_path(path: String) -> bool:
	for prefix in DEV_PREFIXES:
		if path.begins_with(prefix):
			return true
	return false

func _closure(roots: Array, parent: Dictionary, follow_literals: bool) -> Dictionary:
	var seen: Dictionary = {}
	var pending: Array = roots.duplicate()
	while not pending.empty():
		var path: String = pending.pop_back()
		if seen.has(path):
			continue
		seen[path] = true
		var deps: Array = Array(ResourceLoader.get_dependencies(path))
		if follow_literals and path.get_extension() == "gd":
			deps += _script_literals(path)
		for dep in deps:
			if not seen.has(dep):
				if not parent.has(dep):
					parent[dep] = path
				pending.append(dep)
	return seen

func _preset(name: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		return {}
	for section in cfg.get_sections():
		if String(cfg.get_value(section, "name", "")) == name:
			return {
				"include": _patterns(cfg.get_value(section, "include_filter", "")),
				"exclude": _patterns(cfg.get_value(section, "exclude_filter", "")),
				"files": Array(cfg.get_value(section, "export_files", PoolStringArray())),
			}
	return {}

func _patterns(filter: String) -> Array:
	var out: Array = []
	for f in filter.split(","):
		if f.strip_edges() != "":
			out.append(f.strip_edges())
	return out

func _first_match(path: String, patterns: Array) -> String:
	for p in patterns:
		if path.matchn(p):
			return p
	return ""
