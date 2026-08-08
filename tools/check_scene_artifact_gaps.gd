extends SceneTree

# check_scene_artifact_gaps.gd — Lista los assets importados que una escena
# arrastra y cuyo artefacto NO esta trackeado en git: los que no van a existir en
# CI en frio y hacen fallar el smoke con "Failed loading resource:".
#
# Por que hace falta ademas de scripts/check_import_artifacts_present.py: ese
# valida manifiestos, no el grafo de una escena. Aca importan dos casos que un
# grep de "ext_resource" sobre los .tscn NO ve:
#   1. Recursos binarios (DomeTerrace_baked.mesh y compania) que referencian
#      texturas desde sus materiales.
#   2. Materiales horneados que pasaron de tener la textura EMBEBIDA a
#      referenciarla por ruta (paso justo al cambiar SteelGratePlatform de
#      duplicate(true) a duplicate superficial, y rompio CI).
# Por eso recorre con ResourceLoader.get_dependencies(), que si ve ambos.
#
# Las variantes .etc2.stex salen como faltantes A PROPOSITO: el proyecto es GLES2
# y no se versionan (ver docs/engineering/CI_Asset_Strategy.md).
#
# Uso:
#   git ls-files > .git_tracked.txt
#   godot3-bin --no-window -s tools/check_scene_artifact_gaps.gd
#   rm .git_tracked.txt

func _init():
	var tracked := {}
	var f := File.new()
	if f.open("res://.git_tracked.txt", File.READ) == OK:
		while not f.eof_reached():
			var l: String = f.get_line().strip_edges()
			if l != "": tracked[l] = true
		f.close()
	var visited := {}
	_walk("res://core_v2/levels/interiors/Dome_Intro.tscn", visited)
	print("[t] recursos alcanzados: ", visited.size())
	var gaps := []
	var d := Directory.new()
	for path in visited.keys():
		var imp: String = path + ".import"
		if not d.file_exists(imp): continue
		for dest in _dests(imp):
			var rel: String = dest.substr(6)
			if not tracked.has(rel):
				gaps.append(path + "  ->  " + rel)
	print("[t] artefactos SIN trackear: ", gaps.size())
	for g in gaps: print("[t]   FALTA ", g)
	quit()
func _dests(imp: String) -> Array:
	var f := File.new()
	if f.open(imp, File.READ) != OK: return []
	var out := []
	while not f.eof_reached():
		var l: String = f.get_line().strip_edges()
		if l.begins_with("path=") or l.begins_with("path."):
			var parts: PoolStringArray = l.split("=")
			if parts.size() < 2: continue
			var v: String = parts[1].strip_edges().replace("\"", "")
			if v.begins_with("res://"): out.append(v)
	f.close()
	return out
func _walk(path: String, visited: Dictionary) -> void:
	if visited.has(path): return
	visited[path] = true
	for dep in ResourceLoader.get_dependencies(path):
		var p: String = dep
		var sep: int = p.find("::")
		if sep != -1: p = p.substr(sep + 2)
		if p.begins_with("res://"):
			var d := Directory.new()
			if d.file_exists(p): _walk(p, visited)
