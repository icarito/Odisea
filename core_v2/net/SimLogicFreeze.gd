extends Reference

# SimLogicFreeze.gd - FD-316: congelado y descongelado de la logica de un nivel para los
# dos roles de simulacion remota (autoridad y render-esclavo).
#
# Por convencion del proyecto la logica de gameplay vive en _physics_process y lo visual
# en _process: se apaga el primero en todo el subarbol y el segundo sigue (animaciones,
# particulas). Se restauran exactamente los nodos que estaban corriendo, no se prenden
# procesadores que ya estaban apagados.
#
# Antes esto vivia duplicado solo en RemoteSimClient; al conservar el nivel la autoridad
# durante un stop blando necesitaba el mismo congelado (si no, el Pilot oculto cae a su
# InputProvider local y el teclado del control lo sigue moviendo).
#
# Lo que entra al nivel DESPUES del congelado (spawners, PlateContentStream, pickups) nace
# simulando encima de los snapshots: por eso se escucha SceneTree.node_added y se filtra a
# los nodos que caen bajo la escena congelada. Es un hook por evento, no un re-scan por
# frame (bug 4 del review FD-316).

var _frozen_nodes: Array = []
var _frozen_root: Node = null
var _frozen_extra: Node = null
# SceneTree al que quedo conectado node_added; null si no hay escucha (o ya se desconecto).
var _tree: SceneTree = null

# True si ese nodo es el root que ya quedo congelado (permite el chequeo barato por frame
# sin volver a recorrer el arbol).
func frozen_root_is(root: Node) -> bool:
	return root != null and is_instance_valid(root) and root == _frozen_root

func is_frozen() -> bool:
	return _frozen_root != null

# Congela la logica del subarbol de root y, si extra quedo fuera de el, tambien la de ese
# nodo (el jugador puede no colgar de la escena actual: SessionManager lo resuelve aparte).
# Idempotente por root: si ya esta congelado no vuelve a recorrer.
func freeze(root: Node, extra: Node = null) -> void:
	if frozen_root_is(root):
		return
	thaw()
	if root != null and is_instance_valid(root):
		_frozen_root = root
		_freeze_subtree(root)
	if extra != null and is_instance_valid(extra) and extra.is_physics_processing() \
			and not _frozen_nodes.has(extra):
		extra.set_physics_process(false)
		_frozen_nodes.append(extra)
	_frozen_extra = extra if extra != null and is_instance_valid(extra) else null
	_connect_node_added()

func thaw() -> void:
	_disconnect_node_added()
	for node in _frozen_nodes:
		if is_instance_valid(node):
			node.set_physics_process(true)
	_frozen_nodes.clear()
	_frozen_root = null
	_frozen_extra = null

func _freeze_subtree(node: Node) -> void:
	# HoloTerminalV2 (pantallas y HUD del traje) usa _physics_process para presentacion:
	# transicion al HUD, cursor del shader, oclusion y anclaje a la camara activa.
	# Congelarlo dejaba las pantallas rosadas y sueltas de la camara.
	if node.is_physics_processing() and not (node is HoloTerminalV2):
		node.set_physics_process(false)
		_frozen_nodes.append(node)
	for child in node.get_children():
		_freeze_subtree(child)

func _connect_node_added() -> void:
	var scope: Node = _frozen_root if _frozen_root != null else _frozen_extra
	if scope == null or not is_instance_valid(scope):
		return
	var tree := scope.get_tree()
	if tree == null:
		return
	if not tree.is_connected("node_added", self, "_on_node_added"):
		tree.connect("node_added", self, "_on_node_added")
	_tree = tree

func _disconnect_node_added() -> void:
	if _tree != null and _tree.is_connected("node_added", self, "_on_node_added"):
		_tree.disconnect("node_added", self, "_on_node_added")
	_tree = null

# Un nodo que entra al nivel durante el congelado debe quedar con su logica apagada igual
# que los que ya estaban: si no, un spawner/timer/pickup stream sigue simulando encima de
# los snapshots de la autoridad.
func _on_node_added(node: Node) -> void:
	if node == null or _frozen_nodes.has(node):
		return
	if not _is_in_frozen_scope(node):
		return
	if node.is_physics_processing() and not (node is HoloTerminalV2):
		node.set_physics_process(false)
		_frozen_nodes.append(node)

func _is_in_frozen_scope(node: Node) -> bool:
	if _frozen_root != null and is_instance_valid(_frozen_root) \
			and (_frozen_root == node or _frozen_root.is_a_parent_of(node)):
		return true
	if _frozen_extra != null and is_instance_valid(_frozen_extra) \
			and _frozen_extra.is_a_parent_of(node):
		return true
	return false
