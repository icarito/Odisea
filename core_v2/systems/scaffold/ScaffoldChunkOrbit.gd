extends Spatial
# Sin class_name: se consume con preload().
#
# Proyeccion ORBITAL de un tramo de chunks de andamio (ScaffoldChunkRegistry) sobre el
# interior de un cilindro. Misma idea que CylinderRotator: la fisica del jugador no cambia
# (Vector3.UP, AGENTS §5.1); lo que se mueve es el mundo. Cada tick los chunks se recolocan
# sobre el arco de modo que el tramo BAJO el jugador quede plano y el resto se curve hacia
# arriba, delante y detras.
#
# Marco de ESTE nodo: eje del cilindro = X (lateral del tramo), arco = Z (avance del tramo),
# radial = Y (subir es ir hacia el eje). Para otro eje de nave, rotar el nodo.
#
# Dos espacios:
# - plano: el del registro (x lateral, y altura, z avance). Waypoints y grafo viven aqui.
# - fisico: donde estan los cuerpos. Coinciden en el punto bajo el jugador.
# Cada chunk es rigido y se apoya como cuerda del circulo a SU radio (base_radius - altura),
# asi las juntas calzan aunque el tramo suba o baje.
#
# ponytail: recoloca todos los chunks del tramo; con streaming, limitar a los cercanos.

const Registry := preload("res://core_v2/systems/scaffold/ScaffoldChunkRegistry.gd")
const HALF := Registry.CHUNK_LENGTH * 0.5
const MOVE_EPSILON := 0.02

export(float) var base_radius := 190.0

var _chunks := []      # [{node, origin, radius, theta}] en orden de avance
var _player: Spatial = null
var _last_s := NAN


# Los chunks se agregan en orden; `flat_origin` es el `origin` del placement del registro.
func add_chunk(node: Spatial, flat_origin: Vector3) -> void:
	var radius: float = max(base_radius - flat_origin.y, 1.0)
	var theta: float = HALF / radius
	if not _chunks.empty():
		var prev: Dictionary = _chunks[-1]
		theta += prev["theta"] + HALF / float(prev["radius"])
	_chunks.append({"node": node, "origin": flat_origin, "radius": radius, "theta": theta})
	add_child(node)
	_last_s = NAN


func set_player(player: Spatial) -> void:
	_player = player
	_last_s = NAN


func _physics_process(_delta: float) -> void:
	reposition()


# Publico para tests que avanzan el tick del piloto a mano.
func reposition() -> void:
	if _chunks.empty() or not is_instance_valid(_player):
		return
	var s: float = to_local(_player.global_transform.origin).z
	if not is_nan(_last_s) and abs(s - _last_s) < MOVE_EPSILON:
		return
	_last_s = s
	var k: int = _index_at(s)
	var under: Dictionary = _chunks[k]
	var theta_player: float = float(under["theta"]) + (s - (under["origin"].z + HALF)) / float(under["radius"])
	for c in _chunks:
		var theta: float = float(c["theta"]) - theta_player
		var radius: float = float(c["radius"])
		var basis := Basis(Vector3.RIGHT, -theta)
		var center := Vector3(c["origin"].x, base_radius - radius * cos(theta), s + radius * sin(theta))
		c["node"].transform = Transform(basis, center - basis.xform(Vector3(0.0, 0.0, HALF)))


func _index_at(s: float) -> int:
	return int(clamp(floor(s / Registry.CHUNK_LENGTH), 0, _chunks.size() - 1))


# Punto fisico (global) -> punto plano del registro.
func world_to_flat(world: Vector3) -> Vector3:
	if _chunks.empty():
		return world
	var local: Vector3 = to_local(world)
	var c: Dictionary = _chunks[_index_at(local.z)]
	return c["origin"] + c["node"].transform.affine_inverse().xform(local)


# Punto plano del registro -> punto fisico (global), segun la colocacion actual.
func flat_to_world(flat: Vector3) -> Vector3:
	if _chunks.empty():
		return flat
	var c: Dictionary = _chunks[_index_at(flat.z)]
	return to_global(c["node"].transform.xform(flat - c["origin"]))


# Direccion horizontal plana -> direccion fisica. Bajo el jugador el tramo es plano, asi
# que basta la orientacion del nodo.
func flat_dir_to_world(dir: Vector3) -> Vector3:
	return global_transform.basis.xform(dir)
