extends Node
class_name RandomLeakSeeder

# RandomLeakSeeder.gd - Deterministic random leak selector for coolant puzzles (FD-270 / FD-266).
# Selects a subset of pre-placed CoolantLeak candidates at game startup using a seeded RNG
# and Fisher-Yates shuffle. Replay compatible via "replay_sync" snapshots.

# --- EXPORTED PROPERTIES ---
export(int) var seed_value := 42
# Tomar el seed de la partida (SessionManager.run_seed) en vez del valor fijo del export.
# Apagado por defecto a proposito: los tests y CoolantLab fijan su seed a mano y deben
# seguir siendo reproducibles; es la ESCENA la que decide que una partida se juegue
# distinta cada vez (Dome_Intro lo enciende).
#
# El azar no se sortea aca: vive en el autoload, que es quien conoce la sesion. Este nodo
# solo copia ese entero a su estado y lo guarda en get_snapshot(); como esta en
# 'replay_sync', una grabacion reproduce exactamente la partida que se jugo.
export(bool) var randomize_on_start := false
export(int) var leak_count := 2
export(Array, NodePath) var candidate_leak_paths := []

# --- INTERNAL STATE ---
var _active_leak_paths: Array = []
var _is_activated: bool = false


func _get_property_list() -> Array:
	return [
		{
			"name": "seed",
			"type": TYPE_INT,
			"usage": PROPERTY_USAGE_DEFAULT
		}
	]


func _set(property: String, value) -> bool:
	if property == "seed":
		seed_value = int(value)
		return true
	return false


func _get(property: String):
	if property == "seed":
		return seed_value
	return null


func _ready() -> void:
	add_to_group("replay_sync")

	if randomize_on_start and not Engine.editor_hint and not _esta_reproduciendo():
		var session = get_node_or_null("/root/SessionManager")
		if session != null and "run_seed" in session:
			seed_value = int(session.run_seed)
			_active_leak_paths = []

	if _active_leak_paths.empty():
		_draw_active_leaks()

	print("[RandomLeakSeeder] seed = %d -> fugas: %s" % [seed_value, str(_active_leak_paths)])


func _esta_reproduciendo() -> bool:
	var session = get_node_or_null("/root/SessionManager")
	return session != null and "is_replaying" in session and bool(session.is_replaying)

	# La escena empieza sana: ColdRuptureEvent decide cuándo liberar la selección.
	# Mantener el sorteo listo conserva el seed para una activación explícita/replay.


func activate_leaks() -> void:
	if _is_activated:
		return
	if _active_leak_paths.empty():
		_draw_active_leaks()
	_is_activated = true
	_activate_leaks()


func get_active_leak_paths() -> Array:
	return _active_leak_paths.duplicate()


func _draw_active_leaks() -> void:
	if candidate_leak_paths.empty():
		_active_leak_paths = []
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Elegible = la fuga esta CONECTADA al circuito, no "su nombre no dice Ring". El filtro
	# por nombre excluia los anillos porque en su momento no pertenecian a ninguna rama; al
	# incorporarlos a la topologia (el refrigerante sube un tramo y se reparte por el anillo
	# de ese piso) pasaron a ser fugas de gameplay legitimas, con su valvula y su tanque.
	# Preguntarle a los adapters, en vez de mirar el nombre, hace que agregar un tramo al
	# circuito lo vuelva elegible solo, sin tocar este archivo.
	var conectadas := _leaks_en_topologia()
	var selectable: Array = []
	for candidate in candidate_leak_paths:
		var nodo: Node = _get_target_node(candidate)
		if nodo != null and conectadas.has(nodo):
			selectable.append(candidate)
	# Sin adapters resueltos todavia (tests que instancian el seeder suelto) no hay
	# evidencia de desconexion: se conserva el pool completo.
	if conectadas.empty():
		selectable = candidate_leak_paths.duplicate()
	var shuffled := selectable
	for i in range(shuffled.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp

	var count: int = int(min(leak_count, shuffled.size()))
	if count < 0:
		count = 0

	_active_leak_paths = []
	for idx in range(count):
		_active_leak_paths.append(shuffled[idx])

	# La misma rng, despues del barajado, sortea DONDE cae cada fuga sobre su tramo. Sigue
	# siendo determinista (mismo seed, misma secuencia de draws) y replay-safe.
	_scatter_selected_leaks(rng)


# Los nodos de fuga estan autorados en la union con la valvula, asi que las dos fugas
# sorteadas aparecian siempre pegadas a un tee y el puzzle se leia igual cada partida.
# Esto las corre a un punto sorteado a lo largo de SU MISMO tramo: la topologia no cambia
# (cada fuga sigue perteneciendo a su segmento, con su valvula y su tanque), pero el
# jugador tiene que recorrer la seccion para encontrarla.
func _scatter_selected_leaks(rng: RandomNumberGenerator) -> void:
	for path_val in _active_leak_paths:
		var leak: Node = _get_target_node(path_val)
		if not (leak is Spatial):
			continue
		var patch: Node = _find_patch_for(leak)
		var run: Spatial = _pipe_run_of(patch)
		if run == null:
			continue
		var surface := _random_point_on_run(run, rng)
		if surface.empty():
			continue
		(leak as Spatial).global_transform.origin = surface["point"]
		if patch is Spatial:
			(patch as Spatial).global_transform.origin = surface["point"]
			var visual: Node = patch.get_node_or_null("FissureVisual")
			if visual != null and "spray_direction" in visual:
				visual.set("spray_direction", surface["normal"])


func _find_patch_for(leak: Node) -> Node:
	if leak == null or leak.get_parent() == null:
		return null
	return leak.get_parent().get_node_or_null(str(leak.name) + "_Patch")


func _pipe_run_of(patch: Node) -> Spatial:
	if patch == null or not ("target_pipe_run_path" in patch):
		return null
	var run_path = patch.get("target_pipe_run_path")
	if run_path == null or String(run_path) == "":
		return null
	return patch.get_node_or_null(run_path) as Spatial


# Un punto sobre la PARED del tubo. Se toma un vertice real de la malla en vez de deducir
# la forma desde el AABB: para un tramo recto el AABB alcanzaba, pero para un ANILLO la caja
# envolvente es un cajon plano y el punto calculado caia dentro del anillo, flotando en el
# aire en vez de sobre el cano. El vertice siempre esta en la superficie, sea recta, curva o
# horneada, y su normal es hacia donde tiene que salir el chorro.
func _random_point_on_run(run: Spatial, rng: RandomNumberGenerator) -> Dictionary:
	var mesh_instance: MeshInstance = _first_mesh(run)
	if mesh_instance == null or mesh_instance.mesh == null:
		return {}
	var mesh: Mesh = mesh_instance.mesh
	if mesh.get_surface_count() == 0:
		return {}
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	if vertices == null or vertices.size() == 0:
		return {}
	var normales = arrays[Mesh.ARRAY_NORMAL]

	var idx: int = rng.randi_range(0, vertices.size() - 1)
	var local: Vector3 = vertices[idx]
	var normal_local := Vector3.UP
	if normales != null and normales.size() == vertices.size():
		normal_local = normales[idx]
		# Las tapas de los extremos miran a lo largo del cano: ahi viven el collar y la
		# union con el tramo siguiente, que taparian la grieta. Se busca un vertice de
		# pared, no de tapa.
		var eje_largo := _eje_largo(mesh.get_aabb())
		for _intento in range(8):
			if abs(normal_local[eje_largo]) < 0.7:
				break
			idx = rng.randi_range(0, vertices.size() - 1)
			local = vertices[idx]
			normal_local = normales[idx]

	var xf: Transform = mesh_instance.global_transform
	return {
		"point": xf.xform(local),
		"normal": xf.basis.xform(normal_local).normalized()
	}


func _first_mesh(node: Node) -> MeshInstance:
	for child in node.get_children():
		if child is MeshInstance:
			return child
		var nieto: MeshInstance = _first_mesh(child)
		if nieto != null:
			return nieto
	return null


func _eje_largo(aabb: AABB) -> int:
	var eje := 0
	for i in range(1, 3):
		if aabb.size[i] > aabb.size[eje]:
			eje = i
	return eje


# Todas las fugas que alguna rama declara en sus segmentos: son las que estan conectadas
# al circuito y por tanto pueden vaciar el tanque y responder a una valvula.
func _leaks_en_topologia() -> Array:
	var out: Array = []
	if get_tree() == null:
		return out
	for adapter in get_tree().get_nodes_in_group("coolant_adapter"):
		if not ("network" in adapter) or adapter.network == null:
			continue
		var branches = adapter.network.get("branches")
		if not (branches is Dictionary):
			continue
		var branch_id = adapter.get("branch_id")
		if not branches.has(branch_id):
			continue
		for seg in branches[branch_id].get("segments", []):
			if not (seg is Dictionary):
				continue
			var leak_path = seg.get("leak", null)
			if leak_path == null or String(leak_path) == "":
				continue
			var leak: Node = adapter.get_node_or_null(leak_path)
			if leak == null and adapter.get_parent() != null:
				leak = adapter.get_parent().get_node_or_null(leak_path)
			if leak != null and not out.has(leak):
				out.append(leak)
	return out


func _activate_leaks() -> void:
	for path_val in _active_leak_paths:
		var leak_node: Node = _get_target_node(path_val)
		if leak_node != null and leak_node.has_method("trigger_leak"):
			leak_node.call("trigger_leak")


func _get_target_node(path_val) -> Node:
	if path_val == null:
		return null
	var np: NodePath
	if path_val is NodePath:
		np = path_val
	elif path_val is String:
		if path_val == "":
			return null
		np = NodePath(path_val)
	else:
		return null
	if np.is_empty():
		return null

	var n = get_node_or_null(np)
	if n != null:
		return n
	var parent = get_parent()
	if parent != null:
		n = parent.get_node_or_null(np)
		if n != null:
			return n
	return null


# --- REPLAY / SNAPSHOT SYSTEM ---

func get_snapshot() -> Dictionary:
	var str_paths: Array = []
	for path in _active_leak_paths:
		str_paths.append(str(path))
	return {
		"seed": seed_value,
		"active_leak_paths": str_paths,
		"is_activated": _is_activated
	}


func restore_snapshot(data: Dictionary) -> void:
	if data.has("seed"):
		seed_value = int(data["seed"])
	# Re-sortear con el seed restaurado antes de aplicar la seleccion guardada: el sorteo
	# no solo elige QUE fugas, tambien DONDE caen sobre su tramo (_scatter_selected_leaks).
	# Sin esto un replay las dejaba en su posicion autorada y divergia de la corrida grabada.
	if is_inside_tree():
		_draw_active_leaks()
	if data.has("active_leak_paths"):
		var paths_raw = data["active_leak_paths"]
		if paths_raw is Array:
			_active_leak_paths = []
			for p in paths_raw:
				_active_leak_paths.append(NodePath(str(p)))
	if data.has("is_activated"):
		_is_activated = bool(data["is_activated"])
	print("[RandomLeakSeeder] seed restaurado = %d -> fugas: %s" % [seed_value, str(_active_leak_paths)])
	if _is_activated and is_inside_tree():
		_activate_leaks()
