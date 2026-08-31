extends SceneTree

# Parche one-off: vertex_color_use_as_albedo=false en los materiales horneados
# de caneria. COLOR guarda el eje del tramo (use_baked_axis del shader coolant);
# con el flag del kit ese COLOR multiplica el albedo del material plano.
# Uso: godot3-bin --headless -s tools/fix_baked_mat_vertex_color.gd

const DIR := "res://core_v2/levels/interiors/"

func _init() -> void:
	var fixed := 0
	var skipped := 0
	var files := _list_dir(DIR)
	for f in files:
		if not f.ends_with(".material"):
			continue
		var path: String = DIR + f
		var m: Material = load(path)
		if m == null or not (m is SpatialMaterial):
			continue
		var sm := m as SpatialMaterial
		if not sm.vertex_color_use_as_albedo:
			skipped += 1
			continue
		sm.vertex_color_use_as_albedo = false
		var err: int = ResourceSaver.save(path, sm)
		if err == OK:
			fixed += 1
			print("FIXED ", f)
		else:
			print("ERROR ", f, " code=", err)
	print("resumen: fixed=", fixed, " ya-limpios=", skipped)
	quit()

func _list_dir(dir_path: String) -> Array:
	var out := []
	var d := Directory.new()
	if d.open(dir_path) != OK:
		return out
	d.list_dir_begin(true, true)
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir():
			out.append(f)
		f = d.get_next()
	d.list_dir_end()
	return out
