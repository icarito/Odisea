extends SceneTree

# Genera walking_cargo_transporter_rig.tscn: parte el ArrayMesh fusionado en
# piezas rigidas (body + hip/knee/foot por pierna) con pivotes articulados.
# Reutiliza texturas, material y el subarbol de colisiones de la escena original.

const SRC := "res://core_v2/props/machinery/walking_cargo_transporter.tscn"
const DST := "res://core_v2/props/machinery/walking_cargo_transporter_rig.tscn"
const KNEE_Z_MIN := 330.0
const BODY_Y := 540.0
const FOOT_Y := -560.0
const SIDE_X := 120.0
const SHIN_Y := 60.0
const HIP_PIVOT_Y := 380.0
const HIP_PIVOT_Z := 280.0

func _init() -> void:
	var packed: PackedScene = load(SRC)
	assert(packed != null)
	var root: Node = packed.instance()

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

	# centroide por triangulo
	var cent := PoolVector3Array()
	cent.resize(ntris)
	for t in range(ntris):
		cent[t] = (verts[tris[t * 3]] + verts[tris[t * 3 + 1]] + verts[tris[t * 3 + 2]]) / 3.0

	# clasificacion
	var part := {}
	for t in range(ntris):
		var c := cent[t]
		var p := "body"
		if c.y > BODY_Y:
			p = "body"
		elif abs(c.x) <= SIDE_X:
			p = "body"
		else:
			var s := "L" if c.x < 0.0 else "R"
			if c.y < FOOT_Y:
				p = "foot_" + s
			elif c.z > KNEE_Z_MIN and c.y < 400.0:
				p = "knee_" + s
			elif c.y < SHIN_Y:
				p = "shin_" + s
			else:
				p = "thigh_" + s
		part[t] = p

	var names := ["body", "thigh_L", "shin_L", "knee_L", "foot_L", "thigh_R", "shin_R", "knee_R", "foot_R"]
	var counts := {}
	for t in range(ntris):
		counts[part[t]] = int(counts.get(part[t], 0)) + 1
	for nm in names:
		print("%-8s: %5d tris" % [nm, int(counts.get(nm, 0))])

	# pivotes
	var piv := {"body": Vector3.ZERO}
	for s in ["L", "R"]:
		var thigh_band := PoolIntArray()
		for t in range(ntris):
			if part[t] == "thigh_" + s and cent[t].y > 320.0:
				thigh_band.append(t)
		var hx := _mean_x(verts, tris, thigh_band)
		piv["thigh_" + s] = Vector3(hx, HIP_PIVOT_Y, HIP_PIVOT_Z)
		piv["knee_" + s] = _centroid(verts, tris, part, "knee_" + s)
		var fv := _verts_of(verts, tris, part, "foot_" + s)
		var fmax := fv[0].y
		for v in fv:
			fmax = max(fmax, v.y)
		piv["foot_" + s] = Vector3(_mean_x(verts, tris, _tri_ids(part, "foot_" + s)), fmax - 60.0, _mean_z(verts, tris, _tri_ids(part, "foot_" + s)))
	for k in piv:
		print("pivote %-8s (%9.2f, %9.2f, %9.2f)" % [k, piv[k].x, piv[k].y, piv[k].z])

	var mat: Material = mi.get_surface_material(0)
	if mat == null:
		mat = mi.mesh.surface_get_material(0)

	# construir meshes por pieza
	var meshes := {}
	for nm in names:
		if int(counts.get(nm, 0)) == 0:
			continue
		# la canilla comparte el pivote de la rodilla (giran juntas)
		var bake_pivot: Vector3 = piv["knee_" + _s_of(nm)] if nm.begins_with("shin_") else piv.get(nm, Vector3.ZERO)
		meshes[nm] = _build_mesh(verts, norms, tangs, uvs, tris, part, nm, bake_pivot, mat)

	# armar la escena nueva: quitar el MeshInstance fusionado, agregar el rig
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
	for s in ["L", "R"]:
		var hip := MeshInstance.new()
		hip.name = "Hip" + s
		hip.mesh = meshes["thigh_" + s]
		hip.set_surface_material(0, mat)
		hip.translation = piv["thigh_" + s]
		rig.add_child(hip)
		hip.owner = root
		var knee := MeshInstance.new()
		knee.name = "Knee" + s
		knee.mesh = meshes["knee_" + s]
		knee.set_surface_material(0, mat)
		knee.translation = piv["knee_" + s] - piv["thigh_" + s]
		hip.add_child(knee)
		knee.owner = root
		var shin := MeshInstance.new()
		shin.name = "Shin" + s
		shin.mesh = meshes["shin_" + s]
		shin.set_surface_material(0, mat)
		knee.add_child(shin)
		shin.owner = root
		var foot := MeshInstance.new()
		foot.name = "Foot" + s
		foot.mesh = meshes["foot_" + s]
		foot.set_surface_material(0, mat)
		foot.translation = piv["foot_" + s] - piv["knee_" + s]
		knee.add_child(foot)
		foot.owner = root

	var out := PackedScene.new()
	var err := out.pack(root)
	assert(err == OK)
	err = ResourceSaver.save(DST, out)
	assert(err == OK)
	print("escrito ", DST)
	quit(0)

func _s_of(nm: String) -> String:
	return "L" if nm.ends_with("_L") else "R"

func _full_indices(n: int) -> PoolIntArray:
	var idx := PoolIntArray()
	idx.resize(n)
	for i in range(n):
		idx[i] = i
	return idx

func _tri_ids(part: Dictionary, nm: String) -> PoolIntArray:
	var out := PoolIntArray()
	for t in part:
		if part[t] == nm:
			out.append(t)
	return out

func _verts_of(verts: PoolVector3Array, tris: PoolIntArray, part: Dictionary, nm: String) -> PoolVector3Array:
	var ids := _tri_ids(part, nm)
	var seen := {}
	var out := PoolVector3Array()
	for t in ids:
		for k in range(3):
			var vi: int = tris[t * 3 + k]
			if not seen.has(vi):
				seen[vi] = true
				out.append(verts[vi])
	return out

func _mean_x(verts: PoolVector3Array, tris: PoolIntArray, ids: PoolIntArray) -> float:
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

func _mean_z(verts: PoolVector3Array, tris: PoolIntArray, ids: PoolIntArray) -> float:
	var seen := {}
	var acc := 0.0
	var n := 0
	for t in ids:
		for k in range(3):
			var vi: int = tris[t * 3 + k]
			if not seen.has(vi):
				seen[vi] = true
				acc += verts[vi].z
				n += 1
	return acc / max(1, n)

func _centroid(verts: PoolVector3Array, tris: PoolIntArray, part: Dictionary, nm: String) -> Vector3:
	var vs := _verts_of(verts, tris, part, nm)
	var acc := Vector3.ZERO
	for v in vs:
		acc += v
	return acc / max(1, vs.size())

func _build_mesh(verts: PoolVector3Array, norms: PoolVector3Array, tangs: PoolRealArray, uvs: PoolVector2Array, tris: PoolIntArray, part: Dictionary, nm: String, pivot: Vector3, mat: Material) -> ArrayMesh:
	var used := {}
	var tids := _tri_ids(part, nm)
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
