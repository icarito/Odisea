extends SceneTree

# Censo de programas de shader que exige una escena. Godot comparte un shader entre
# todos los SpatialMaterial que coinciden en su MaterialKey: no en los colores ni en
# las texturas, sino en QUE features y flags estan encendidos. Dos materiales que solo
# difieren en albedo comparten programa; uno que enciende un flag mas cuesta uno nuevo.
#
# Reconstruye esa llave leyendo las propiedades que participan de ella (ver
# SpatialMaterial::MaterialKey en scene/resources/material.h de Godot 3.6).

const SCENE := "res://core_v2/levels/interiors/Dome_Intro.tscn"

# Features: cuentan por si un slot esta habilitado, no por su valor.
const FEATURES := [
	"transparency", "emission_enabled", "normal_enabled", "rim_enabled",
	"clearcoat_enabled", "anisotropy_enabled", "ao_enabled", "depth_enabled",
	"subsurf_scatter_enabled", "transmission_enabled", "refraction_enabled",
	"detail_enabled",
]
# Enums y banderas que entran en la llave.
const KEYED := [
	"flags_transparent", "flags_unshaded", "flags_vertex_lighting", "flags_no_depth_test",
	"flags_use_point_size", "flags_world_triplanar", "flags_fixed_size",
	"flags_albedo_tex_force_srgb", "flags_do_not_receive_shadows",
	"flags_disable_ambient_light", "flags_ensure_correct_normals",
	"vertex_color_use_as_albedo", "vertex_color_is_srgb",
	"params_diffuse_mode", "params_specular_mode", "params_blend_mode",
	"params_cull_mode", "params_depth_draw_mode", "params_billboard_mode",
	"params_billboard_keep_scale", "params_grow", "params_use_alpha_scissor",
	"proximity_fade_enable", "distance_fade_mode",
	"uv1_triplanar", "uv2_triplanar", "ao_on_uv2", "emission_on_uv2",
	"emission_operator", "detail_blend_mode", "detail_uv_layer",
	"depth_deep_parallax", "async_mode",
]

var _sigs := {}
var _shaders := {}
var _seen := {}

func _init() -> void:
	var ps = load(SCENE)
	if ps == null:
		print("no pude cargar ", SCENE); quit(1); return
	var root = ps.instance(PackedScene.GEN_EDIT_STATE_DISABLED)
	_walk(root)
	_report()
	root.free()
	quit()

func _walk(n: Node) -> void:
	# Lo invisible no se dibuja y por lo tanto no compila nada: los _ZoneDebugMesh y
	# demas ayudas de depuracion no cuestan un programa aunque esten en el .tscn.
	if n is Spatial and not n.visible:
		return
	if n is GeometryInstance:
		_collect(n.material_override, n)
		if n is MeshInstance and n.mesh != null:
			for i in range(n.mesh.get_surface_count()):
				var m = n.get_surface_material(i)
				if m == null:
					m = n.mesh.surface_get_material(i)
				_collect(m, n)
		if n is CSGShape and n.material != null:
			_collect(n.material, n)
	for c in n.get_children():
		_walk(c)

func _collect(mat, owner_node: Node) -> void:
	if mat == null:
		return
	var id = mat.get_instance_id()
	if _seen.has(id):
		_bump(_seen[id], owner_node, mat)
		return
	var sig = ""
	if mat is SpatialMaterial:
		var parts = []
		for f in FEATURES:
			if _prop(mat, f):
				parts.append(f)
		for k in KEYED:
			var v = _prop(mat, k)
			if typeof(v) == TYPE_BOOL:
				if v:
					parts.append(k)
			elif v != null and int(v) != 0:
				parts.append("%s=%s" % [k, v])
		# Los slots de textura tambien cambian el shader (se declara el sampler).
		for t in ["albedo", "metallic", "roughness", "emission", "normal", "ao", "detail_albedo"]:
			if mat.get("%s_texture" % t) != null:
				parts.append("tex:" + t)
		parts.sort()
		sig = "Spatial{" + PoolStringArray(parts).join(",") + "}"
	elif mat is ShaderMaterial:
		var sh = mat.shader
		sig = "Shader{%s}" % [sh.resource_path if sh != null and sh.resource_path != "" else str(sh)]
	else:
		sig = "Otro{%s}" % mat.get_class()
	_seen[id] = sig
	_bump(sig, owner_node, mat)

func _bump(sig: String, owner_node: Node, mat) -> void:
	if not _sigs.has(sig):
		_sigs[sig] = {"count": 0, "mats": {}, "nodes": []}
	_sigs[sig]["count"] += 1
	_sigs[sig]["mats"][mat.get_instance_id()] = true
	if _sigs[sig]["nodes"].size() < 6:
		var where = String(owner_node.get_path()) if owner_node.is_inside_tree() else owner_node.name
		var rp = mat.resource_path
		_sigs[sig]["nodes"].append("%s <%s>" % [where, rp if rp != "" else "embebido"])

func _prop(mat, prop):
	return mat.get(prop)

func _report() -> void:
	var keys = _sigs.keys()
	keys.sort_custom(self, "_by_count")
	var uniq_mats = 0
	for k in keys:
		uniq_mats += _sigs[k]["mats"].size()
	print("=== %d combinaciones distintas (= programas), %d materiales, %d usos ===" % [
		keys.size(), uniq_mats, _total()])
	var singles = 0
	for k in keys:
		var d = _sigs[k]
		if d["mats"].size() == 1:
			singles += 1
		print("%3d usos  %2d mats  %s" % [d["count"], d["mats"].size(), k])
		for w in d["nodes"]:
			print("            %s" % w)
	print("--- combinaciones usadas por UN solo material: %d de %d" % [singles, keys.size()])

func _total() -> int:
	var t = 0
	for k in _sigs:
		t += _sigs[k]["count"]
	return t

func _by_count(a, b) -> bool:
	return _sigs[a]["count"] > _sigs[b]["count"]
