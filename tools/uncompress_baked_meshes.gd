extends SceneTree

# Re-guarda los .mesh horneados SIN compresion de atributos de vertice.
#
# Las herramientas de bake llaman add_surface_from_arrays(primitive, arrays) sin pasar
# flags, asi que Godot aplica ARRAY_COMPRESS_DEFAULT: normales y tangentes en bytes con
# signo, y UV/UV2 en half float. El half float de atributos NO es del nucleo de OpenGL
# ES 2.0 (viene por OES_vertex_half_float), y en iOS esas mallas se ven con la
# iluminacion en bloques planos y sin lightmap, mientras que en Android y escritorio
# estan bien.
#
# Uso:
#   godot3-bin --path . -s tools/uncompress_baked_meshes.gd            # informe, no escribe
#   godot3-bin --path . -s tools/uncompress_baked_meshes.gd -- --write # aplica
#
# Solo toca las que tienen algun flag de compresion puesto; el resto las deja igual.

const DIRS := ["res://core_v2/levels/interiors"]

func _init():
	var write := false
	for arg in OS.get_cmdline_args():
		if arg == "--write":
			write = true

	var files := []
	for d in DIRS:
		_collect(d, files)
	files.sort()

	var touched := 0
	var skipped := 0
	for path in files:
		var mesh = load(path)
		if mesh == null or not (mesh is ArrayMesh):
			continue
		if not _is_compressed(mesh):
			skipped += 1
			continue
		touched += 1
		if not write:
			print("comprimida: %s (format=%d)" % [path.get_file(), mesh.surface_get_format(0)])
			continue
		var rebuilt := _rebuild(mesh)
		var err = ResourceSaver.save(path, rebuilt)
		if err != OK:
			printerr("ERROR guardando %s: %d" % [path, err])
		else:
			print("re-guardada: %-46s %d -> %d" % [
				path.get_file(), mesh.surface_get_format(0), rebuilt.surface_get_format(0)])

	print("---")
	print("%s | comprimidas=%d ya_limpias=%d" % ["ESCRITO" if write else "SOLO INFORME", touched, skipped])
	quit()


func _collect(dir_path: String, out: Array) -> void:
	var d = Directory.new()
	if d.open(dir_path) != OK:
		return
	d.list_dir_begin(true, true)
	var f = d.get_next()
	while f != "":
		var p = dir_path.plus_file(f)
		if d.current_is_dir():
			_collect(p, out)
		elif f.ends_with(".mesh"):
			out.append(p)
		f = d.get_next()
	d.list_dir_end()


func _is_compressed(mesh: ArrayMesh) -> bool:
	var mask = (
		ArrayMesh.ARRAY_COMPRESS_NORMAL
		| ArrayMesh.ARRAY_COMPRESS_TANGENT
		| ArrayMesh.ARRAY_COMPRESS_COLOR
		| ArrayMesh.ARRAY_COMPRESS_TEX_UV
		| ArrayMesh.ARRAY_COMPRESS_TEX_UV2
	)
	for i in range(mesh.get_surface_count()):
		if mesh.surface_get_format(i) & mask:
			return true
	return false


func _rebuild(source: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.resource_name = source.resource_name
	for i in range(source.get_surface_count()):
		# compress_flags = 0: los arrays salen tal cual entraron, sin cuantizar.
		out.add_surface_from_arrays(
			source.surface_get_primitive_type(i),
			source.surface_get_arrays(i),
			source.surface_get_blend_shape_arrays(i),
			0
		)
		out.surface_set_material(i, source.surface_get_material(i))
		var surface_name = source.surface_get_name(i)
		if surface_name != "":
			out.surface_set_name(i, surface_name)
	# El AABB horneado se recalcula solo desde los arrays; no se copia a mano.
	return out
