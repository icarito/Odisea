extends SceneTree

# Conteo de materiales/shaders unicos en el arbol de dependencias de una escena.
# Uso: godot3-bin --headless -s tools/count_scene_materials.gd -- res://core_v2/levels/interiors/Dome_Intro.tscn

var _seen_materials := {}
var _seen_shaders := {}
var _by_source := {}
var _scenes := {}

func _init() -> void:
	var args := OS.get_cmdline_args()
	var target := "res://core_v2/levels/interiors/Dome_Intro.tscn"
	for i in args.size():
		if args[i] == "--" and i + 1 < args.size():
			target = args[i + 1]
	print("[Count] target=", target)
	var t0 := OS.get_ticks_msec()
	var packed: PackedScene = load(target)
	if packed == null:
		printerr("[Count] no se pudo cargar ", target)
		quit(1)
		return
	var inst := packed.instance()
	_walk(inst, target)
	inst.free()
	var total_mat := _seen_materials.size()
	var total_shader := _seen_shaders.size()
	print("[Count] materiales_unicos=", total_mat, " shaders_unicos=", total_shader, " ms=", OS.get_ticks_msec() - t0)
	var sources := _by_source.keys()
	sources.sort()
	for s in sources:
		var m: Dictionary = _by_source[s]
		print("[Count] %s -> mats=%d shaders=%d" % [s, m.get("mats", 0), m.get("shaders", 0)])
	for sh in _seen_shaders.keys():
		print("[Count] shader=", sh)
	quit(0)

func _walk(node: Node, source: String) -> void:
	if node is GeometryInstance:
		var mats := []
		var gi := node as GeometryInstance
		if gi.material_override != null:
			mats.append(gi.material_override)
		if gi.material_overlay != null:
			mats.append(gi.material_overlay)
		if node is MeshInstance:
			var mi := node as MeshInstance
			for i in mi.get_surface_material_count():
				var m := mi.get_surface_material(i)
				if m != null:
					mats.append(m)
			if mi.mesh != null:
				for i in mi.mesh.get_surface_count():
					var m2 := mi.mesh.surface_get_material(i)
					if m2 != null:
						mats.append(m2)
		if node is CSGPrimitive and "material" in node:
			var m3: Material = node.get_material()
			if m3 != null:
				mats.append(m3)
		for m in mats:
			var key := _mat_key(m)
			if not _seen_materials.has(key):
				_seen_materials[key] = true
				if not _by_source.has(source):
					_by_source[source] = {"mats": 0, "shaders": 0}
				_by_source[source]["mats"] += 1
				var shader := _shader_of(m)
				if shader != "" and not _seen_shaders.has(shader):
					_seen_shaders[shader] = true
					_by_source[source]["shaders"] += 1
	for child in node.get_children():
		_walk(child, source)

func _mat_key(m: Material) -> String:
	return str(m.get_instance_id()) + ":" + m.resource_path + ":" + m.resource_name

func _shader_of(m: Material) -> String:
	if m is ShaderMaterial:
		var s: Shader = m.get_shader()
		if s != null:
			return s.resource_path if s.resource_path != "" else "(inline:" + str(s.get_instance_id()) + ")"
		return "(null_shader)"
	return "SpatialMaterial"
