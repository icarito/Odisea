extends Node
class_name IceSubmergedCuller

# Apaga las colisiones de todo lo que el hielo ya sepulto.
#
# Dome_Intro tiene 240 criopods en seis anillos. RadialScatter batchea sus VISUALES en un
# MultiMeshInstance pero deja vivos los cuerpos originales ("Original nodes stay alive for
# collision and interaction", ver core_v2/tools/RadialScatter.gd): cada uno sigue pagando
# mantenimiento de broadphase aunque nada se mueva. Medido en un Redmi Note 9 Pro, la
# fisica cuesta ~14 ms de un frame de ~60 ms con CERO cuerpos activos y cero pares.
#
# Por que esto es mejor que cullear por distancia al jugador: hundirse es MONOTONO. El
# jugador camina SOBRE el hielo, asi que lo que queda debajo es inalcanzable y no vuelve a
# hacer falta. No hay histeresis, no hay oscilacion y, sobre todo, no hay churn: apagar y
# prender formas las re-registra en el espacio de fisica y eso perturba el orden de
# resolucion de contactos (el culler por distancia mete 13 mm de drift en un replay que sin
# el da 0.0000 m). Aca cada forma se apaga una vez y se queda apagada.
#
# Reversible igual, porque ice_height puede BAJAR: reset() lo devuelve a start_height y
# ensure_safe_for_respawn() lo baja para dejar aire sobre el checkpoint. Por eso el estado
# se deriva siempre de la altura actual y no de un "ya lo apague".

const DISABLE_ENV := "ODISEA_DISABLE_ICE_CULL"
const ShapeBounds := preload("res://core_v2/systems/collision/ShapeBounds.gd")

# Solo capa Prop (bit 64) por defecto. Entorno es el suelo y las paredes del domo: apagarlo
# bajo el hielo dejaria caer al jugador por el mundo si la altura retrocede.
export(int, LAYERS_3D_PHYSICS) var cullable_layers := 64
# Holgura bajo la superficie caminable. Una forma se apaga recien cuando su punto MAS ALTO
# quedo este margen por debajo de donde pisa el jugador, para que nunca desaparezca algo
# que todavia se pueda rozar.
export(float, 0.0, 10.0, 0.5) var submerged_margin := 1.5
export(bool) var enabled := true
# RadialScatter agrega sus hijos Batched_* por call_deferred, y los anillos horneados
# resuelven en frames distintos. Un solo escaneo puede llegar antes que los cuerpos.
export(int) var scan_attempts := 4
export(float) var scan_interval := 0.35

var _ice_level: Node = null
# Ordenado por altura del tope, de abajo hacia arriba. El orden es lo que hace barato el
# seguimiento: al subir el hielo solo hay que avanzar un cursor, no recorrer las 240.
var _shapes := []
var _cursor := 0
var _scans_done := 0


func _ready() -> void:
	if Engine.editor_hint:
		return
	if OS.get_environment(DISABLE_ENV) in ["1", "true", "yes", "on"]:
		enabled = false
		return
	call_deferred("_connect_ice_level")
	_schedule_scan()


func _connect_ice_level() -> void:
	_ice_level = _find_ice_level()
	if _ice_level == null:
		return
	if not _ice_level.is_connected("ice_height_changed", self, "_on_ice_height_changed"):
		var _e = _ice_level.connect("ice_height_changed", self, "_on_ice_height_changed")


# La raiz del nivel se resuelve trepando desde este nodo, no leyendo current_scene: un
# nivel instanciado a mano (arneses de prueba, precarga) no figura como current_scene y el
# escaneo se iria en blanco sin avisar.
func _raiz_de_escena() -> Node:
	var n: Node = self
	var tope: Node = get_tree().root if get_tree() != null else null
	while n.get_parent() != null and n.get_parent() != tope:
		n = n.get_parent()
	return n


func _find_ice_level() -> Node:
	var padre := get_parent()
	if padre != null and padre.has_method("get_frost_ceiling"):
		return padre
	if get_tree() == null:
		return null
	var pila := [_raiz_de_escena()]
	while not pila.empty():
		var n: Node = pila.pop_back()
		if n.has_method("get_frost_ceiling") and n.has_signal("ice_height_changed"):
			return n
		for c in n.get_children():
			pila.push_back(c)
	return null


func _schedule_scan() -> void:
	if _scans_done >= scan_attempts:
		return
	_scans_done += 1
	var t := get_tree()
	if t == null:
		return
	yield(t.create_timer(scan_interval), "timeout")
	if not is_inside_tree():
		return
	_rescan()
	_schedule_scan()


func _rescan() -> void:
	if get_tree() == null:
		return
	_shapes.clear()
	_cursor = 0
	var pila := [_raiz_de_escena()]
	while not pila.empty():
		var n: Node = pila.pop_back()
		if n is StaticBody and (n.collision_layer & cullable_layers) != 0:
			for c in n.get_children():
				if c is CollisionShape:
					var cs := c as CollisionShape
					# El tope de la esfera envolvente: solo se apaga cuando TODA la forma
					# quedo sepultada, nunca cuando solo su centro lo esta.
					var tope: float = cs.global_transform.origin.y + ShapeBounds.radius_of(cs)
					_shapes.append({"shape": cs, "top": tope, "off": cs.disabled})
		for c2 in n.get_children():
			pila.push_back(c2)
	_shapes.sort_custom(self, "_por_altura")
	if _ice_level != null:
		_on_ice_height_changed(_ice_level.ice_height)


func _por_altura(a, b) -> bool:
	return a.top < b.top


func _on_ice_height_changed(_height: float) -> void:
	if not enabled or _ice_level == null:
		return
	# La superficie que pisa el jugador, no la altura nominal del hielo.
	var umbral: float = _ice_level.get_frost_ceiling() - submerged_margin
	# El hielo subio: sepultar lo que quedo debajo.
	while _cursor < _shapes.size() and _shapes[_cursor].top < umbral:
		var e = _shapes[_cursor]
		if is_instance_valid(e.shape) and not e.off:
			e.shape.disabled = true
			e.off = true
		_cursor += 1
	# El hielo bajo (reset, o ensure_safe_for_respawn abriendo aire sobre el checkpoint):
	# devolver lo que volvio a estar al alcance.
	while _cursor > 0 and _shapes[_cursor - 1].top >= umbral:
		_cursor -= 1
		var e2 = _shapes[_cursor]
		if is_instance_valid(e2.shape) and e2.off:
			e2.shape.disabled = false
			e2.off = false


# Apagarlo tiene que DEVOLVER las colisiones, no solo dejar de sepultar: si se congela con
# el hielo alto, lo que ya quedo enterrado se queda sin colision para siempre.
func set_cull_enabled(valor: bool) -> void:
	enabled = valor
	if valor:
		if _ice_level != null:
			_on_ice_height_changed(_ice_level.ice_height)
		return
	for e in _shapes:
		if is_instance_valid(e.shape) and e.off:
			e.shape.disabled = false
			e.off = false
	_cursor = 0


func get_stats() -> Dictionary:
	return {
		"tracked": _shapes.size(),
		"submerged": _cursor,
		"enabled": enabled,
		"threshold": (_ice_level.get_frost_ceiling() - submerged_margin) if _ice_level != null else 0.0,
	}
