extends SceneTree

# Hornea la colision de cada chunk body de RingHub en UN compound de Box3D y
# reescribe la escena del body para que use CompoundChunkBodyV2 (una sola shape).
#
# Uso: tools/godot --no-window -s tools/bake_chunk_compounds.gd
#
# Convierte la geometria de cada CollisionShape hija al compound, en el espacio
# local del root del body (asi el chunk lo puede posicionar despues igual que
# antes):
#   BoxShape            -> hull de 8 esquinas (escala por eje del transform)
#   SphereShape         -> esfera
#   CapsuleShape        -> capsula (eje Z, altura = tramo medio, como el modulo)
#   CylinderShape       -> hull de 24 lados Y-alineado (mismo poligono que el modulo)
#   ConvexPolygonShape  -> hull
#   ConcavePolygonShape -> mesh (cada triangulo duplicado con las dos caras, como
#                          hace el modulo para emular el trimesh de doble cara)
#
# Los bytes van a <escena>_compound.res (CompoundBytesV2) y la escena del body se
# reescribe manteniendo el nombre del root y sus capas de colision.

const SECTOR_DIR := "res://core_v2/levels/interiors/"
const CHUNK_DIR := "res://core_v2/levels/chunks/ringhub/"
# Escenas fuente (originales con primitivas). El horneado reescribe los bodies
# finales en SECTOR_DIR/CHUNK_DIR, por eso la fuente no puede ser el destino.
const SRC_DIR := "res://core_v2/levels/chunks/compound_body_src/"
const BODY_SCRIPT := "res://core_v2/levels/chunks/CompoundChunkBodyV2.gd"
const BYTES_SCRIPT := "res://core_v2/levels/chunks/CompoundBytesV2.gd"
const FOOTSTEP_PROFILE := "res://core_v2/audio/footsteps/footstep_profile_scaffold_metal.tres"
const CYL_SEGMENTS := 24
# Mismo engrosado que el modulo para ConvexPolygonShape planos (placa de espesor
# cero): sin esto el hull de box3d rechaza la nube coplanar.
const LINEAR_SLOP := 0.005

func _init() -> void:
	call_deferred("_run")

func _glob(dir_path: String, pattern: String) -> Array:
	var out := []
	var d := Directory.new()
	if d.open(dir_path) != OK:
		return out
	d.list_dir_begin(true, true)
	var name := d.get_next()
	while name != "":
		if name.match(pattern):
			out.append(dir_path + name)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

func _targets() -> Array:
	var out := []
	# Las fuentes viven aparte: el horneado reescribe el body final, asi que leer
	# del destino no es idempotente (perderia la geometria original).
	for group in ["SpiralStairs", "HubSpokes", "SpiralWalkways"]:
		for src in _glob(SRC_DIR, "RingHub_%s_sector_*_body.tscn" % group):
			out.append({"src": src, "path": SECTOR_DIR + src.get_file(), "skip": [], "footstep": true})
	# El anillo de despertar omite Pod_26: ahi va el pod funcional, y el visual
	# mergeado ya lo dejo afuera (su blocked_slot = 37). Los anillos superiores no
	# bloquean ningun slot.
	for src in _glob(SRC_DIR, "RingHub_Criopods*_body.tscn"):
		var skip := []
		if src.get_file() == "RingHub_Criopods_body.tscn":
			skip = ["Pod_26"]
		out.append({"src": src, "path": CHUNK_DIR + src.get_file(), "skip": skip, "footstep": false})
	return out

func _find_static_body(node: Node) -> Node:
	var stack := [node]
	while not stack.empty():
		var n = stack.pop_back()
		if n is StaticBody:
			return n
		for c in n.get_children():
			stack.append(c)
	return null

# Un ConvexPolygonShape con demasiados puntos no entra en un hull de box3d
# (B3_MAX_HULL_VERTICES/FACES/EDGES = 128). En vez de perder la colision, se parte
# la nube en dos por su eje mas largo y se hornean dos hulls: la union cubre el
# original (con un pelo de sobre-aproximacion en el corte, inofensivo en estatica).
func _add_hull_split(comp: Box3DCompound, points: PoolVector3Array, xf: Transform, splits: Array, depth: int) -> void:
	var before: int = comp.get_child_count()
	comp.add_hull(points, xf)
	if comp.get_child_count() > before:
		return
	if points.size() < 8 or depth >= 4:
		splits.append("no se pudo hornear un hull de %d puntos" % points.size())
		return
	var aabb := AABB(points[0], Vector3())
	for p in points:
		aabb = aabb.expand(p)
	var axis := 0
	if aabb.size.y > aabb.size.x and aabb.size.y >= aabb.size.z:
		axis = 1
	elif aabb.size.z > aabb.size.x:
		axis = 2
	var mid: float = aabb.position[axis] + aabb.size[axis] * 0.5
	var lo := PoolVector3Array()
	var hi := PoolVector3Array()
	for p in points:
		if p[axis] <= mid:
			lo.append(p)
		else:
			hi.append(p)
	if lo.empty() or hi.empty():
		splits.append("no se pudo hornear un hull de %d puntos" % points.size())
		return
	_add_hull_split(comp, lo, xf, splits, depth + 1)
	_add_hull_split(comp, hi, xf, splits, depth + 1)
	splits.append("hull de %d puntos partido en 2" % points.size())

func _thicken_flat(points: PoolVector3Array) -> PoolVector3Array:
	var n := points.size()
	if n < 3:
		return PoolVector3Array()
	var base := points[0]
	var best := 0.0
	var far := -1
	for i in range(1, n):
		var d := (points[i] - base).length_squared()
		if d > best:
			best = d
			far = i
	if far < 0 or best <= 0.000001:
		return PoolVector3Array()
	var edge := (points[far] - base).normalized()
	best = 0.0
	var off := -1
	for i in range(1, n):
		var v := points[i] - base
		var d := (v - edge * edge.dot(v)).length_squared()
		if d > best:
			best = d
			off = i
	if off < 0 or best <= 0.000001:
		return PoolVector3Array()
	var normal := edge.cross(points[off] - base).normalized()
	if normal.length_squared() <= 0.000001:
		return PoolVector3Array()
	var offset := normal * (2.0 * LINEAR_SLOP)
	var out := PoolVector3Array()
	for p in points:
		out.append(p + offset)
	for p in points:
		out.append(p - offset)
	return out

func _rel_to_root(node: Node, root: Node) -> Transform:
	var xf: Transform = node.transform
	var p: Node = node.get_parent()
	while p != null and p != root:
		xf = p.transform * xf
		p = p.get_parent()
	return xf

func _xform_points(points: PoolVector3Array, xf: Transform) -> PoolVector3Array:
	var out := PoolVector3Array()
	out.resize(points.size())
	for i in range(points.size()):
		out.set(i, xf.xform(points[i]))
	return out

func _cylinder_points(height: float, radius: float) -> PoolVector3Array:
	# Mismo poligono que b3CreateCylinder(..., 24): Y-alineado, centrado.
	var pts := PoolVector3Array()
	for i in range(CYL_SEGMENTS):
		var a := TAU * float(i) / float(CYL_SEGMENTS)
		var x := cos(a) * radius
		var z := sin(a) * radius
		pts.append(Vector3(x, -height * 0.5, z))
		pts.append(Vector3(x, height * 0.5, z))
	return pts

func _double_faced(faces: PoolVector3Array) -> PoolVector3Array:
	var out := PoolVector3Array()
	for t in range(faces.size() / 3):
		var a := faces[t * 3 + 0]
		var b := faces[t * 3 + 1]
		var c := faces[t * 3 + 2]
		out.append(a)
		out.append(b)
		out.append(c)
		out.append(a)
		out.append(c)
		out.append(b)
	return out

func _add_shape(comp: Box3DCompound, shape: Shape, rel: Transform, unsupported: Array) -> void:
	var scale := rel.basis.get_scale()
	var rot := Transform(Basis(rel.basis.get_rotation_quat()), rel.origin)
	if shape is BoxShape:
		# Los transforms de props vienen con rotacion + escala no uniforme (y a veces
		# shear): descomponer como rot*scale no es exacto. Se hornean las 8 esquinas
		# transformadas por el transform COMPLETO.
		var corners := PoolVector3Array()
		var he: Vector3 = shape.extents
		for i in range(8):
			corners.append(Vector3(he.x if (i & 1) != 0 else -he.x, he.y if (i & 2) != 0 else -he.y, he.z if (i & 4) != 0 else -he.z))
		_add_hull_split(comp, _xform_points(corners, rel), Transform(), unsupported, 0)
	elif shape is SphereShape:
		comp.add_sphere(shape.radius * max(scale.x, max(scale.y, scale.z)), rot)
	elif shape is CapsuleShape:
		comp.add_capsule(shape.radius * max(scale.x, scale.z), shape.height * scale.y, rot)
	elif shape is CylinderShape:
		# Igual que la caja: los puntos del prisma por el transform completo.
		comp.add_hull(_xform_points(_cylinder_points(shape.height, shape.radius), rel))
	elif shape is ConvexPolygonShape:
		var pts := _xform_points(shape.points, rel)
		var before: int = comp.get_child_count()
		_add_hull_split(comp, pts, Transform(), unsupported, 0)
		if comp.get_child_count() == before:
			# placa plana: engrosar +-2*slop como hace el modulo
			var thick := _thicken_flat(pts)
			if not thick.empty():
				_add_hull_split(comp, thick, Transform(), unsupported, 1)
	elif shape is ConcavePolygonShape:
		comp.add_mesh(_double_faced(_xform_points(shape.faces, rel)))
	else:
		unsupported.append(shape.get_class())

func _bake_one(cfg: Dictionary) -> Dictionary:
	var packed: PackedScene = load(cfg["src"])
	if packed == null:
		return {"path": cfg["path"], "error": "no carga la fuente %s" % cfg["src"]}
	var root: Node = packed.instance()
	var body: Node = root
	if body is PhysicsBody:
		pass
	else:
		body = _find_static_body(root)
	if body == null:
		root.free()
		return {"path": cfg["path"], "error": "no encontre un StaticBody en la escena"}

	var comp := Box3DCompound.new()
	var unsupported := []
	var shapes := 0
	for child in body.get_children():
		if not (child is CollisionShape) or (child as CollisionShape).shape == null:
			continue
		if String(child.name) in cfg["skip"]:
			continue
		# Transform RELATIVO AL ROOT del body (no al StaticBody): en los anillos de
		# criopods el StaticBody cuelga de un Spatial con el offset del piso (y=4.5)
		# y hay que hornearlo. El root queda en identidad, asi que el chunk lo puede
		# posicionar despues igual que antes.
		_add_shape(comp, (child as CollisionShape).shape, _rel_to_root(child, root), unsupported)
		shapes += 1

	var children: int = comp.get_child_count()
	var bytes: PoolByteArray = comp.bake()
	var root_transform: Transform = root.transform
	var root_name: String = String(root.name)
	var layer: int = int(body.get("collision_layer"))
	var mask: int = int(body.get("collision_mask"))
	root.free()

	if bytes.size() <= 0 or children != shapes:
		return {"path": cfg["path"], "error": "bake incompleto: hijos=%d shapes=%d unsupported=%s" % [children, shapes, str(unsupported)]}
	# `children != shapes` NO alcanza para detectar colision perdida: una shape que
	# se partio en dos aporta un hijo de mas y tapa a otra que aporto cero. Asi
	# quedaron SpiralWalkways 05 y 06 con shapes=9 hijos=9 y el deck sin colision.
	# Las shapes que box3d rechaza se cuentan aparte.
	var perdidas := 0
	for entry in unsupported:
		if String(entry).begins_with("no se pudo hornear"):
			perdidas += 1
	if perdidas > 0:
		# Antes que perder colision, este chunk se queda SIN compound: se copia la
		# fuente tal cual (primitivas sueltas). Cuesta mas por frame que una sola
		# shape, pero se puede caminar encima, que es lo que importa.
		var src_file := File.new()
		if src_file.open(cfg["src"], File.READ) != OK:
			return {"path": cfg["path"], "error": "no pude leer la fuente para el fallback"}
		var src_text := src_file.get_as_text()
		src_file.close()
		var dst_file := File.new()
		if dst_file.open(cfg["path"], File.WRITE) != OK:
			return {"path": cfg["path"], "error": "no pude escribir el fallback sin compound"}
		dst_file.store_string(src_text)
		dst_file.close()
		return {"path": cfg["path"], "shapes": shapes, "children": children, "bytes": 0,
			"fallback": perdidas, "unsupported": unsupported}
	if root_transform != Transform():
		return {"path": cfg["path"], "error": "el root tiene transform (%s): el horneado asume identidad" % str(root_transform)}

	var res: Resource = load(BYTES_SCRIPT).new()
	res.bytes = bytes
	res.child_count = children
	res.source_scene = cfg["path"]
	res.unsupported_shapes = unsupported
	var res_path: String = String(cfg["path"]).get_basename() + "_compound.res"
	var err := ResourceSaver.save(res_path, res)
	if err != OK:
		return {"path": cfg["path"], "error": "no pude guardar %s (err %d)" % [res_path, err]}

	# Reescribir la escena del body como texto (evita PackedScene.pack y overrides).
	var lines := []
	lines.append("[gd_scene load_steps=%d format=2]" % (4 if cfg["footstep"] else 3))
	lines.append("")
	lines.append("[ext_resource path=\"%s\" type=\"Script\" id=1]" % BODY_SCRIPT)
	lines.append("[ext_resource path=\"%s\" type=\"Resource\" id=2]" % res_path)
	if cfg["footstep"]:
		lines.append("[ext_resource path=\"%s\" type=\"Resource\" id=3]" % FOOTSTEP_PROFILE)
	lines.append("")
	lines.append("[node name=\"%s\" type=\"StaticBody\"]" % root_name)
	lines.append("collision_layer = %d" % int(layer))
	lines.append("collision_mask = %d" % int(mask))
	lines.append("script = ExtResource( 1 )")
	lines.append("compound = ExtResource( 2 )")
	if cfg["footstep"]:
		lines.append("with_footstep_surface = true")
		lines.append("footstep_profile = ExtResource( 3 )")
	lines.append("")
	var f := File.new()
	if f.open(cfg["path"], File.WRITE) != OK:
		return {"path": cfg["path"], "error": "no pude reescribir la escena"}
	f.store_string(String("\n").join(lines))
	f.close()

	return {"path": cfg["path"], "shapes": shapes, "children": children, "bytes": bytes.size(),
			"res": res_path, "unsupported": unsupported}

func _run() -> void:
	var targets := _targets()
	print("BAKE_CHUNKS: %d escenas" % targets.size())
	var errors := 0
	for cfg in targets:
		var r := _bake_one(cfg)
		if r.has("error"):
			errors += 1
			print("  ERROR %s: %s" % [r["path"].get_file(), r["error"]])
		elif r.has("fallback"):
			print("  %-52s SIN COMPOUND: box3d rechazo %d shape(s), se deja con primitivas sueltas %s" % [
				r["path"].get_file(), r["fallback"], str(r["unsupported"])])
		else:
			print("  %-52s shapes=%2d hijos=%2d bytes=%6d -> %s%s" % [
				r["path"].get_file(), r["shapes"], r["children"], r["bytes"],
				r["res"].get_file(),
				("  unsupported=" + str(r["unsupported"])) if not r["unsupported"].empty() else ""])
	print("BAKE_CHUNKS: listo, errores=%d" % errors)
	quit(1 if errors > 0 else 0)
