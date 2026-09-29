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

var _frozen_nodes: Array = []
var _frozen_root: Node = null

# True si ese nodo es el root que ya quedo congelado (permite el chequeo barato por frame
# sin volver a recorrer el arbol).
func frozen_root_is(root: Node) -> bool:
	return root != null and is_instance_valid(root) and root == _frozen_root and not _frozen_nodes.empty()

func is_frozen() -> bool:
	return not _frozen_nodes.empty()

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
	if extra != null and is_instance_valid(extra) and extra.is_physics_processing():
		extra.set_physics_process(false)
		_frozen_nodes.append(extra)

func thaw() -> void:
	for node in _frozen_nodes:
		if is_instance_valid(node):
			node.set_physics_process(true)
	_frozen_nodes.clear()
	_frozen_root = null

func _freeze_subtree(node: Node) -> void:
	# HoloTerminalV2 (pantallas y HUD del traje) usa _physics_process para presentacion:
	# transicion al HUD, cursor del shader, oclusion y anclaje a la camara activa.
	# Congelarlo dejaba las pantallas rosadas y sueltas de la camara.
	if node.is_physics_processing() and not (node is HoloTerminalV2):
		node.set_physics_process(false)
		_frozen_nodes.append(node)
	for child in node.get_children():
		_freeze_subtree(child)
