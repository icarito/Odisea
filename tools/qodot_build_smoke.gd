extends SceneTree

# qodot_build_smoke.gd — Construye todos los .map y falla si alguno no genera geometria.
#
# Existe por un modo de falla silencioso: si los 3 puntos de un plano estan en el
# winding contrario, el brush compila sin una sola queja pero su volumen queda vacio.
# Qodot dice "Build complete", el mapa carga, y no se ve nada. Asi estuvo
# maps/interior_a.map desde que se agrego.
#
# La unica forma de detectarlo es construir y contar: un mapa con brushes y cero
# MeshInstance esta roto.
#
# Run:  godot3-bin --no-window -s tools/qodot_build_smoke.gd
#       MAPS=res://maps/crio.map godot3-bin --no-window -s tools/qodot_build_smoke.gd

const MAPS_DIR := "res://maps"
const TIMEOUT_FRAMES := 2400

var _results := []
var _failures := []
var _building := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var maps := []
	var only := OS.get_environment("MAPS")
	if only != "":
		maps = Array(only.split(",", false))
	else:
		maps = _collect(MAPS_DIR)
		maps.sort()

	for map_path in maps:
		var built = _build(map_path)
		while built is GDScriptFunctionState and built.is_valid():
			built = yield(built, "completed")

	print("")
	print("%-46s %8s %8s" % ["mapa", "brushes", "mallas"])
	for r in _results:
		print("%-46s %8d %8d  %s" % [r["name"], r["brushes"], r["meshes"], r["verdict"]])

	if _failures.empty():
		print("\nqodot_build_smoke: OK (%d mapas)" % _results.size())
		quit(0)
	else:
		for f in _failures:
			printerr("  FALLA: ", f)
		printerr("\nqodot_build_smoke: %d mapas sin geometria" % _failures.size())
		quit(1)

# Los .map de maps/autosave/ son respaldos del editor, no assets: no se construyen.
func _collect(dir_path: String) -> Array:
	var out := []
	var d := Directory.new()
	if d.open(dir_path) != OK:
		return out
	d.list_dir_begin(true, true)
	var name := d.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if d.current_is_dir():
			if name != "autosave":
				out += _collect(full)
		elif name.ends_with(".map"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
	return out

func _build(map_path: String):
	var brushes := _count_brushes(map_path)

	var QodotMap = load("res://addons/qodot/src/nodes/qodot_map.gd")
	var node = QodotMap.new()
	node.name = "Smoke"
	get_root().add_child(node)
	node.set("map_file", map_path)
	node.verify_and_build()

	# `_is_building` es privado; la señal build_complete es el unico final fiable, y
	# esperar por ella hace que un mapa roto termine rapido en vez de agotar el timeout.
	node.connect("build_complete", self, "_on_build_complete", [], CONNECT_ONESHOT)
	_building = true
	var frames := 0
	while _building and frames < TIMEOUT_FRAMES:
		yield(self, "idle_frame")
		frames += 1
	if _building:
		_failures.append("%s: timeout, no termino de construir" % map_path)

	var meshes := _count_meshes(node)
	var verdict := "ok"
	if brushes > 0 and meshes == 0:
		verdict = "SIN GEOMETRIA"
		_failures.append("%s: %d brushes y 0 MeshInstance (winding invertido?)"
			% [map_path, brushes])
	elif brushes == 0:
		verdict = "sin brushes"

	_results.append({"name": map_path.replace("res://maps/", ""),
		"brushes": brushes, "meshes": meshes, "verdict": verdict})

	node.get_parent().remove_child(node)
	node.queue_free()
	yield(self, "idle_frame")

func _count_brushes(map_path: String) -> int:
	var f := File.new()
	if f.open(map_path, File.READ) != OK:
		return 0
	var text := f.get_as_text()
	f.close()
	# Un brush es un "{" anidado dentro del "{" de una entidad.
	var depth := 0
	var count := 0
	for line in text.split("\n"):
		var s: String = line.strip_edges()
		if s.begins_with("//"):
			continue
		if s == "{":
			depth += 1
			if depth == 2:
				count += 1
		elif s == "}":
			depth -= 1
	return count

func _on_build_complete() -> void:
	_building = false

func _count_meshes(node: Node) -> int:
	var n := 0
	if node is MeshInstance:
		n += 1
	for c in node.get_children():
		n += _count_meshes(c)
	return n
