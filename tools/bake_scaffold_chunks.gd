extends SceneTree

# bake_scaffold_chunks.gd — Hornea los chunks de andamio Transit-Run.
#
# Fuente de arte:   tools/scaffold_chunks/glb/<id>.glb  (Blender, scene_chunks.py)
# Fuente de medidas: core_v2/systems/scaffold/ScaffoldChunkRegistry.gd
#
# El GLB se lee en runtime con PackedSceneGLTF (la carpeta lleva .gdignore): no hay
# artefactos .import que trackear ni GLB dentro del pck. Por chunk produce:
#   <id>.mesh      malla estatica, una superficie por material
#   <id>_dyn.mesh  objetos `Dyn_*` (mamparo cortable, cable, carro): lugar de props dinamicos
#   <id>.tscn      Mesh + Dyn + Collision (cajas del REGISTRO, no de la malla) + Socket_* +
#                  metadata "sockets"
# Los materiales compartidos (materials/M_*.tres) solo se crean si faltan: se pueden afinar
# a mano en Godot y un rehorneado no los pisa.
#
# Run: tools/scaffold_chunks/build.sh   (o directo: godot --path . --no-window -s tools/bake_scaffold_chunks.gd)

const LaserGateScript := preload("res://core_v2/levels/bay_vertical/LaserGate.gd")
const GlooSpanScript := preload("res://core_v2/levels/bay_vertical/GlooSpan.gd")
const Registry := preload("res://core_v2/systems/scaffold/ScaffoldChunkRegistry.gd")
const Exporter := preload("res://tools/scaffold_chunks/export_registry.gd")
const SRC_DIR := "res://tools/scaffold_chunks/glb/"
const OUT_DIR := "res://core_v2/props/scaffold/chunks/"
const MAT_DIR := OUT_DIR + "materials/"
const DECOR_DIR := "res://core_v2/props/hull_underdeck/"
const DECOR := ["hull_bay", "terrace_underside", "hull_pylon"]
const DECK_THICKNESS := 0.3
const GRATE_MATERIAL := "res://textures/trenchbroom/steel_grate_platform.tres"
const GRATE_REPEAT_PER_METER := 1.35  # igual que SteelGratePlatform

var _materials := {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	Directory.new().make_dir_recursive(MAT_DIR)
	var m: Dictionary = Exporter.metrics()
	for id in Registry.chunk_ids():
		if not _bake(id, Registry.build_chunk(id, m)):
			quit(1)
			return
	Directory.new().make_dir_recursive(DECOR_DIR)
	for id in DECOR:
		if not _bake_decor(id):
			quit(1)
			return
	quit(0)


# Pieza de fondo (kit del entrecasco): solo malla, sin medidas de juego. El nivel que la usa
# decide donde va y si lleva colision.
func _bake_decor(id: String) -> bool:
	var src: Node = ClassDB.instance("PackedSceneGLTF").import_gltf_scene(
		ProjectSettings.globalize_path(SRC_DIR + id + ".glb"))
	if src == null:
		push_error("[bake_chunks] no se pudo leer %s.glb" % id)
		return false
	var surfaces := {}
	for mi in _all_meshes(src):
		for s in range(mi.mesh.get_surface_count()):
			var mat: Material = _shared_material(mi.mesh.surface_get_material(s))
			if not surfaces.has(mat.resource_path):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(mat)
				surfaces[mat.resource_path] = st
			surfaces[mat.resource_path].append_from(mi.mesh, s, _relative_transform(mi, src))
	src.free()
	var keys: Array = surfaces.keys()
	keys.sort()
	var mesh := ArrayMesh.new()
	for key in keys:
		surfaces[key].index()
		surfaces[key].commit(mesh)
	var path: String = DECOR_DIR + id + ".mesh"
	mesh.take_over_path(path)
	var ok: bool = ResourceSaver.save(path, mesh) == OK
	print("[bake_chunks] decor %s: %d superficies" % [id, mesh.get_surface_count()])
	return ok


func _bake(id: String, chunk: Dictionary) -> bool:
	var src: Node = ClassDB.instance("PackedSceneGLTF").import_gltf_scene(
		ProjectSettings.globalize_path(SRC_DIR + id + ".glb"))
	if src == null:
		push_error("[bake_chunks] no se pudo leer %s.glb (correr tools/scaffold_chunks/build.sh)" % id)
		return false
	var buckets := {"": {}, "_dyn": {}}
	for mi in _all_meshes(src):
		var part: Dictionary = buckets["_dyn"] if String(mi.name).begins_with("Dyn_") else buckets[""]
		for s in range(mi.mesh.get_surface_count()):
			var mat: Material = _shared_material(mi.mesh.surface_get_material(s))
			var key: String = mat.resource_path
			if not part.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(mat)
				part[key] = st
			part[key].append_from(mi.mesh, s, _relative_transform(mi, src))
	src.free()

	var root := Spatial.new()
	root.name = id
	for suffix in ["", "_dyn"]:
		var keys: Array = buckets[suffix].keys()
		if keys.empty():
			continue
		keys.sort()
		var mesh := ArrayMesh.new()
		for key in keys:
			buckets[suffix][key].index()
			buckets[suffix][key].commit(mesh)
		var path: String = OUT_DIR + id + suffix + ".mesh"
		mesh.take_over_path(path)
		if ResourceSaver.save(path, mesh) != OK:
			push_error("[bake_chunks] fallo guardando %s" % path)
			return false
		var mi := MeshInstance.new()
		mi.name = "Mesh" if suffix == "" else "Dyn"
		mi.mesh = mesh
		_adopt(root, mi)

	var body := StaticBody.new()
	body.name = "Collision"
	_adopt(root, body)
	for n in chunk["nodes"]:
		var profile: Array = n.get("roll_profile", [])
		if profile.empty():
			_add_box(root, body, "Col_" + str(n["id"]), n["position"], n["size"], float(n.get("rise", 0.0)), true)
			for side in n["rails"]:
				_add_rail(root, body, "Rail_%s_%s" % [str(n["id"]), "R" if side > 0 else "L"],
					n["position"], n["size"], float(n.get("rise", 0.0)), 0.0, int(side))
			continue
		# Pasarela peraltada: un segmento por entrada del perfil, girado sobre la linea central.
		var seg_len: float = n["size"].z / float(profile.size())
		for i in range(profile.size()):
			var z: float = n["position"].z - n["size"].z * 0.5 + seg_len * (float(i) + 0.5)
			_add_box(root, body, "Col_%s_%d" % [str(n["id"]), i], Vector3(n["position"].x, n["position"].y, z),
				Vector3(n["size"].x, n["size"].y, seg_len), 0.0, true, float(profile[i]))
			for side in n["rails"]:
				_add_rail(root, body, "Rail_%s_%d_%s" % [str(n["id"]), i, "R" if side > 0 else "L"],
					Vector3(n["position"].x, n["position"].y, z), Vector3(n["size"].x, n["size"].y, seg_len),
					0.0, float(profile[i]), int(side))
	for b in chunk["blockers"]:
		if bool(b["cuttable"]):
			# Mamparo cortable = LaserGate real: dibuja su panel, lo calienta con el laser
			# y al cortarse libera el paso. Su eje fino es X: se gira para que cierre +Z.
			var gate = LaserGateScript.new()
			gate.name = "Blocker_" + str(b["id"])
			gate.panel_size = Vector3(b["size"].z, b["size"].y, b["size"].x)
			gate.transform = Transform(Basis(Vector3.UP, PI * 0.5), b["position"])
			_adopt(root, gate)
			continue
		var blocker := StaticBody.new()
		blocker.name = "Blocker_" + str(b["id"])
		_adopt(root, blocker)
		_add_box(root, blocker, "Col", b["position"], b["size"], 0.0, false)
	for sp in chunk["spans"]:
		var span = GlooSpanScript.new()
		span.name = "Span_" + str(sp["id"])
		span.span_is_local = true
		span.span_from = sp["from"]
		span.span_to = sp["to"]
		span.span_height = 0.0
		span.bridge_width = Registry.WALKWAY_WIDTH - 0.3
		span.required_blobs = int(sp["required_blobs"])
		_adopt(root, span)

	var sockets := {"In_A": {"type": "A", "position": Vector3.ZERO}}
	sockets["Out_" + str(chunk["out_socket"])] = {"type": chunk["out_socket"],
		"position": Vector3(0.0, float(chunk["dy"]), Registry.CHUNK_LENGTH), "bank_deg": chunk["bank_deg"]}
	for side_type in chunk["side_outs"]:
		for n in chunk["nodes"]:
			if n["id"] == chunk["side_outs"][side_type]:
				sockets["Out_" + side_type] = {"type": side_type, "position": n["position"]}
	for socket_name in sockets:
		var marker := Position3D.new()
		marker.name = "Socket_" + socket_name
		marker.translation = sockets[socket_name]["position"]
		_adopt(root, marker)
	root.set_meta("sockets", sockets)
	root.set_meta("chunk_id", id)

	var packed := PackedScene.new()
	packed.pack(root)
	var ok: bool = ResourceSaver.save(OUT_DIR + id + ".tscn", packed) == OK
	print("[bake_chunks] %s: %d cajas, %d sockets, dyn=%s" % [id, chunk["nodes"].size(),
		sockets.size(), str(not buckets["_dyn"].empty())])
	root.free()
	return ok


# `position` es el centro de la superficie caminable (deck) o el centro de la caja (blocker).
# Una rampa sube `rise` a lo largo de +Z.
func _add_box(root: Node, body: Node, shape_name: String, position: Vector3, size: Vector3, rise: float,
		is_deck: bool, roll_deg: float = 0.0) -> void:
	var col := CollisionShape.new()
	col.name = shape_name
	var box := BoxShape.new()
	var basis := Basis(Vector3(0.0, 0.0, 1.0), deg2rad(roll_deg)) * Basis(Vector3.RIGHT, -atan2(rise, size.z))
	var thickness: float = DECK_THICKNESS if is_deck else size.y
	box.extents = Vector3(size.x, thickness, Vector2(size.z, rise).length()) * 0.5
	col.shape = box
	var origin: Vector3 = position - basis.y * (thickness * 0.5) if is_deck else position
	col.transform = Transform(basis, origin)
	body.add_child(col)
	col.owner = root


# Baranda: caja fina sobre el costado `side` de la plataforma, de RAIL_HEIGHT de alto. Sigue
# la pendiente de una rampa y el peralte de un segmento.
func _add_rail(root: Node, body: Node, shape_name: String, position: Vector3, size: Vector3, rise: float,
		roll_deg: float, side: int) -> void:
	var col := CollisionShape.new()
	col.name = shape_name
	var box := BoxShape.new()
	var basis := Basis(Vector3(0.0, 0.0, 1.0), deg2rad(roll_deg)) * Basis(Vector3.RIGHT, -atan2(rise, size.z))
	box.extents = Vector3(Registry.RAIL_THICKNESS, Registry.RAIL_HEIGHT, Vector2(size.z, rise).length()) * 0.5
	col.shape = box
	var offset := Vector3(float(side) * (size.x - Registry.RAIL_THICKNESS) * 0.5, Registry.RAIL_HEIGHT * 0.5, 0.0)
	col.transform = Transform(basis, position + basis.xform(offset))
	body.add_child(col)
	col.owner = root


func _adopt(root: Node, child: Node) -> void:
	root.add_child(child)
	child.owner = root


# Un .tres por nombre de material de Blender (sin sufijos .001), compartido por los 10 chunks.
func _shared_material(source: Material) -> Material:
	var mat_name: String = source.resource_name if source != null else "M_Default"
	while mat_name.length() > 4 and mat_name.substr(mat_name.length() - 4, 1) == "." \
			and mat_name.substr(mat_name.length() - 3).is_valid_integer():
		mat_name = mat_name.substr(0, mat_name.length() - 4)
	if not _materials.has(mat_name):
		var path: String = MAT_DIR + mat_name + ".tres"
		if not ResourceLoader.exists(path):
			var fresh: Material = _game_material(mat_name, source)
			fresh.resource_name = mat_name
			ResourceSaver.save(path, fresh)
		_materials[mat_name] = load(path)
	return _materials[mat_name]


# Material del JUEGO para cada nombre de Blender. Misma familia que el andamio existente
# (SteelGratePlatform): rejilla con alpha scissor, tubo oscuro, chapa. Nada por encima de
# ~0.6 de metallic: sin cielo ni ReflectionProbe el metal puro sale negro.
func _game_material(mat_name: String, source: Material) -> Material:
	match mat_name:
		"M_Grate":
			var g: SpatialMaterial = load(GRATE_MATERIAL).duplicate()
			g.flags_transparent = true
			g.params_use_alpha_scissor = true
			g.params_alpha_scissor_threshold = 0.46
			g.params_cull_mode = SpatialMaterial.CULL_DISABLED
			g.albedo_color = Color(0.66, 0.72, 0.78)
			g.metallic = 0.5
			g.roughness = 0.3
			g.metallic_specular = 0.9
			# Triplanar en coordenadas locales: las cajas de Blender no traen UV a escala.
			g.uv1_triplanar = true
			g.uv1_scale = Vector3(GRATE_REPEAT_PER_METER, GRATE_REPEAT_PER_METER, GRATE_REPEAT_PER_METER)
			return g
		"M_Frame":
			var f := SpatialMaterial.new()
			f.albedo_color = Color(0.27, 0.29, 0.32)
			f.metallic = 0.6
			f.roughness = 0.55
			f.metallic_specular = 0.5
			f.rim_enabled = true
			f.rim = 0.4
			f.rim_tint = 0.3
			return f
		"M_Hull":
			var h := SpatialMaterial.new()
			h.albedo_color = Color(0.20, 0.22, 0.25)
			h.metallic = 0.3
			h.roughness = 0.8
			return h
		"M_Lamp":
			var lamp := SpatialMaterial.new()
			lamp.albedo_color = Color(1.0, 0.9, 0.72)
			lamp.emission_enabled = true
			lamp.emission = Color(1.0, 0.82, 0.55)
			lamp.emission_energy = 2.5
			return lamp
		"M_Panel":
			var p := SpatialMaterial.new()
			p.albedo_color = Color(0.42, 0.46, 0.50)
			p.metallic = 0.45
			p.roughness = 0.5
			return p
	if source != null:
		return source.duplicate() as Material
	return SpatialMaterial.new()


func _all_meshes(node: Node) -> Array:
	var out := []
	if node is MeshInstance and node.mesh != null:
		out.append(node)
	for child in node.get_children():
		out += _all_meshes(child)
	return out


func _relative_transform(node: Node, ancestor: Node) -> Transform:
	var xf := Transform.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != ancestor:
		if cursor is Spatial:
			xf = (cursor as Spatial).transform * xf
		cursor = cursor.get_parent()
	return xf
