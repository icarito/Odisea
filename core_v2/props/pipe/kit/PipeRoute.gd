tool
extends Spatial
class_name PipeRoute

# PipeRoute.gd — arma una corrida de caneria a partir de una POLILINEA, usando las
# piezas del kit modular (ver PipeKit.gd).
#
# Reemplaza el modo de autoria de DomeIntro_PipeNetworkSource.tscn, que son 1518
# lineas de Transform explicitos: ilegibles en un diff, imposibles de editar a mano,
# y por eso hubo que manipularlos con scripts (fit_pipes_to_criopods.py,
# generate_pipe_serpentine.py). Aca un anillo de cinco pisos son cinco listas de
# puntos.
#
# Que hace en cada vertice, segun el angulo que forman los dos tramos:
#
#   ~90 grados   codo del kit (turn_short / turn_long). Es lo unico que el kit trae
#                como curva, y sus puertos estan medidos en PipeKit.PUERTOS.
#   < UMBRAL     arco generado. El kit no trae codo de angulo libre, y pegar las
#                cuerdas a tope deja una arruga visible en cada vertice: en un
#                anillo poligonal son 24 arrugas por piso. Se barre un tubo por el
#                arco de empalme, con la misma seccion del cano, y los rectos se
#                acortan hasta los puntos de tangencia.

const PipeKitScript = preload("res://core_v2/props/pipe/kit/PipeKit.gd")

# Arriba de esto se usa codo del kit; abajo, cuerdas a tope.
const UMBRAL_CODO := 60.0
# Solape en las juntas, para que no se vea la costura por el lado externo.
const RECUBRIMIENTO := 0.012
# Radio de empalme del arco generado, en multiplos del radio del cano. Mas chico se
# ve anguloso; mas grande se come tramo recto y en un vertice muy cerrado no entra.
const RADIO_ARCO := 3.0
# Lados de la seccion del tubo generado. El kit usa 12; mantenerlo igual evita que
# el arco se lea con otra silueta que los rectos que empalma.
const LADOS_SECCION := 12
const SEGMENTOS_ARCO := 4
# Un tramo mas corto que esto no se dibuja: la pieza mas chica del kit es de 5 cm.
const MINIMO := 0.04

export(PoolVector3Array) var puntos := PoolVector3Array()
export(String, "grueso", "fino") var calibre := "grueso"
export(String, "metal", "pvc") var material_kit := "metal"
# Multiplicador de la SECCION del cano, no de su largo: escala los dos ejes
# perpendiculares al recorrido y deja el eje del tramo en 1, asi el ajuste de piezas
# contra la polilinea no se mueve. El kit viene en Ø0.10 y el domo estaba autorado
# contra el cano viejo de Ø0.40 (las fisuras de fuga miden 0.43), asi que 4.0
# reproduce el calibre original.
export(float, 0.25, 8.0) var grosor := 4.0
export(bool) var cerrada := false
# Indices de vertice donde va una valvula. Ocupa el largo de un recto, asi que
# entra sin recalcular el trazado (ver PipeKit.EN_LINEA).
export(PoolIntArray) var valvulas := PoolIntArray()
# Indices de vertice donde el tronco sigue RECTO y sale una rama: se coloca la T
# del kit (junction_t) y los rectos se cortan a los puertos del paso. La direccion
# de la rama va en tes_ramas (normalizada, coords de ruta), misma cantidad de
# entradas que tes y en el mismo orden. La ruta de la rama arranca en el vastago
# de la T: vertice + rama * 0.098 * grosor.
export(PoolIntArray) var tes := PoolIntArray()
export(PoolVector3Array) var tes_ramas := PoolVector3Array()
# Indices (dentro de puntos) que llevan CRUZ (junction_x, 4 bocas) en vez de T:
# para anillos que ATRAVIESAN el riser (el cano sigue a los dos lados y el riser
# entra perpendicular). La rama de la cruz se da en tes_ramas; la boca opuesta
# sale automaticamente.
export(PoolIntArray) var tes_cruz := PoolIntArray()
# Empalme en los EXTREMOS de la ruta (esquina entre dos rutas, ej: el anillo
# termina y el conector vertical sigue): eje_* es la direccion desde el extremo
# a lo largo del eje de la OTRA ruta. El codo del kit entra por ese eje y sale
# por el tramo propio; los tubos se solapan dentro del empalme.
export(bool) var codo_inicio := false
export(Vector3) var eje_inicio := Vector3()
export(bool) var codo_fin := false
export(Vector3) var eje_fin := Vector3()
export(bool) var reconstruir := false setget set_reconstruir

var _kit = null
var _avisos := []
# Franja canonica de textura (isla del recto de 200cm) y cuantos metros de cano
# cubre a lo largo. Cero = sin reparametrizar (kit no disponible).
var _isla_c: Rect2 = Rect2()
var _periodo_v: float = 0.0


func set_reconstruir(v: bool) -> void:
	reconstruir = false
	if v:
		build()


func _ready() -> void:
	# SIEMPRE reconstruye. Los hijos de un PipeRoute son geometria generada, nunca
	# autorada, asi que "no reconstruir si ya hay hijos" —el criterio de los props
	# horneados— deja piezas rancias de una construccion anterior conviviendo con las
	# nuevas: el sintoma es cano duplicado (parece del doble de grosor) y piezas
	# dentro del hueco reservado para una valvula.
	build()


func build() -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	_avisos = []
	if puntos.size() < 2:
		return
	if _kit == null:
		_kit = PipeKitScript.new()
	# Franja canonica: las piezas del kit traen islas propias con densidades muy
	# distintas entre si (el 5cm muestra la misma altura de textura que el 200cm:
	# 1.58 vs 0.12 por metro), asi que el patron salta en cada junta. Contra esta
	# isla y fase = metros recorridos, piezas y arcos muestrean la misma franja
	# con la misma densidad y el patron fluye continuo por toda la corrida.
	var ref: Mesh = _kit.malla(_kit.nombre("200cm", calibre, material_kit))
	if ref != null:
		_isla_c = _isla_uv(ref)
		_periodo_v = 2.0

	var lista := []
	for p in puntos:
		lista.append(p)
	if cerrada:
		lista.append(lista[0])
	var n: int = lista.size()

	# Cortes por vertice: cut_in[v] acorta el tramo que LLEGA a v, cut_out[v] el
	# que SALE. Codos, arcos y T/X cortan a los dos lados; juntas a tope, nada.
	var cut_in := []
	var cut_out := []
	var tipo := []  # 0 junta recta, 1 codo del kit, 2 arco generado
	for v in range(n):
		cut_in.append(0.0)
		cut_out.append(0.0)
		tipo.append(0)

	# Pasada 1: cortes y piezas de esquina. T/X valen tambien en los EXTREMOS
	# (v=0 y v=n-1): el paso sigue el unico tramo que existe ahi.
	for v in range(n):
		var din: Vector3 = (lista[1] - lista[0]).normalized() if v == 0 \
			else (lista[v] - lista[v - 1]).normalized()
		var dout: Vector3 = (lista[v + 1] - lista[v]).normalized() if v + 1 < n else din
		if _es_tee(v):
			var rama: Vector3 = _rama_de(v)
			var corte_tee: float = 0.100 * grosor
			if v > 0:
				cut_in[v] = corte_tee
			if v < n - 1:
				cut_out[v] = corte_tee
			if _es_cruz(v):
				_cruz(lista[v], din, rama)
			else:
				_tee(lista[v], din, rama)
		elif v > 0 and v < n - 1:
			var ang: float = rad2deg(din.angle_to(dout))
			if ang >= UMBRAL_CODO:
				var pieza: String = "turn_long" if ang > 115.0 else "turn_short"
				var pu: Array = PipeKitScript.PUERTOS[pieza]
				# puerto A en el origen local (entra), puerto B = a*din + b*dout
				# los puertos estan en unidades del kit; el codo va escalado por grosor
				var b: float = pu[1][0].x * grosor
				var a: float = pu[1][0].y * grosor
				cut_in[v] = a
				cut_out[v] = b
				tipo[v] = 1
				_codo(pieza, lista[v] - din * a, din, dout)
				# el codo conserva UVs propias del kit
			elif ang > 1.0:
				var radio_cano: float = PipeKitScript.RADIO[
					PipeKitScript.FINO if calibre == "fino" else PipeKitScript.GRUESO] * grosor
				var t_tan: float = radio_cano * RADIO_ARCO * tan(deg2rad(ang) * 0.5)
				if t_tan > 0.001:
					cut_in[v] = t_tan
					cut_out[v] = t_tan
					tipo[v] = 2

	if cerrada and n > 1:
		# El vertice de cierre ES lista[0]: su corte de salida gobierna el arranque
		# del primer tramo, si no el recto inicial atraviesa el arco de cierre.
		cut_out[0] = cut_in[n - 1]

	# Codos de empalme en los extremos (esquinas entre rutas distintas).
	if n >= 2:
		if codo_inicio:
			_codo_extremo(lista[0], -eje_inicio, (lista[1] - lista[0]).normalized())
		if codo_fin:
			_codo_extremo(lista[n - 1],
				(lista[n - 1] - lista[n - 2]).normalized(), eje_fin)

	# Pasada 2: distancia a lo largo de la ruta ajustada en cada vertice (fase de
	# textura) y arcos de empalme, que necesitan esa fase.
	var dist_v := []
	var dist: float = 0.0
	for v in range(n):
		dist_v.append(dist)
		if v + 1 < n:
			var full: float = lista[v].distance_to(lista[v + 1])
			dist += max(full - cut_out[v] - cut_in[v + 1], 0.0)
			if tipo[v + 1] == 2:
				var radio_cano: float = PipeKitScript.RADIO[
					PipeKitScript.FINO if calibre == "fino" else PipeKitScript.GRUESO] * grosor
				var din2: Vector3 = (lista[v + 1] - lista[v]).normalized()
				var dout2: Vector3 = (lista[v + 2] - lista[v + 1]).normalized() if v + 2 < n else din2
				var ang2: float = rad2deg(din2.angle_to(dout2))
				var mitad2: float = deg2rad(ang2) * 0.5
				var r_arco: float = radio_cano * RADIO_ARCO
				# el arco reemplaza 2*t_tan de cuerda por su barrido real
				dist += max(r_arco * deg2rad(ang2) - 2.0 * r_arco * tan(mitad2), 0.0)
	for v in range(1, n - 1):
		if tipo[v] != 2:
			continue
		var din: Vector3 = (lista[v] - lista[v - 1]).normalized()
		var dout: Vector3 = (lista[v + 1] - lista[v]).normalized()
		var ang: float = rad2deg(din.angle_to(dout))
		_arco(lista[v], din, dout, ang, dist_v[v] - cut_in[v])

	# Pasada 3: rectos ajustados de mayor a menor entre cortes.
	for i in range(n - 1):
		var dir: Vector3 = (lista[i + 1] - lista[i]).normalized()
		var a: Vector3 = lista[i] + dir * cut_out[i]
		var b: Vector3 = lista[i + 1] - dir * cut_in[i + 1]
		_tramo(a, b, i, dist_v[i] + cut_out[i])

	if not _avisos.empty():
		push_warning("[PipeRoute] %s: %s" % [name, ", ".join(_avisos)])


# Rectos ajustados de mayor a menor sobre el segmento a->b.
func _tramo(a: Vector3, b: Vector3, indice: int, dist_ini: float) -> void:
	var d: Vector3 = b - a
	var largo: float = d.length()
	if largo < MINIMO:
		return
	var dir: Vector3 = d / largo
	var valvula: bool = false
	for v in valvulas:
		if int(v) == indice:
			valvula = true
	var cursor: float = 0.0
	if valvula:
		var lv: float = PipeKitScript.EN_LINEA["valve_small_1"]
		if largo >= lv:
			_poner("valve_small_1", a, dir, 0.0, true, dist_ini)
			cursor = lv * grosor
	var ajuste: Dictionary = _kit.ajustar(largo - cursor)
	var piezas: Array = ajuste.piezas
	# El ajuste greedy deja un sobrante menor a la pieza minima (hasta 5 cm): se lo
	# traga la pieza mas larga estirandola sobre el eje, si no queda una ranura
	# visible en cada junta de rutas. La UV acompana el estiramiento (escala_eje).
	var cubierto: float = 0.0
	var mas_larga: int = -1
	for j in range(piezas.size()):
		cubierto += piezas[j]
		if mas_larga < 0 or piezas[j] > piezas[mas_larga]:
			mas_larga = j
	var delta: float = max(largo - cubierto, 0.0)
	for j in range(piezas.size()):
		# solape hacia atras: tapa la costura entre pieza y pieza
		var off: float = max(cursor - RECUBRIMIENTO, 0.0) if cursor > 0.0 else 0.0
		var esc: float = 1.0
		if j == mas_larga and delta > 0.001 and piezas[j] > 0.0:
			esc = (piezas[j] + delta) / piezas[j]
		_poner(PipeKitScript.LARGO_NOMBRE[piezas[j]], a, dir, off, false,
			dist_ini + off, esc)
		cursor += piezas[j] + (delta if j == mas_larga else 0.0)


# `uniforme` para las piezas que no son un recto simple (valvulas): su largo es parte
# de la pieza, asi que engordar solo lo transversal las deforma.
func _poner(pieza: String, origen: Vector3, dir: Vector3, avance: float,
		uniforme: bool = false, dist_uv: float = 0.0, esc_eje: float = 1.0) -> void:
	var m: Mesh = _kit.malla(_kit.nombre(pieza, calibre, material_kit))
	if m == null:
		_avisos.append("falta la pieza %s" % pieza)
		return
	var mi := MeshInstance.new()
	mi.name = "%s_%d" % [pieza, get_child_count()]
	if uniforme or _periodo_v <= 0.0:
		mi.mesh = m
	else:
		# rectos: UV canonica con fase por metros recorridos (textura continua)
		mi.mesh = _uv_continua(m, dist_uv, esc_eje)
	var base: Basis = _base(dir, esc_eje if not uniforme else 1.0)
	if uniforme:
		base = base.orthonormalized().scaled(Vector3(grosor, grosor, grosor))
	mi.transform = Transform(base, origen + dir * avance)
	add_child(mi)
	if get_tree() != null and owner != null:
		mi.owner = owner


# Reparametriza las UV de una pieza recta contra la franja canonica del kit:
# u = vuelta alrededor del eje, v = metros recorridos desde el inicio de la ruta
# (con periodo = el largo de cano que cubre la isla). Sin esto cada pieza muestrea
# su propia isla con su propia densidad y el patron salta en cada junta.
func _uv_continua(m: Mesh, dist_ini: float, esc_eje: float = 1.0) -> Mesh:
	var eje: Vector3 = PipeKitScript.EJE_RECTO[
		PipeKitScript.FINO if calibre == "fino" else PipeKitScript.GRUESO]
	var e1: Vector3 = Vector3.RIGHT if abs(eje.dot(Vector3.RIGHT)) < 0.9 else Vector3.BACK
	var e2: Vector3 = eje.cross(e1).normalized()
	e1 = e2.cross(eje).normalized()
	var arrays: Array = m.surface_get_arrays(0)
	var verts: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs := PoolVector2Array()
	uvs.resize(verts.size())
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		var along: float = v.dot(eje) * esc_eje
		var radial: Vector3 = v - eje * v.dot(eje)
		var ang: float = atan2(radial.dot(e2), radial.dot(e1))
		uvs[i] = Vector2(_u_tex(ang), _v_tex(dist_ini + along))
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var nueva := ArrayMesh.new()
	nueva.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	nueva.surface_set_material(0, m.surface_get_material(0))
	return nueva


func _u_tex(ang: float) -> float:
	return _isla_c.position.x + fposmod(ang, TAU) / TAU * _isla_c.size.x


func _v_tex(dist_m: float) -> float:
	return _isla_c.position.y + fposmod(dist_m, _periodo_v) / _periodo_v * _isla_c.size.y


func _es_tee(v: int) -> bool:
	for t in tes:
		if int(t) == v:
			return true
	return false


func _es_cruz(v: int) -> bool:
	for t in tes_cruz:
		if int(t) == v:
			return true
	return false


func _rama_de(v: int) -> Vector3:
	for k in range(tes.size()):
		if int(tes[k]) == v and k < tes_ramas.size():
			var r: Vector3 = tes_ramas[k]
			return r.normalized() if r.length() > 0.001 else Vector3.UP
	return Vector3.UP


# Codo en un EXTREMO de la ruta: empalma el eje propio con el eje de la otra
# ruta. entra por din (hacia p) y sale por dout. El origen queda 0.098*grosor
# detras de p, sobre el eje de entrada: los tubos propios y ajenos solapan los
# bore del codo y la esquina queda llena.
func _codo_extremo(p: Vector3, din: Vector3, dout: Vector3) -> void:
	if din.length() < 0.5 or dout.length() < 0.5:
		return
	var ang: float = rad2deg(din.normalized().angle_to(dout.normalized()))
	if ang < 1.0 or ang > 179.0:
		return
	_codo("turn_short", p - din.normalized() * (0.098 * grosor), din.normalized(), dout.normalized())


# T del kit (junction_t) sobre un tronco recto: el paso (puertos a ±0.10 locales,
# medidos) va sobre el eje del tronco y el vastago (puerto en el origen, apunta
# -Y local) hacia la rama. El origen de la pieza queda a 0.098*grosor del eje,
# sobre el arranque de la rama.
func _tee(vertice: Vector3, dir_tronco: Vector3, rama: Vector3) -> void:
	var m: Mesh = _kit.malla(_kit.nombre("junction_t", calibre, material_kit))
	if m == null:
		_avisos.append("falta la pieza junction_t")
		return
	var x: Vector3 = dir_tronco.normalized()
	var y: Vector3 = -rama
	var z: Vector3 = x.cross(y).normalized()
	var mi := MeshInstance.new()
	mi.name = "T_%d" % get_child_count()
	mi.mesh = _uv_herraje(m)
	mi.transform = Transform(Basis(x * grosor, y * grosor, z * grosor),
		vertice + rama * (0.098 * grosor))
	add_child(mi)
	if get_tree() != null and owner != null:
		mi.owner = owner


# Cruz del kit (junction_x) donde un anillo ATRAVIESA el riser: el paso local ±X
# va sobre el eje de la ruta (el anillo) y las bocas ±Y locales toman el riser.
# El origen queda 0.10*grosor atras por el eje del riser, para que el centro de
# la cruz caiga en el vertice y las bocas del riser queden a ±0.10*grosor.
func _cruz(vertice: Vector3, dir_eje: Vector3, rama: Vector3) -> void:
	var m: Mesh = _kit.malla(_kit.nombre("junction_x", calibre, material_kit))
	if m == null:
		_avisos.append("falta la pieza junction_x")
		return
	var x: Vector3 = dir_eje.normalized()
	var y: Vector3 = rama.normalized()
	var z: Vector3 = x.cross(y).normalized()
	var mi := MeshInstance.new()
	mi.name = "Cruz_%d" % get_child_count()
	mi.mesh = _uv_herraje(m)
	mi.transform = Transform(Basis(x * grosor, y * grosor, z * grosor),
		vertice - rama * (0.100 * grosor))
	add_child(mi)
	if get_tree() != null and owner != null:
		mi.owner = owner


# Los herrajes (T, cruz, codos) traen islas propias del atlas en zonas de color
# distinto (la T cae en la zona azul): se remapean a la franja canonica de los
# rectos para que todo el circuito lea el mismo metal.
func _uv_herraje(m: Mesh) -> Mesh:
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


func _codo(pieza: String, origen: Vector3, din: Vector3, dout: Vector3) -> void:
	var m: Mesh = _kit.malla(_kit.nombre(pieza, calibre, material_kit))
	if m == null:
		_avisos.append("falta la pieza %s" % pieza)
		return
	var mi := MeshInstance.new()
	mi.name = "%s_%d" % [pieza, get_child_count()]
	mi.mesh = _uv_herraje(m)
	# el codo entra por su -Y y sale por su +X: se mapea Y->din, X->dout
	var y: Vector3 = din.normalized()
	var x: Vector3 = dout.normalized()
	var z: Vector3 = x.cross(y).normalized()
	# Escala UNIFORME. En un recto se engordan solo los ejes transversales para no
	# alterar el largo; el codo tiene DOS ejes de recorrido (entra por Y, sale por X),
	# asi que escalar solo el tercero lo dejaba a tamaño de kit (0.15) al lado de un
	# cano de 0.40 — y el radio de curva tiene que crecer con el calibre igual.
	mi.transform = Transform(Basis(x * grosor, y * grosor, z * grosor), origen)
	add_child(mi)
	if get_tree() != null and owner != null:
		mi.owner = owner


# Arco de empalme en un vertice suave. Devuelve cuanto hay que acortar cada recto
# (la longitud de tangencia); 0 si el vertice es tan cerrado que no entra.
func _arco(centro: Vector3, din: Vector3, dout: Vector3, ang_deg: float,
		dist_v: float = 0.0) -> float:
	var radio_cano: float = PipeKitScript.RADIO[
		PipeKitScript.FINO if calibre == "fino" else PipeKitScript.GRUESO] * grosor
	var r_arco: float = radio_cano * RADIO_ARCO
	var mitad: float = deg2rad(ang_deg) * 0.5
	var tang: float = r_arco * tan(mitad)
	if tang < 0.001:
		return 0.0

	var p0: Vector3 = centro - din * tang
	var p1: Vector3 = centro + dout * tang
	# El centro del arco sale por la bisectriz interior, a r/cos(mitad) del vertice.
	var bis: Vector3 = (dout - din).normalized()
	var o: Vector3 = centro + bis * (r_arco / max(cos(mitad), 0.001))
	var u: Vector3 = (p0 - o).normalized()
	var v: Vector3 = (p1 - o).normalized()
	var eje: Vector3 = u.cross(v)
	if eje.length() < 0.0001:
		return 0.0
	eje = eje.normalized()

	# UV contra la misma franja canonica de los rectos: fase = distancia a lo largo
	# de la ruta hasta el punto de tangencia de entrada.
	var dist_ini: float = dist_v
	var largo_arco: float = r_arco * deg2rad(ang_deg)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total: float = u.angle_to(v)
	var anillos := []
	for s in range(SEGMENTOS_ARCO + 1):
		var f: float = float(s) / float(SEGMENTOS_ARCO)
		var q := Quat(eje, total * f)
		var radial: Vector3 = q.xform(u)
		var pos: Vector3 = o + radial * r_arco
		var avance: Vector3 = eje.cross(radial).normalized()
		var lado: Vector3 = radial
		var arriba: Vector3 = eje
		var anillo := []
		for k in range(LADOS_SECCION):
			var a: float = TAU * float(k) / float(LADOS_SECCION)
			anillo.append(pos + (lado * cos(a) + arriba * sin(a)) * radio_cano)
		anillos.append(anillo)
	for s in range(SEGMENTOS_ARCO):
		for k in range(LADOS_SECCION):
			var k2: int = (k + 1) % LADOS_SECCION
			var a0: Vector3 = anillos[s][k]
			var a1: Vector3 = anillos[s][k2]
			var b0: Vector3 = anillos[s + 1][k]
			var b1: Vector3 = anillos[s + 1][k2]
			# UV: u alrededor de la seccion, v a lo largo del arco. SIN esto todos
			# los fragmentos muestrean el mismo texel del difuso y el arco sale de
			# un color plano (salia negro), aunque el material sea el correcto.
			var u0: float = _u_tex(TAU * float(k) / float(LADOS_SECCION))
			var u1: float = _u_tex(TAU * float(k + 1) / float(LADOS_SECCION))
			var v0: float = _v_tex(dist_ini + float(s) / float(SEGMENTOS_ARCO) * largo_arco)
			var v1: float = _v_tex(dist_ini + float(s + 1) / float(SEGMENTOS_ARCO) * largo_arco)
			# Winding: con el orden a0,b0,b1 las caras salian hacia ADENTRO (medido:
			# 24 de 288 normales hacia afuera) y el tubo se veia negro, porque lo que
			# quedaba visible era su interior sin iluminar.
			var quad := [[a0, u0, v0], [b1, u1, v1], [b0, u0, v1],
				[a0, u0, v0], [a1, u1, v0], [b1, u1, v1]]
			for e in quad:
				# El material del kit tiene vertex_color_use_as_albedo: sin color de
				# vertice, COLOR llega en negro y apaga el albedo. El arco salia negro
				# por esto, no por falta de material.
				st.add_color(Color.white)
				# Y las UV del kit viven en una ISLA del atlas, no en 0..1: hay que
				# mapear ahi dentro o se muestrea otra pieza de la textura.
				st.add_uv(Vector2(e[1], e[2]))
				st.add_vertex(e[0])
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance.new()
	mi.name = "Arco_%d" % get_child_count()
	mi.mesh = st.commit()
	# Mismo material que los rectos: el arco tiene que leerse como el mismo cano.
	var recto: Mesh = _kit.malla(_kit.nombre("40cm", calibre, material_kit))
	var mat: Material = recto.surface_get_material(0) if recto != null else null
	if mat != null:
		mi.mesh.surface_set_material(0, mat)
		mi.set_surface_material(0, mat)
	else:
		_avisos.append("el arco no consiguio material del kit")
	add_child(mi)
	if get_tree() != null and owner != null:
		mi.owner = owner
	return tang


# Region del atlas que ocupa una pieza del kit, para que el arco generado muestree
# la misma zona de textura que los rectos que empalma.
func _isla_uv(m: Mesh) -> Rect2:
	if m == null:
		return Rect2(0, 0, 1, 1)
	var uvs = m.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	if uvs == null or uvs.size() == 0:
		return Rect2(0, 0, 1, 1)
	var mn: Vector2 = uvs[0]
	var mx: Vector2 = uvs[0]
	for q in uvs:
		mn = Vector2(min(mn.x, q.x), min(mn.y, q.y))
		mx = Vector2(max(mx.x, q.x), max(mx.y, q.y))
	return Rect2(mn, mx - mn)


# Base ortonormal con el eje del recto (Y para grueso, X para fino) sobre `dir`.
# El kit trae los dos calibres sobre ejes distintos; se normaliza aca.
func _base(dir: Vector3, esc_eje: float = 1.0) -> Basis:
	var eje: Vector3 = PipeKitScript.EJE_RECTO[
		PipeKitScript.FINO if calibre == "fino" else PipeKitScript.GRUESO]
	var d: Vector3 = dir.normalized()
	var aux: Vector3 = Vector3.UP if abs(d.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var i: Vector3 = aux.cross(d).normalized()
	var j: Vector3 = d.cross(i).normalized()
	if eje == Vector3(0, 1, 0):
		return Basis(i * grosor, d * esc_eje, j * grosor)
	return Basis(d * esc_eje, i * grosor, j * grosor)
