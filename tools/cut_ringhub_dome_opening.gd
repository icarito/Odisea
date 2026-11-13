extends SceneTree

# cut_ringhub_dome_opening.gd — Recorta una BOCA DE ESCLUSA en la cascara del
# domo de RingHub y escribe un producto nuevo (no toca la fuente horneada).
#
# Por que existe: el shell es un hemisferio low-poly (16 radiales x 8 anillos =
# 240 tris, r=35) horneado por tools/bake_dome_interior_lowpoly.gd desde un GLB.
# La fuente no tiene aberturas y las facetas miden 22.5 grados: borrar por
# centroide abriria un hueco de ~13 m. Este tool hace clipping EXACTO de cada
# triangulo contra una caja orientada (Sutherland-Hodgman), asi la boca mide
# exactamente lo pedido.
#
# CLAVE — lightmap: RingHub tiene UN solo bake (RingHub.lmbake) y el shell entra
# con use_in_baked_light + UV2. Si se regenerara la malla desde el GLB, el
# lightmap_unwrap cambiaria TODOS los UV2 y el bake quedaria desalineado. Aca se
# corta el PRODUCTO ya horneado y se PRESERVAN e INTERPOLAN UV1/UV2/normales, de
# modo que los vertices que quedan conservan su texel del lightmap.
#
# Salidas nuevas (RingHub_Level.tscn apunta a ellas):
#   core_v2/levels/interiors/DomeInteriorLowPoly_breach.mesh
#   core_v2/levels/interiors/DomeInteriorLowPoly_breach.shape
# La fuente DomeInteriorLowPoly_baked.* queda intacta: rehornear el shell no
# pierde el corte; este tool se vuelve a correr despues.
#
# Run: tools/godot --path . --no-window -s tools/cut_ringhub_dome_opening.gd
#   ODISEA_BAKE_SOURCE / ODISEA_BAKE_PREFIX sobreescriben las rutas.

const SRC_MESH := "res://core_v2/levels/interiors/DomeInteriorLowPoly_baked.mesh"
const SRC_SHAPE := "res://core_v2/levels/interiors/DomeInteriorLowPoly_baked.shape"
const OUT_MESH := "res://core_v2/levels/interiors/DomeInteriorLowPoly_breach.mesh"
const OUT_SHAPE := "res://core_v2/levels/interiors/DomeInteriorLowPoly_breach.shape"

# Boca de esclusa, alineada con Hub/PedestalMachineBay (world 31.8, 0, 3.2).
const AZIMUTH_DEG := 5.75        # atan2(3.2, 31.8)
const OPENING_WIDTH := 5.0       # tangencial (a lo largo de la pared)
const OPENING_HEIGHT := 3.4      # vertical desde el piso
const OPENING_Y_BASE := -0.15    # arranca bajo el piso para no dejar rebaba
const OPENING_RADIAL_MIN := 29.0 # radio interior de la caja de corte
const OPENING_RADIAL_MAX := 41.0 # radio exterior (atraviesa el muro r=35)

# Un vertice con sus atributos para poder interpolar al recortar.
class V:
	var p: Vector3
	var n: Vector3
	var uv: Vector2
	var uv2: Vector2
	func _init(p_: Vector3, n_: Vector3, uv_: Vector2, uv2_: Vector2) -> void:
		p = p_; n = n_; uv = uv_; uv2 = uv2_
	func lerp_to(o: V, t: float) -> V:
		return V.new(p.linear_interpolate(o.p, t), n.linear_interpolate(o.n, t),
			uv.linear_interpolate(o.uv, t), uv2.linear_interpolate(o.uv2, t))

var _axis_r := Vector3.RIGHT   # radial (hacia afuera)
var _axis_t := Vector3.FORWARD # tangencial
var _kept := 0
var _cut := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var src_mesh: ArrayMesh = load(SRC_MESH)
	if src_mesh == null:
		push_error("[cut_dome] no carga %s" % SRC_MESH); quit(1); return
	if src_mesh.get_surface_count() != 1:
		push_error("[cut_dome] se esperaba 1 superficie, hay %d" % src_mesh.get_surface_count()); quit(1); return

	var rad := deg2rad(AZIMUTH_DEG)
	_axis_r = Vector3(cos(rad), 0.0, sin(rad))
	_axis_t = Vector3(-sin(rad), 0.0, cos(rad))

	var arr: Array = src_mesh.surface_get_arrays(0)
	var verts: PoolVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PoolVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uvs: PoolVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var uv2s: PoolVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var indices: PoolIntArray = arr[Mesh.ARRAY_INDEX]
	if indices.empty():
		push_error("[cut_dome] la superficie no tiene indices"); quit(1); return
	if uv2s.size() != verts.size():
		push_error("[cut_dome] UV2 ausente/incompleto: %d vs %d" % [uv2s.size(), verts.size()]); quit(1); return

	var out_verts: Array = []   # de V
	var out_indices := PoolIntArray()
	var hit_count := 0

	var tri_count := indices.size() / 3
	for t in range(tri_count):
		var tri := [
			_mk(verts, normals, uvs, uv2s, indices[t * 3 + 0]),
			_mk(verts, normals, uvs, uv2s, indices[t * 3 + 1]),
			_mk(verts, normals, uvs, uv2s, indices[t * 3 + 2]),
		]
		var res: Dictionary = _subtract_box(tri)
		var outside: Array = res["outside"]
		if bool(res["hit"]):
			hit_count += 1
		if not bool(res["hit"]):
			_kept += 1
			for v in tri:
				out_indices.append(out_verts.size())
				out_verts.append(v)
		else:
			_cut += 1
			for poly in outside:
				_emit_polygon(poly, out_verts, out_indices)

	if hit_count == 0:
		push_error("[cut_dome] la caja no intersecta ningun triangulo: revisar azimut/medidas"); quit(1); return

	var out := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat: Material = src_mesh.surface_get_material(0)
	if mat != null:
		st.set_material(mat)
	for v in out_verts:
		st.add_normal(v.n)
		st.add_uv(v.uv)
		st.add_uv2(v.uv2)
		st.add_vertex(v.p)
	st.index()
	var committed: ArrayMesh = st.commit()
	if committed == null or committed.get_surface_count() == 0:
		push_error("[cut_dome] commit vacio"); quit(1); return
	out = committed

	out.take_over_path(OUT_MESH)
	var err := ResourceSaver.save(OUT_MESH, out)
	if err != OK:
		push_error("[cut_dome] fallo guardando mesh: %s" % err); quit(1); return

	var shape: ConcavePolygonShape = out.create_trimesh_shape()
	shape.take_over_path(OUT_SHAPE)
	err = ResourceSaver.save(OUT_SHAPE, shape)
	if err != OK:
		push_error("[cut_dome] fallo guardando shape: %s" % err); quit(1); return

	var faces := shape.get_faces().size() / 3
	print("[cut_dome] OK azimut=%.2fgr ancho=%.2f alto=%.2f | tri fuente=%d intersectados=%d enteros_fuera=%d | salida tri=%d caras_colision=%d uv2=%s" % [
		AZIMUTH_DEG, OPENING_WIDTH, OPENING_HEIGHT, tri_count, hit_count, _kept,
		out_verts.size() / 3, faces,
		"si" if out.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2 else "NO"])
	quit(0)


func _mk(verts, normals, uvs, uv2s, i: int) -> V:
	return V.new(verts[i], normals[i], uvs[i], uv2s[i])


# Resta la caja (convexa) del triangulo. Devuelve {outside: [poligonos],
# hit: bool}. `hit` es true si el triangulo intersecta la caja (su parte
# interior no es vacia), aunque el centroide caiga fuera de la caja.
func _subtract_box(tri: Array) -> Dictionary:
	var remaining: Array = [tri]
	var result: Array = []
	# 6 medias-espacios: cada uno "afuera" de una cara de la caja.
	for spec in _planes():
		var next_remaining: Array = []
		for poly in remaining:
			var outside_poly: Array = _clip_poly(poly, spec, true)
			var inside_poly: Array = _clip_poly(poly, spec, false)
			if outside_poly.size() >= 3:
				result.append(outside_poly)
			if inside_poly.size() >= 3:
				next_remaining.append(inside_poly)
		remaining = next_remaining
		if remaining.empty():
			break
	# `remaining` = triangulo ∩ caja. Si queda algo, hubo interseccion.
	var hit := false
	for poly in remaining:
		if poly.size() >= 3:
			hit = true
			break
	return {"outside": result, "hit": hit}


# Las 6 caras de la caja como [tipo, limite, invertir]. `_signed` siempre
# devuelve negativo para el lado "afuera" de la caja.
func _planes() -> Array:
	return [
		[0, OPENING_RADIAL_MIN, false],
		[0, OPENING_RADIAL_MAX, true],
		[1, -OPENING_WIDTH * 0.5, false],
		[1, OPENING_WIDTH * 0.5, true],
		[2, OPENING_Y_BASE, false],
		[2, OPENING_Y_BASE + OPENING_HEIGHT, true],
	]


func _signed(p: Vector3, spec: Array) -> float:
	var kind: int = spec[0]
	var limit: float = spec[1]
	var invert: bool = spec[2]
	var v := 0.0
	if kind == 0:
		v = p.dot(_axis_r)
	elif kind == 1:
		v = p.dot(_axis_t)
	else:
		v = p.y
	return (limit - v) if invert else (v - limit)


# Recorta el poligono dejando el lado "afuera" (keep_negative=true) o "adentro".
func _clip_poly(poly: Array, spec: Array, keep_negative: bool) -> Array:
	var out: Array = []
	var n := poly.size()
	for i in range(n):
		var cur: V = poly[i]
		var nxt: V = poly[(i + 1) % n]
		var dc := _signed(cur.p, spec)
		var dn := _signed(nxt.p, spec)
		var cur_in := (dc < 0.0) if keep_negative else (dc >= 0.0)
		var nxt_in := (dn < 0.0) if keep_negative else (dn >= 0.0)
		if cur_in:
			out.append(cur)
		if cur_in != nxt_in:
			var denom := dc - dn
			if abs(denom) > 0.0000001:
				var t := dc / denom
				out.append(cur.lerp_to(nxt, t))
	return out


func _emit_polygon(poly: Array, out_verts: Array, out_indices: PoolIntArray) -> void:
	if poly.size() < 3:
		return
	# Fan de triangulos desde el primer vertice.
	for i in range(1, poly.size() - 1):
		var a: V = poly[0]
		var b: V = poly[i]
		var c: V = poly[i + 1]
		var area := (b.p - a.p).cross(c.p - a.p).length()
		if area < 0.000001:
			continue
		for v in [a, b, c]:
			out_indices.append(out_verts.size())
			out_verts.append(v)
