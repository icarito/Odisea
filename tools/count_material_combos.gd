extends SceneTree

# Cuenta combinaciones distintas de features de SpatialMaterial (≈ programas GL)
# y shaders custom en el arbol de dependencias de una escena.

var _combos := {}
var _mats := {}

func _init() -> void:
	var args := OS.get_cmdline_args()
	var target := "res://core_v2/levels/interiors/Dome_Intro.tscn"
	for i in args.size():
		if args[i] == "--" and i + 1 < args.size():
			target = args[i + 1]
	var packed: PackedScene = load(target)
	if packed == null:
		quit(1)
		return
	var inst := packed.instance()
	_walk(inst)
	inst.free()
	print("[Combo] materiales_unicos=", _mats.size(), " combos_de_programa=", _combos.size())
	var keys := _combos.keys()
	keys.sort()
	for k in keys:
		print("[Combo] x", _combos[k], "  ", k)
	quit(0)

func _walk(node: Node) -> void:
	if node is MeshInstance:
		var mi := node as MeshInstance
		var mats := []
		for i in mi.get_surface_material_count():
			var m := mi.get_surface_material(i)
			if m != null:
				mats.append(m)
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m2 := mi.mesh.surface_get_material(i)
				if m2 != null:
					mats.append(m2)
		for m in mats:
			var key := _mat_key(m)
			if not _mats.has(key):
				_mats[key] = m
				var combo := _combo_of(m)
				_combos[combo] = int(_combos.get(combo, 0)) + 1
	for child in node.get_children():
		_walk(child)

func _mat_key(m: Material) -> String:
	return str(m.get_instance_id())

func _combo_of(m: Material) -> String:
	if m is ShaderMaterial:
		var s: Shader = m.get_shader()
		var path := "(inline)"
		if s != null and s.resource_path != "":
			path = s.resource_path.get_file()
		return "ShaderMaterial:" + path
	var sm := m as SpatialMaterial
	var flags := []
	if sm.get_feature(0): flags.append("albedo_tex") # FEATURE_ALBEDO_TEXTURE
	if sm.get_feature(1): flags.append("transparency")
	if sm.get_feature(2): flags.append("alpha_scissor")
	if sm.get_feature(3): flags.append("flowmap") # unused, keep numbering stable
	if sm.get_feature(4): flags.append("normal")
	if sm.get_feature(5): flags.append("emission")
	if sm.get_feature(6): flags.append("refraction")
	if sm.get_feature(7): flags.append("detail")
	if sm.get_feature(8): flags.append("uv2_triplanar")
	if sm.get_feature(9): flags.append("clearcoat")
	if sm.get_feature(10): flags.append("anisotropy")
	if sm.get_feature(11): flags.append("ao")
	if sm.get_feature(12): flags.append("depth")
	if sm.get_feature(13): flags.append("rim")
	if sm.get_feature(14): flags.append("heightmap")
	if sm.get_feature(15): flags.append("subsurf_scatter")
	if sm.get_feature(16): flags.append("distance_fade")
	flags.append("blend_" + str(sm.get_blend_mode()))
	flags.append("spec_" + str(sm.get_specular_mode()))
	flags.append("diff_" + str(sm.get_diffuse_mode()))
	flags.append("billboard_" + str(sm.get_billboard_mode()))
	flags.append("vertex_color_" + str(sm.get_flag(0))) # FLAG_USE_POINT_SIZE? aproximacion
	if sm.get_flag(2): flags.append("uv1_triplanar")
	flags.append("vertex_shading_" + str(sm.get_flag(3)))
	return "Spatial[" + ",".join(flags) + "]"
