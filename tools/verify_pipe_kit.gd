extends SceneTree

# verify_pipe_kit.gd — vuelve a MEDIR el kit y lo contrasta contra PipeKit.gd.
#
# El catalogo de puertos no se puede deducir del nombre de la pieza ni de la
# documentacion del asset: sale de detectar los anillos de seccion en la malla. Si
# alguien reimporta el glTF con otra escala, otro eje, u otra version del asset,
# todo lo que se genere con el kit queda mal SIN error. Esto lo detecta.
#
# Run: godot3-bin --path . --no-window -s tools/verify_pipe_kit.gd

const PipeKitScript = preload("res://core_v2/props/pipe/kit/PipeKit.gd")
const TOL := 0.004

var _fallas := 0


func _init() -> void:
	var kit = PipeKitScript.new()
	var raiz: Node = load(PipeKitScript.RUTA).instance()

	# 1. estan todas las piezas que el catalogo promete
	for largo in PipeKitScript.LARGOS:
		for calibre in [PipeKitScript.GRUESO, PipeKitScript.FINO]:
			var n: String = kit.nombre(PipeKitScript.LARGO_NOMBRE[largo], calibre)
			if kit.malla(n) == null:
				_falla("falta la pieza %s" % n)

	# 2. un recto mide lo que dice su nombre, sobre el eje que dice el catalogo
	for largo in PipeKitScript.LARGOS:
		for calibre in [PipeKitScript.GRUESO, PipeKitScript.FINO]:
			var m: Mesh = kit.malla(kit.nombre(PipeKitScript.LARGO_NOMBRE[largo], calibre))
			if m == null:
				continue
			var eje: Vector3 = PipeKitScript.EJE_RECTO[calibre]
			var tam: Vector3 = m.get_aabb().size
			var medido: float = abs(tam.dot(eje))
			if abs(medido - largo) > TOL:
				_falla("%s calibre %s mide %.3f sobre %s, el catalogo dice %.3f" % [
					PipeKitScript.LARGO_NOMBRE[largo], calibre, medido, str(eje), largo])

	# 3. los puertos declarados existen en la malla, en la posicion declarada
	for pieza in PipeKitScript.PUERTOS:
		var m: Mesh = kit.malla(kit.nombre(pieza))
		if m == null:
			_falla("falta la pieza %s" % pieza)
			continue
		var anillos: Array = _anillos(m)
		for entrada in PipeKitScript.PUERTOS[pieza]:
			var pos: Vector3 = entrada[0]
			var cerca := false
			for a in anillos:
				if (a - pos).length() <= 0.01:
					cerca = true
					break
			if not cerca:
				_falla("%s: no hay anillo de seccion en el puerto %s (medidos: %s)" % [
					pieza, str(pos), str(anillos)])

	# 4. la valvula entra donde entra un recto: mismos puertos, mismo largo
	for pieza in PipeKitScript.EN_LINEA:
		var m: Mesh = kit.malla(kit.nombre(pieza))
		if m == null:
			_falla("falta la pieza en linea %s" % pieza)
			continue
		var largo: float = PipeKitScript.EN_LINEA[pieza]
		if abs(m.get_aabb().size.y - largo) > 0.01:
			_falla("%s ocupa %.3f de alto, el catalogo dice %.3f" % [
				pieza, m.get_aabb().size.y, largo])

	raiz.free()
	if _fallas > 0:
		push_error("[verify_pipe_kit] %d fallas" % _fallas)
		quit(1)
		return
	print("[verify_pipe_kit] ok")
	quit(0)


# Centros de los anillos de seccion: planos perpendiculares a un eje con >=8
# vertices a distancia de radio de cano del centro.
func _anillos(m: Mesh) -> Array:
	var vs: PoolVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var salida := []
	for eje in range(3):
		var planos := {}
		for v in vs:
			var k = stepify(v[eje], 0.001)
			if not planos.has(k):
				planos[k] = []
			planos[k].append(v)
		var claves: Array = planos.keys()
		claves.sort()
		for k in [claves[0], claves[claves.size() - 1]]:
			var grupo: Array = planos[k]
			if grupo.size() < 8:
				continue
			var c := Vector3.ZERO
			for v in grupo:
				c += v
			c /= grupo.size()
			var rad := 0.0
			for v in grupo:
				rad = max(rad, (v - c).length())
			if rad > 0.02 and rad < 0.09:
				salida.append(c)
	return salida


func _falla(msg: String) -> void:
	_fallas += 1
	printerr("[verify_pipe_kit] FALLA: %s" % msg)
