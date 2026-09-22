extends Spatial
class_name CriopodRingVisualV2

# FD-314 - Visual barato del anillo de criopods decorativos de RingHub.
#
# Los anillos se resuelven con MultiMesh (shell / glass / cards) en vez de las ~29
# escenas CriopodParallax con su propio StaticBody. Excepcion: el anillo del piso
# de despertar se hornea con la geometria mergeada (RingHub_Criopods1_visual.tscn,
# tools/bake_ringhub_criopods1_merged.gd) porque su MultiMeshInstance no se dibuja
# en el GLES3 mobile del Anbernic aunque los anillos superiores si.
#
# El pod funcional de despertar (Criopod_Vert) ocupa el slot 37: el anillo mergeado
# lo omite al hornear y los anillos MultiMesh ocultan esa instancia con
# `block_slot(slot)`.

# Ocultar colapsando la instancia en su propio origen (escala ~0) en vez de
# teletransportarla a -10000: moverla lejos infla el AABB del MultiMesh a ~10000
# unidades verticales. Colapsada, el AABB queda ajustado al anillo y la instancia
# es igual de invisible.
static func _hidden_transform(origin: Vector3) -> Transform:
	return Transform(Basis.IDENTITY.scaled(Vector3(0.0001, 0.0001, 0.0001)), origin)

# Margen de culling de las 3 capas. El anillo de despertar (Criopods_Visual) tiene
# datos correctos (29 instancias a radio 12, AABB y materiales validados en device)
# pero el driver GLES3 mobile del Anbernic descartaba el MultiMeshInstance entero,
# mientras los anillos superiores (mismo mesh/script) se dibujaban. Con el margen
# el frustum test no lo descarta. Es geometria decorativa sin gameplay: el margen
# no cambia colision.
const RING_CULL_MARGIN := 3.0

# slot del RadialScatter (0..item_count-1) -> indice de instancia (0..N-1); -1 si
# ese slot no tiene pod decorativo.
export(Array, int) var slot_to_instance := []

# Slot bloqueado por el despertar. Es export para que el visual mergeado del piso
# de despertar pueda grabarlo en la escena y CriopodRingCollisionV2 libere la caja
# correspondiente sin esperar a RingHubWakeup.
export(int) var blocked_slot := -1

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
			# aca deja el estado del bloqueo aislado por instancia. La copia se
			# reescribe desde una lectura previa para no depender de que duplicate()
			# arrastre el buffer de transforms.
			var keep: Array = []
			var count: int = node.multimesh.instance_count
			for i in range(count):
				keep.append(node.multimesh.get_instance_transform(i))
			var copy: MultiMesh = node.multimesh.duplicate()
			for i in range(count):
				copy.set_instance_transform(i, keep[i])
			node.multimesh = copy
			node.extra_cull_margin = RING_CULL_MARGIN
			_layers.append(node)
		for child in node.get_children():
			pending.append(child)
	if blocked_slot >= 0:
		block_slot(blocked_slot)
	if OS.get_environment("ODISEA_CRIO_DIAG") != "":
		_diag_dump("ready")
		_diag_later()


func block_slot(slot: int) -> void:
	var index := instance_for_slot(slot)
	if index < 0:
		return
	if blocked_slot >= 0 and blocked_slot != slot:
		unblock_slot(blocked_slot)
	blocked_slot = slot
	if _hidden.has(index):
		return
	# El estado autoritativo es el indice bloqueado, aun sin capas que mover: el
	# visual mergeado del piso de despertar ya no trae esa instancia en la geometria.
	_hidden[index] = true
	if _layers.empty():
		_saved[index] = []
		return
	var saved := []
	for layer in _layers:
		var original: Transform = layer.multimesh.get_instance_transform(index)
		saved.append(original)
		layer.multimesh.set_instance_transform(index, _hidden_transform(original.origin))
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


# ODISEA_CRIO_DIAG=1: vuelca a user://crio_diag.txt el estado de cada capa MultiMesh.
# En release no hay eval, y el device es donde aparecen las diferencias del driver.
func _diag_later() -> void:
	var timer := get_tree().create_timer(1.0)
	yield(timer, "timeout")
	_diag_dump("t+1s")

func _diag_dump(tag: String) -> void:
	if OS.get_environment("ODISEA_CRIO_DIAG") == "":
		return
	var f := File.new()
	if f.open("user://crio_diag.txt", File.READ_WRITE) != OK and f.open("user://crio_diag.txt", File.WRITE) != OK:
		return
	f.seek_end()
	f.store_string("=== %s %s visible=%s in_tree=%s\n" % [
		tag, String(get_path()), str(visible), str(is_visible_in_tree())])
	for layer in _layers:
		var mm: MultiMesh = layer.multimesh
		f.store_string("  %s layers=%d cull=%.1f count=%d fmt=%d/%d/%d visible=%s aabb=%s\n" % [
			layer.name, layer.layers, layer.extra_cull_margin, mm.instance_count,
			mm.transform_format, mm.color_format, mm.custom_data_format,
			str(layer.is_visible_in_tree()), str(mm.get_aabb())])
		f.store_string("    t0=%s mat=%s\n" % [
			str(mm.get_instance_transform(0).origin), str(layer.material_override)])
	f.close()
