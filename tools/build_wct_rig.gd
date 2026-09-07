extends SceneTree

# Genera walking_cargo_transporter_rig.tscn desde el modelo original.
# Anatomia del usuario: CUATRO articulaciones por pierna.
#   Pelvis (fija, unica): bloque central + cintura + collares + eje + tanque trasero
#   Hip   (eje 1, y=338):  primer femur = discos + anillos + plato/brazo
#   Knee  (eje 2, y=50):   primera rodilla invertida = alojamiento del cilindro + biela
#   Shin  (eje 3, y=-80):  segunda rodilla = gota + anillos + viga + riel
#   Foot  (tobillo y=-635): ski + ruedas, se nivela solo (cuarta articulacion)

const SRC := "res://core_v2/props/machinery/walking_cargo_transporter.tscn"
const DST := "res://core_v2/props/machinery/walking_cargo_transporter_rig.tscn"
# Pivotes medidos sobre la geometria (espacio mesh = local de LegsJoined):
#   eje 1 cadera  (y=338,  z=-37)   eje del disco (en la pelvis)
#   eje 2 rodilla (y=50,   z=287)   perno donde pivota biela+alojamiento
#   tobillo       (y=-635, z=-42)   eje entre canilla y ski
# La biela (el muslo) pivota en el perno: LA SEGUNDA ARTICULACION.
const HIP_YZ := Vector2(338.0, -37.0)        # eje 1: la cadera
const KNEE_YZ := Vector2(50.0, 287.0)        # eje 2: la primera rodilla invertida
const TEARDROP_YZ := Vector2(-80.0, -120.0)  # eje 3: la segunda rodilla
const ANKLE_YZ := Vector2(-635.0, -42.0)     # eje 4: el tobillo

var _parent: PoolIntArray

func _uf_find(a: int) -> int:
	while _parent[a] != a:
		_parent[a] = _parent[_parent[a]]
		a = _parent[a]
	return a

func _uf_union(a: int, b: int) -> void:
	var ra := _uf_find(a)
	var rb := _uf_find(b)
	if ra != rb:
		_parent[rb] = ra

func _init() -> void:
	var packed: PackedScene = load(SRC)
	assert(packed != null)
	var root: Node = packed.instance()
	root.name = "walking_cargo_transporter_rig"
	root.transform = Transform.IDENTITY
	root.set_script(load("res://core_v2/props/machinery/WalkingCargoTransporterRig.gd"))

	var mi: MeshInstance = null
	var stack := [root]
	while not stack.empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance:
			mi = n
			break
		for c in n.get_children():
			stack.push_back(c)
	assert(mi != null and mi.mesh != null)

	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PoolVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangs: PoolRealArray = arrays[Mesh.ARRAY_TANGENT]
	var uvs: PoolVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PoolIntArray = arrays[Mesh.ARRAY_INDEX]
	var tris := indices if not indices.empty() else _full_indices(len(verts))
	var ntris: int = tris.size() / 3
	var nv := verts.size()

	# clasificacion por triangulo (centroide), segun la anatomia del usuario:
	# pelvis fija unica (bloque central + cintura + collares + eje + tanque trasero);
	# hip = el primer femur (discos + anillos + plato/brazo);
	# knee = la primera rodilla invertida (el alojamiento, negro) + la biela;
	# shin = la viga + el riel; foot = el ski + las ruedas.
	var names := ["body", "pelvis", "hip_L", "hip_R", "knee_L", "knee_R", "shin_L", "shin_R", "foot_L", "foot_R"]
	var part_tris := {}
	for nm0 in names:
		part_tris[nm0] = []
	for t in range(ntris):
		var c := (verts[tris[t * 3]] + verts[tris[t * 3 + 1]] + verts[tris[t * 3 + 2]]) / 3.0
		var nm := ""
		if c.y > 560.0:
			nm = "body"  # plataforma y columna
		elif c.y < -560.0:
			nm = "foot_" + _side(c.x)  # ski, ruedas, eje de tobillo
		elif abs(c.x) <= 90.0 and c.y > 240.0 and c.y < 440.0 and c.z < -250.0 and c.z > -460.0:
			nm = "pelvis"  # la parte trasera de la pelvis (el tanque con el anillo)
		elif abs(c.x) <= 165.0 and c.y > 450.0 and c.y < 560.0 and c.z > -260.0 and c.z < 100.0:
			nm = "pelvis"  # los collares + el eje de las caderas
		elif abs(c.x) <= 131.0 and c.y > 395.0 and abs(c.z - HIP_YZ.y) <= 135.0:
			nm = "pelvis"  # el bloque central de la pelvis
		elif c.y > -170.0 and c.y < 20.0 and c.z > -220.0 and c.z < -30.0:
			nm = "shin_" + _side(c.x)  # la gota + anillos (la segunda rodilla)
		elif c.y > -610.0 and c.y < 20.0 and c.z > -280.0 and c.z < -10.0:
			nm = "shin_" + _side(c.x)  # la viga + el riel
		elif c.y > 40.0 and c.y < 260.0 and c.z > 220.0 and c.z < 440.0:
			# el corredor de la biela -> knee; el brazo del plato -> hip;
			# el resto del alojamiento -> knee (la primera rodilla invertida)
			if _dist_line_yz(c, KNEE_YZ, TEARDROP_YZ) < 60.0:
				nm = "knee_" + _side(c.x)  # la biela
			elif abs(c.x) > 345.0 and abs(c.x) <= 415.0:
				nm = "hip_" + _side(c.x)  # el brazo del plato (el primer femur)
			else:
				nm = "knee_" + _side(c.x)  # el alojamiento del cilindro
		elif _dist_line_yz(c, KNEE_YZ, TEARDROP_YZ) < 60.0 and c.y > TEARDROP_YZ.y - 30.0:
			nm = "knee_" + _side(c.x)  # la biela (entre el perno y la gota)
		else:
			nm = "hip_" + _side(c.x)  # los discos, anillos, el plato/brazo
		part_tris[nm].append(t)

	# el riel frontal baja hasta el tobillo: la parte bajo la gota viaja con
	# la canilla (corte y = TEARDROP_Y)
	for s in ["L", "R"]:
		var upper: Array = part_tris["hip_" + s]
		var stay := []
		var moved := []
		for t in upper:
			var cy := (verts[tris[t * 3]].y + verts[tris[t * 3 + 1]].y + verts[tris[t * 3 + 2]].y) / 3.0
			if cy < TEARDROP_YZ.y:
				moved.append(t)
			else:
				stay.append(t)
		if moved.size() > 0:
			print("riel %s: %d tris pasan de hip a shin (corte y=%.0f)" % [s, moved.size(), TEARDROP_YZ.y])
			part_tris["hip_" + s] = stay
			part_tris["shin_" + s] += moved
	for nm3 in names:
		print("%-8s: %5d tris" % [nm3, part_tris[nm3].size()])

	# pivotes: x por pieza (promedio), (y,z) medidos sobre la geometria
	var piv := {"body": Vector3.ZERO, "pelvis": Vector3.ZERO}
	for s in ["L", "R"]:
		piv["hip_" + s] = Vector3(_mean_x(verts, tris, part_tris, "hip_" + s), HIP_YZ.x, HIP_YZ.y)
		piv["knee_" + s] = Vector3(_mean_x(verts, tris, part_tris, "knee_" + s), KNEE_YZ.x, KNEE_YZ.y)
		piv["shin_" + s] = Vector3(_mean_x(verts, tris, part_tris, "shin_" + s), TEARDROP_YZ.x, TEARDROP_YZ.y)
		piv["foot_" + s] = Vector3(_mean_x(verts, tris, part_tris, "foot_" + s), ANKLE_YZ.x, ANKLE_YZ.y)
		print("pivotes %s: cadera=(%.0f, %.0f, %.0f) rodilla=(%.0f, %.0f, %.0f) tobillo=(%.0f, %.0f, %.0f)" % [
			s, piv["hip_" + s].x, piv["hip_" + s].y, piv["hip_" + s].z,
			piv["knee_" + s].x, piv["knee_" + s].y, piv["knee_" + s].z,
			piv["foot_" + s].x, piv["foot_" + s].y, piv["foot_" + s].z])

	var mat: Material = mi.get_surface_material(0)
	if mat == null:
		mat = mi.mesh.surface_get_material(0)

	# meshes por pieza: cada una se hornea alrededor del pivote de SU
	# articulacion (el mismo punto donde se coloca su nodo en la cadena).
	var meshes := {}
	for nm4 in names:
		if part_tris[nm4].size() == 0:
			print("AVISO: %s sin tris" % nm4)
			continue
		meshes[nm4] = _build_mesh(verts, norms, tangs, uvs, tris, part_tris[nm4], piv.get(nm4, Vector3.ZERO), mat)

	# armar la escena
	mi.get_parent().remove_child(mi)
	mi.queue_free()
	var legs := root.find_node("LegsJoined", true, false)
	assert(legs != null)
	var rig := Spatial.new()
	rig.name = "Rig"
	legs.add_child(rig)
	rig.owner = root
	var body := MeshInstance.new()
	body.name = "Body"
	body.mesh = meshes["body"]
	body.set_surface_material(0, mat)
	rig.add_child(body)
	body.owner = root
	var pelvis := MeshInstance.new()
	pelvis.name = "Pelvis"
	pelvis.mesh = meshes["pelvis"]
	pelvis.set_surface_material(0, mat)
	rig.add_child(pelvis)
	pelvis.owner = root
	for s2 in ["L", "R"]:
		var hip := MeshInstance.new()
		hip.name = "Hip" + s2
		hip.mesh = meshes["hip_" + s2]
		hip.set_surface_material(0, mat)
		hip.translation = piv["hip_" + s2]
		rig.add_child(hip)
		hip.owner = root
		var knee := MeshInstance.new()
		knee.name = "Knee" + s2
		knee.mesh = meshes["knee_" + s2]
		knee.set_surface_material(0, mat)
		knee.translation = piv["knee_" + s2] - piv["hip_" + s2]
		hip.add_child(knee)
		knee.owner = root
		var shin := MeshInstance.new()
		shin.name = "Shin" + s2
		shin.mesh = meshes["shin_" + s2]
		shin.set_surface_material(0, mat)
		shin.translation = piv["shin_" + s2] - piv["knee_" + s2]
		knee.add_child(shin)
		shin.owner = root
		var foot := MeshInstance.new()
		foot.name = "Foot" + s2
		foot.mesh = meshes["foot_" + s2]
		foot.set_surface_material(0, mat)
		foot.translation = piv["foot_" + s2] - piv["shin_" + s2]
		shin.add_child(foot)
		foot.owner = root

	var out := PackedScene.new()
	var err := out.pack(root)
	assert(err == OK)
	err = ResourceSaver.save(DST, out)
	assert(err == OK)
	print("escrito ", DST)
	quit(0)

func _dist_line_yz(p: Vector3, a: Vector2, b: Vector2) -> float:
	var pa := Vector2(p.y, p.z) - a
	var d := b - a
	return abs(pa.cross(d)) / d.length()

func _side(x: float) -> String:
	return "L" if x < 0.0 else "R"

func _full_indices(n: int) -> PoolIntArray:
	var idx := PoolIntArray()
	idx.resize(n)
	for i in range(n):
		idx[i] = i
	return idx

func _centroid_of(verts: PoolVector3Array, tris: PoolIntArray, ids: Array) -> Vector3:
	var acc := Vector3.ZERO
	for t in ids:
		acc += (verts[tris[t * 3]] + verts[tris[t * 3 + 1]] + verts[tris[t * 3 + 2]]) / 3.0
	return acc / max(1, ids.size())

func _mean_x(verts: PoolVector3Array, tris: PoolIntArray, part_tris: Dictionary, nm: String) -> float:
	var ids: Array = part_tris.get(nm, [])
	var seen := {}
	var acc := 0.0
	var n := 0
	for t in ids:
		for k in range(3):
			var vi: int = tris[t * 3 + k]
			if not seen.has(vi):
				seen[vi] = true
				acc += verts[vi].x
				n += 1
	return acc / max(1, n)

func _bbox_dist(a: Dictionary, b: Dictionary) -> float:
	var dx: float = max(max(a.lo.x - b.hi.x, b.lo.x - a.hi.x), 0.0)
	var dy: float = max(max(a.lo.y - b.hi.y, b.lo.y - a.hi.y), 0.0)
	var dz: float = max(max(a.lo.z - b.hi.z, b.lo.z - a.hi.z), 0.0)
	return sqrt(dx * dx + dy * dy + dz * dz)

func _build_mesh(verts: PoolVector3Array, norms: PoolVector3Array, tangs: PoolRealArray, uvs: PoolVector2Array, tris: PoolIntArray, tids: Array, pivot: Vector3, mat: Material) -> ArrayMesh:
	var used := {}
	for t in tids:
		for k in range(3):
			used[tris[t * 3 + k]] = true
	var remap := {}
	var nv := PoolVector3Array()
	var nn := PoolVector3Array()
	var nt := PoolRealArray()
	var nuv := PoolVector2Array()
	for vi in used:
		remap[vi] = nv.size()
		nv.append(verts[vi] - pivot)
		if norms.size() > 0:
			nn.append(norms[vi])
		if tangs.size() > 0:
			for k in range(4):
				nt.append(tangs[vi * 4 + k])
		if uvs.size() > 0:
			nuv.append(uvs[vi])
	var nidx := PoolIntArray()
	nidx.resize(tids.size() * 3)
	var w := 0
	for t in tids:
		for k in range(3):
			nidx[w] = remap[tris[t * 3 + k]]
			w += 1
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = nv
	if nn.size() > 0: arr[Mesh.ARRAY_NORMAL] = nn
	if nt.size() > 0: arr[Mesh.ARRAY_TANGENT] = nt
	if nuv.size() > 0: arr[Mesh.ARRAY_TEX_UV] = nuv
	arr[Mesh.ARRAY_INDEX] = nidx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m
