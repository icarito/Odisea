extends Spatial
class_name CriopodRingVisualV2

# FD-314 - Visual barato del anillo de criopods decorativos de RingHub.
#
# Tres MultiMeshInstance (shell / glass / cards) reemplazan las ~29 escenas
# CriopodParallax con su propio StaticBody. El anillo vive SIEMPRE en el shell.
#
# El pod funcional de despertar (Criopod_Vert) se coloca en un slot elegido por
# run_seed; para que no quede un pod decorativo encima, RingHubWakeup llama
# `block_slot(slot)` y aca se manda esa instancia lejos de la camara.

const HIDDEN_ORIGIN := Vector3(0.0, -10000.0, 0.0)

# slot del RadialScatter (0..item_count-1) -> indice de instancia (0..N-1); -1 si
# ese slot no tiene pod decorativo.
export(Array, int) var slot_to_instance := []

var blocked_slot := -1

var _layers := []
var _hidden := {}
# Transform original de cada indice oculto, alineado con _layers, para desocultar.
var _saved := {}

func _ready() -> void:
	# Las capas cuelgan de Criopods1 (el nodo con el transform del anillo), no del
	# root; hay que recorrer el subarbol.
	var pending := [self]
	while not pending.empty():
		var node = pending.pop_back()
		if node is MultiMeshInstance and node.multimesh != null:
			# Los sub-recursos MultiMesh del .tscn se comparten entre instancias de
			# la escena: ocultar un slot se filtraba a todas las copias. Duplicar
			# aca deja el estado del bloqueo aislado por instancia.
			node.multimesh = node.multimesh.duplicate()
			_layers.append(node)
		for child in node.get_children():
			pending.append(child)
	if blocked_slot >= 0:
		block_slot(blocked_slot)

func block_slot(slot: int) -> void:
	var index := instance_for_slot(slot)
	if index < 0:
		return
	if blocked_slot >= 0 and blocked_slot != slot:
		unblock_slot(blocked_slot)
	blocked_slot = slot
	# Si todavia no termino _ready(), no hay capas que mover: se reaplica al final.
	if _layers.empty() or _hidden.has(index):
		return
	_hidden[index] = true
	var saved := []
	for layer in _layers:
		saved.append(layer.multimesh.get_instance_transform(index))
		layer.multimesh.set_instance_transform(index, Transform(Basis.IDENTITY, HIDDEN_ORIGIN))
	_saved[index] = saved

func unblock_slot(slot: int) -> void:
	var index := instance_for_slot(slot)
	if index >= 0:
		_unblock_index(index)
	if blocked_slot == slot:
		blocked_slot = -1

func _unblock_index(index: int) -> void:
	if not _hidden.has(index):
		return
	_hidden.erase(index)
	var saved = _saved.get(index, null)
	_saved.erase(index)
	if saved == null:
		return
	for i in range(_layers.size()):
		if i < saved.size():
			_layers[i].multimesh.set_instance_transform(index, saved[i])

func get_blocked_slot() -> int:
	return blocked_slot

func instance_for_slot(slot: int) -> int:
	if slot < 0 or slot >= slot_to_instance.size():
		return -1
	return int(slot_to_instance[slot])

func hidden_instance_count() -> int:
	return _hidden.size()
