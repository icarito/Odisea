extends SceneTree

# check_pipe_route.gd — verifica que PipeRoute arme corridas SIN huecos.
#
# Un hueco entre pieza y pieza no rompe nada ni tira error: solo se ve un cano
# cortado. Es exactamente el tipo de defecto que costo varias rondas encontrar en
# el sistema viejo, asi que aca se mide.
#
# Run: godot3-bin --path . --no-window -s tools/check_pipe_route.gd

const RouteScript = preload("res://core_v2/props/pipe/kit/PipeRoute.gd")

var _fallas := 0


func _init() -> void:
	# recta simple: la suma de piezas tiene que cubrir el largo
	_caso("recta 3.7m", [Vector3.ZERO, Vector3(3.7, 0, 0)], false)
	# ele: dos tramos a 90 grados, con codo del kit en el vertice
	_caso("ele 90", [Vector3.ZERO, Vector3(2, 0, 0), Vector3(2, 0, 2)], false)
	# subida: vertical, que es el caso del riser
	_caso("vertical", [Vector3.ZERO, Vector3(0, 4.5, 0)], false)
	# anillo poligonal de 24 lados, r=12: el caso de Dome_Intro
	var anillo := []
	for i in range(24):
		var a: float = TAU * float(i) / 24.0
		anillo.append(Vector3(cos(a) * 12.0, 0, sin(a) * 12.0))
	_caso("anillo r=12 (24 lados)", anillo, true)

	if _fallas > 0:
		push_error("[check_pipe_route] %d fallas" % _fallas)
		quit(1)
		return
	print("[check_pipe_route] ok")
	quit(0)


func _caso(nombre: String, pts: Array, cerrada: bool) -> void:
	var r = RouteScript.new()
	r.puntos = PoolVector3Array(pts)
	r.cerrada = cerrada
	get_root().add_child(r)
	r.build()

	var piezas: int = r.get_child_count()
	if piezas == 0:
		_falla("%s: no genero ninguna pieza" % nombre)
		r.queue_free()
		return

	# largo cubierto vs largo pedido
	var pedido := 0.0
	for i in range(pts.size() - 1):
		pedido += (pts[i + 1] - pts[i]).length()
	if cerrada:
		pedido += (pts[0] - pts[pts.size() - 1]).length()

	# NOTA: cubierto ya no se suma por AABB de pieza — la caja de un arco envuelve
	# la curva y miente (marcaba 0.65 m fantasma por esquina). La cobertura real
	# sale del muestreo de abajo: proporcion de muestras dentro de piezas.
	var cajas := []
	for c in r.get_children():
		cajas.append([c.global_transform.affine_inverse(), c.mesh.get_aabb().grow(0.02)])
	var descubiertos := 0
	var muestras := 0
	var peor_hueco := 0.0
	var corrido := 0.0
	for i in range(pts.size() - (1 if not cerrada else 0)):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		var largo: float = (b - a).length()
		var n: int = int(largo / 0.02)
		for k in range(n + 1):
			var pt: Vector3 = a.linear_interpolate(b, float(k) / float(max(n, 1)))
			muestras += 1
			var dentro := false
			for caja in cajas:
				if caja[1].has_point(caja[0].xform(pt)):
					dentro = true
					break
			if dentro:
				peor_hueco = max(peor_hueco, corrido)
				corrido = 0.0
			else:
				descubiertos += 1
				corrido += 0.02
	peor_hueco = max(peor_hueco, corrido)

	var cubierto: float = pedido * float(muestras - descubiertos) / float(max(muestras, 1))
	var falta: float = pedido - cubierto
	print("[check_pipe_route] %-26s piezas=%3d  pedido=%6.2f  cubierto=%6.2f  sin_cano=%d/%d  hueco_max=%.2f m" % [
		nombre, piezas, pedido, cubierto, descubiertos, muestras, peor_hueco])
	# el ajuste greedy baja hasta 5cm, asi que puede faltar menos de eso por tramo
	if falta > 0.05 * float(max(pts.size() - 1, 1)) + 0.01:
		_falla("%s: faltan %.3f m de cano" % [nombre, falta])
	# un hueco de mas de 6 cm se ve; menos que eso lo tapa el solape de las juntas
	if peor_hueco > 0.06:
		_falla("%s: hay %.2f m de recorrido sin cano" % [nombre, peor_hueco])
	r.queue_free()


func _falla(msg: String) -> void:
	_fallas += 1
	printerr("[check_pipe_route] FALLA: %s" % msg)
