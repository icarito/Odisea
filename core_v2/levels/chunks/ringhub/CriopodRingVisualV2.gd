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
	# Gateable: Godot 3 NO puede hornear MultiMeshInstance, asi que los anillos con
	# env var se cambian por pods instanciados (MeshInstance, bakeables). Apagado por
	# default: si cuesta draw calls en la Anbernic, se saca del dev.sh.
	if OS.get_environment("ODISEA_CRIOPOD_RING_INSTANCED") in ["1", "true", "yes", "on"]:
		_instance_bakeable_pods()
	if OS.get_environment("ODISEA_CRIO_DIAG") != "":
		_diag_dump("ready")
		_diag_later()


# Cambia las capas MultiMesh (no bakeables en Godot 3) por pods CriopodParallax
# instanciados, que sí son MeshInstance con UV2 y reciben el lightmap.
func _instance_bakeable_pods() -> void:
	var shell_layer: MultiMeshInstance = null
	for layer in _layers:
		if String(layer.name) == "Shell":
			shell_layer = layer
			break
	if shell_layer == null:
		return
	var pod_scene: PackedScene = load("res://core_v2/props/criopod/CriopodParallax.tscn")
	if pod_scene == null:
		return
	var count: int = shell_layer.multimesh.instance_count
	for i in range(count):
		if _hidden.has(i):
			continue
		var xf: Transform = shell_layer.global_transform * shell_layer.multimesh.get_instance_transform(i)
		var pod = pod_scene.instance()
		add_child(pod)
		pod.global_transform = xf
		# El BakedLightmap._find_meshes_and_lights saltea hijos con owner==null
		# ("maybe a helper"): sin owner, los pods instanciados no se hornean. En el
		# bake no hay current_scene, asi que se usa la raiz real del arbol del nivel.
		var scene_root = _scene_root()
		if scene_root != null and pod.owner == null:
			pod.owner = scene_root
		# Visual-only: sin colision propia (el anillo MultiMesh tampoco la tenia).
		for c in pod.get_children():
			if c is StaticBody or c is KinematicBody:
				c.queue_free()
	for layer in _layers:
		layer.visible = false
	set_meta("ring_instanced_bake", true)
	print("[criopods] ", get_path(), " instanced pods=", count, " (layers=", _layers.size(), ")")


func _scene_root() -> Node:
	var n: Node = self
	while n.get_parent() != null and is_instance_valid(n.get_parent()) and n.get_parent() != get_tree().root:
		n = n.get_parent()
	if n == get_tree().root:
		return null
	return n


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
