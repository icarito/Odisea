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

func _ready() -> void:
	# Las capas cuelgan de Criopods1 (el nodo con el transform del anillo), no del
	# root; hay que recorrer el subarbol.
	var pending := [self]
	while not pending.empty():
		var node = pending.pop_back()
		if node is MultiMeshInstance and node.multimesh != null:
			_layers.append(node)
		for child in node.get_children():
			pending.append(child)

func block_slot(slot: int) -> void:
	var index := instance_for_slot(slot)
	if index < 0:
		return
	blocked_slot = slot
	_hidden[index] = true
	for layer in _layers:
		layer.multimesh.set_instance_transform(index, Transform(Basis(), HIDDEN_ORIGIN))

func get_blocked_slot() -> int:
	return blocked_slot

func instance_for_slot(slot: int) -> int:
	if slot < 0 or slot >= slot_to_instance.size():
		return -1
	return int(slot_to_instance[slot])

func hidden_instance_count() -> int:
	return _hidden.size()
