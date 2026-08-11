extends Reference

# Sin class_name a proposito: esa registracion la escribe el editor en project.godot, asi
# que un script creado fuera del editor no resuelve. Los consumidores hacen preload.
#
# Radio de la esfera que envuelve una forma de colision, en unidades de mundo.
#
# Existe porque comparar distancias contra el ORIGEN de un CollisionShape es incorrecto para
# cualquier forma grande: una baranda o una plataforma de andamio tiene su origen en el
# centro, asi que parado en un extremo el jugador esta a mas de 20 m del origen mientras la
# toca con el cuerpo. Apagarla ahi lo hace atravesarla y caer; paso de verdad.
#
# Ante una forma que no reconocemos devolvemos un radio grande a proposito. El error seguro
# es sobrestimar (se pierde algo de ahorro), nunca subestimar: subestimar apaga colisiones
# que el jugador esta tocando.
const RADIO_DESCONOCIDO := 100.0


static func radius_of(node: CollisionShape) -> float:
	if node == null:
		return RADIO_DESCONOCIDO
	var shape: Shape = node.shape
	if shape == null:
		return RADIO_DESCONOCIDO
	var escala: Vector3 = node.global_transform.basis.get_scale()
	var factor: float = max(abs(escala.x), max(abs(escala.y), abs(escala.z)))
	var local := RADIO_DESCONOCIDO
	if shape is BoxShape:
		local = (shape as BoxShape).extents.length()
	elif shape is SphereShape:
		local = (shape as SphereShape).radius
	elif shape is CapsuleShape:
		local = (shape as CapsuleShape).radius + (shape as CapsuleShape).height * 0.5
	elif shape is CylinderShape:
		var cil := shape as CylinderShape
		local = Vector2(cil.radius, cil.height * 0.5).length()
	elif shape is ConvexPolygonShape:
		local = _radio_de_puntos((shape as ConvexPolygonShape).points)
	elif shape is ConcavePolygonShape:
		local = _radio_de_puntos((shape as ConcavePolygonShape).get_faces())
	return local * factor


static func _radio_de_puntos(puntos) -> float:
	var maximo := 0.0
	for i in range(puntos.size()):
		var d: float = (puntos[i] as Vector3).length()
		if d > maximo:
			maximo = d
	if maximo <= 0.0:
		return RADIO_DESCONOCIDO
	return maximo
