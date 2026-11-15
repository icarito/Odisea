extends GdUnitTestSuite

# test_export_campaign_dependencies.gd - Lo que carga la campaña tiene que viajar en el paquete.
#
# El export corre en modo "resources": entra el cierre de dependencias de export_files mas lo que
# matchea include_filter (los globs NO caminan dependencias), y exclude_filter gana sobre ambos.
# Un exclude que tapa una dependencia de una escena de campaña no falla el export: falla en el
# jugador con "No loader found for resource" (rusty_metal_grid_disp_1k.png <- DomeShell_baked.mesh
# <- Dome_Base <- Dome_Intro, nightly de Linux). Las dependencias salen del motor
# (ResourceLoader.get_dependencies), que lee tambien los binarios comprimidos (RSCC).

const CampaignRoute = preload("res://core_v2/tests/test_campaign_route.gd")
const PRESET_NAME := "Linux/X11 x86_64"

func test_campaign_scene_dependencies_are_exported_on_linux() -> void:
	var preset: Dictionary = _preset(PRESET_NAME)
	var include: Array = preset.get("include", [])
	var exclude: Array = preset.get("exclude", [])
	assert_bool(include.empty() or exclude.empty()).is_false()

	var rooted: Dictionary = _closure(preset.get("files", []), {})
	var problems: Array = []
	for scene in CampaignRoute.REQUIRED_REACHABLE_SCENES:
		var parent: Dictionary = {}
		var deps: Dictionary = _closure([scene], parent)
		assert_int(deps.size()).is_greater(1) # la escena existe y el motor le ve dependencias
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

func _closure(roots: Array, parent: Dictionary) -> Dictionary:
	var seen: Dictionary = {}
	var pending: Array = roots.duplicate()
	while not pending.empty():
		var path: String = pending.pop_back()
		if seen.has(path):
			continue
		seen[path] = true
		for dep in ResourceLoader.get_dependencies(path):
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
