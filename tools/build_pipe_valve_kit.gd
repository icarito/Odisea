extends SceneTree

# build_pipe_valve_kit.gd — parte la valvula del kit en CUERPO + VOLANTE.
#
# El kit trae la valvula como una sola malla, pero PipeValve.gd anima el volante
# (`_wheel.rotation.z`). Las variantes valve_small_1 y valve_small_2 tienen la MISMA
# topologia (3974 verts) con el volante corrido: los vertices que difieren entre las
# dos SON el volante. Eso da la particion sin tener que adivinarla, y ademas el campo
# de desplazamiento da el eje de giro y el pivote.
#
# Salida: core_v2/props/pipe/kit/PipeValveKit_{body,wheel}.mesh
# Run: godot3-bin --path . --no-window -s tools/build_pipe_valve_kit.gd

const KIT := "res://assets/models/Modular Pipes/1k/modular_pipes_1k.gltf"
const SALIDA := "res://core_v2/props/pipe/kit/"
const UMBRAL := 0.002

var _material: Material = null
# Franja canonica del atlas (isla del recto de 200cm, igual criterio que
# PipeRoute): el cuerpo de la valvula muestrea ahi para coincidir con los tubos.
var _isla_c: Rect2 = Rect2()
const _PERIODO_M := 2.0
const _ESCALA_DOMO := 4.0


func _init() -> void:
	var raiz: Node = load(KIT).instance()
	var m1: Mesh = _buscar(raiz, "pipe_valve_small_1_metal")
	var m2: Mesh = _buscar(raiz, "pipe_valve_small_2_metal")
	if m1 == null or m2 == null:
		printerr("VK no encuentro las dos variantes")
		quit(1)
		return

	_material = m1.surface_get_material(0)

	# Isla canonica: la del recto mas largo del kit, la misma franja que usan los
	# rectos de PipeRoute para su textura continua.
	var recto_ref: Mesh = _buscar(raiz, "pipe_200cm_metal")
	if recto_ref != null:
		var uvs_ref = recto_ref.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		if uvs_ref_valido(uvs_ref):
			var mn: Vector2 = uvs_ref[0]
			var mx: Vector2 = uvs_ref[0]
			for q in uvs_ref:
				mn = Vector2(min(mn.x, q.x), min(mn.y, q.y))
				mx = Vector2(max(mx.x, q.x), max(mx.y, q.y))
			_isla_c = Rect2(mn, mx - mn)

	var a1: Array = m1.surface_get_arrays(0)
	var a2: Array = m2.surface_get_arrays(0)
	var v1: PoolVector3Array = a1[Mesh.ARRAY_VERTEX]
	var v2: PoolVector3Array = a2[Mesh.ARRAY_VERTEX]
	if v1.size() != v2.size():
		printerr("VK las variantes no comparten topologia")
		quit(1)
		return

	var mueve := {}
	var centro := Vector3.ZERO
	var n := 0
	for i in range(v1.size()):
		if (v1[i] - v2[i]).length() > UMBRAL:
			mueve[i] = true
			centro += v1[i]
			n += 1
	if n == 0:
		printerr("VK las dos variantes son iguales")
		quit(1)
		return
	centro /= n

	# Eje de giro: el desplazamiento de una rotacion es perpendicular al eje, asi que
	# el eje es la direccion con MENOS varianza de desplazamiento. Se toma el producto
	# cruz de dos desplazamientos bien separados.
	var eje := Vector3.ZERO
	var claves: Array = mueve.keys()
	for i in range(0, claves.size() - 1, max(claves.size() / 32, 1)):
		var ia: int = claves[i]
		var ib: int = claves[(i + claves.size() / 2) % claves.size()]
		var da: Vector3 = v2[ia] - v1[ia]
		var db: Vector3 = v2[ib] - v1[ib]
		var c: Vector3 = da.cross(db)
		if c.length() > 0.0001:
			if eje.dot(c) < 0.0:
				c = -c
			eje += c
	eje = eje.normalized() if eje.length() > 0.0001 else Vector3(0, 1, 0)

	print("VK volante: %d de %d verts | centro=(%.3f, %.3f, %.3f) | eje=(%.2f, %.2f, %.2f)" % [
		n, v1.size(), centro.x, centro.y, centro.z, eje.x, eje.y, eje.z])

	var cuerpo := _particion(a1, mueve, false, Vector3.ZERO)
	var volante := _remap_isla(_particion(a1, mueve, true, centro))
	var e1 = ResourceSaver.save(SALIDA + "PipeValveKit_body.mesh", cuerpo)
	var e2 = ResourceSaver.save(SALIDA + "PipeValveKit_wheel.mesh", volante)
	print("VK cuerpo=%d verts (err %d) | volante=%d verts (err %d)" % [
		cuerpo.surface_get_array_len(0), e1, volante.surface_get_array_len(0), e2])
	print("VK pivote_local = Vector3(%.4f, %.4f, %.4f)" % [centro.x, centro.y, centro.z])
	raiz.free()
	quit(0)


# Sub-malla con los triangulos cuyos vertices caen (o no) en el conjunto del volante.
# El volante se recentra en su pivote para que rotarlo por el nodo funcione.
static func uvs_ref_valido(uvs) -> bool:
	return uvs != null and uvs.size() > 0


# Remapea las UV de una sub-malla a la franja canonica (isla del recto 200cm),
# preservando su layout autorado. El volante conserva las UVs de fabrica si no
# hay franja disponible.
func _remap_isla(m: ArrayMesh) -> ArrayMesh:
	var isp := _isla_uv(m)
	if isp.size.x <= 0.0 or isp.size.y <= 0.0 or _isla_c.size.x <= 0.0:
		return m
	var esc: float = min(_isla_c.size.x / isp.size.x, _isla_c.size.y / isp.size.y)
	var tam := isp.size * esc
	var arrays: Array = m.surface_get_arrays(0)
	var uvs := PoolVector2Array()
	for uv in arrays[Mesh.ARRAY_TEX_UV]:
		uvs.append(_isla_c.position + (_isla_c.size - tam) * 0.5 + (uv - isp.position) * esc)
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var nueva := ArrayMesh.new()
	nueva.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	nueva.surface_set_material(0, m.surface_get_material(0))
	return nueva


func _isla_uv(m: Mesh) -> Rect2:
	var uvs = m.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	if uvs == null or uvs.size() == 0:
		return Rect2()
	var mn: Vector2 = uvs[0]
	var mx: Vector2 = uvs[0]
	for q in uvs:
		mn = Vector2(min(mn.x, q.x), min(mn.y, q.y))
		mx = Vector2(max(mx.x, q.x), max(mx.y, q.y))
	return Rect2(mn, mx - mn)


func _particion(arrays: Array, mueve: Dictionary, quiero_volante: bool, pivote: Vector3) -> ArrayMesh:
	var vs: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var ns: PoolVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	# El material del kit tiene vertex_color_use_as_albedo: sin color de vertice,
	# COLOR llega en negro y apaga el albedo entero. La malla partida salia negra
	# —invisible en Dome_Intro— aunque el material fuera el correcto.
	var cols = arrays[Mesh.ARRAY_COLOR]
	var idx: PoolIntArray = arrays[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var i := 0
	while i + 2 < idx.size():
		var tri := [idx[i], idx[i + 1], idx[i + 2]]
		var del_volante := false
		for k in tri:
			if mueve.has(k):
				del_volante = true
		if del_volante == quiero_volante:
			for k in tri:
				if cols != null and cols.size() > k:
					st.add_color(cols[k])
				else:
					st.add_color(Color.white)
				if ns.size() > k:
					st.add_normal(ns[k])
				if uvs != null and uvs.size() > k:
					st.add_uv(_uv_para(quiero_volante, vs[k], uvs[k]))
				st.add_vertex(vs[k] - pivote)
		i += 3
	st.index()
	var m: ArrayMesh = st.commit()
	# Sin esto la sub-malla sale con el material por defecto (blanco plano) y pierde
	# el PBR del asset: SurfaceTool no lo hereda de la malla de origen.
	# Material del kit SIN tocar (metal=1, rough=1, atlas compartido): la valvula
	# tiene que leerse como el mismo cano que los rectos. Lo que unifica el color
	# es el remapeo de UV del cuerpo a la franja canonica: la isla propia de la
	# valvula cae en la zona herrumbre del atlas y "lucia marron" junto a tubos
	# gris-verdosos.
	if _material != null:
		m.surface_set_material(0, _material)
	return m


# UV del cuerpo contra la franja canonica: u = vuelta alrededor del eje Y, v =
# altura en metros de domo (escala x4 del kit) con el mismo periodo de 2 m que
# PipeRoute. El volante conserva sus UVs autoradas: es un herraje, como los codos.
func _uv_para(es_volante: bool, p: Vector3, uv_autorada: Vector2) -> Vector2:
	if es_volante or _isla_c.size.x <= 0.0:
		return uv_autorada
	var ang: float = atan2(p.z, p.x)
	var dist_m: float = p.y * _ESCALA_DOMO
	return Vector2(
		_isla_c.position.x + fposmod(ang, TAU) / TAU * _isla_c.size.x,
		_isla_c.position.y + fposmod(dist_m, _PERIODO_M) / _PERIODO_M * _isla_c.size.y)


func _buscar(n: Node, nombre: String) -> Mesh:
	if n is MeshInstance and n.name == nombre:
		return n.mesh
	for c in n.get_children():
		var f: Mesh = _buscar(c, nombre)
		if f != null:
			return f
	return null
