extends GdUnitTestSuite

# FD-316 (tarea Y): batching de los anillos de criopods decorativos de RingHub.
#
# En tier LOW el anillo deja de instanciar un CriopodParallax por pod (3 MeshInstance ->
# 3 draws cada uno) y usa sus capas MultiMesh horneadas, que agrupan los pods por
# (mesh, material): 1 draw por superficie y todas las instancias en el mismo draw. Fuera
# del tier LOW se conservan los pods instanciados porque son MeshInstance bakeables y el
# batcheo pierde su lightmap horneado (Godot 3 no hornea MultiMeshInstance).
#
# El pod funcional de despertar (Criopod_Vert) es un nodo aparte del visual del anillo:
# el batching solo toca el decorado y el slot bloqueado sigue colapsandose con block_slot().

const RingScene = preload("res://core_v2/levels/chunks/ringhub/RingHub_Criopods3_visual.tscn")
const LevelScene = preload("res://core_v2/levels/RingHub_Level.tscn")
const InstancedEnv := "ODISEA_CRIOPOD_RING_INSTANCED"


func _gate():
	return get_node("/root/GLES3VendorGate")


func _set_env(value: String) -> String:
	var previous: String = OS.get_environment(InstancedEnv)
	OS.set_environment(InstancedEnv, value)
	return previous


# Draws estimados de la geometria VISIBLE del subarbol: 1 por superficie (en un MultiMesh
# las N instancias van en el mismo draw). Espeja el censo de RemoteSimClient.
func _visible_estimated_draws(root: Node) -> int:
	var total := 0
	var stack: Array = [root]
	while not stack.empty():
		var node = stack.pop_back()
		if node is Spatial and not (node as Spatial).is_visible_in_tree():
			continue
		if node is MultiMeshInstance:
			var mm = (node as MultiMeshInstance).multimesh
			if mm != null and mm.mesh != null:
				total += int(max(1, mm.mesh.get_surface_count()))
		elif node is MeshInstance:
			var mesh = (node as MeshInstance).mesh
			if mesh != null:
				total += int(max(1, mesh.get_surface_count()))
		for child in node.get_children():
			stack.append(child)
	return total


func _count_children_named(root: Node, prefix: String) -> int:
	var total := 0
	for child in root.get_children():
		if String(child.name).begins_with(prefix):
			total += 1
	return total


# Los pods existen como anclas del lightmap horneado pero no deben aportar draws.
func _pods_are_hidden(root: Node) -> bool:
	for child in root.get_children():
		if not String(child.name).begins_with("Pod_"):
			continue
		if (child as Spatial).visible:
			return false
	return true


func _multimesh_layers(root: Node) -> Array:
	var layers: Array = []
	var stack: Array = [root]
	while not stack.empty():
		var node = stack.pop_back()
		if node is MultiMeshInstance and (node as MultiMeshInstance).multimesh != null:
			layers.append(node)
		for child in node.get_children():
			stack.append(child)
	return layers


func test_low_tier_ring_batches_pods_into_multimesh() -> void:
	var gate = _gate()
	var previous_force: bool = gate.force_gate
	var previous_env: String = _set_env("")
	gate.force_gate = true
	var ring = auto_free(RingScene.instance())
	add_child(ring)
	yield(get_tree(), "idle_frame")

	# Las capas MultiMesh (Shell/Glass/PersonCards) son la representacion visible y el
	# anillo de 23 pods baja a 1 draw por superficie (3 en total).
	var layers := _multimesh_layers(ring)
	assert_int(layers.size()).is_equal(3)
	for layer in layers:
		assert_bool(layer.visible).is_true()
		assert_int(layer.multimesh.instance_count).is_equal(23)
	# Los pods siguen existiendo (anclas ocultas del BakedLightmap) pero no dibujan.
	assert_int(_count_children_named(ring, "Pod_")).is_equal(23)
	assert_bool(_pods_are_hidden(ring)).is_true()
	assert_int(_visible_estimated_draws(ring)).is_equal(3)

	gate.force_gate = previous_force
	_set_env(previous_env)


func test_normal_tier_ring_instances_bakeable_pods() -> void:
	var gate = _gate()
	var previous_force: bool = gate.force_gate
	var previous_env: String = _set_env("")
	gate.force_gate = false
	var ring = auto_free(RingScene.instance())
	add_child(ring)
	yield(get_tree(), "idle_frame")

	# Fuera de LOW se conserva un pod bakeable visible por slot; las capas MultiMesh
	# quedan ocultas para que no dupliquen la geometria.
	assert_int(_count_children_named(ring, "Pod_")).is_equal(23)
	assert_bool(_pods_are_hidden(ring)).is_false()
	for layer in _multimesh_layers(ring):
		assert_bool(layer.visible).is_false()
	assert_int(_visible_estimated_draws(ring)).is_greater(3)

	gate.force_gate = previous_force
	_set_env(previous_env)


func test_instanced_env_forces_both_paths() -> void:
	var gate = _gate()
	var previous_force: bool = gate.force_gate
	var previous_env: String = _set_env("0")
	gate.force_gate = false
	var batched = auto_free(RingScene.instance())
	add_child(batched)
	yield(get_tree(), "idle_frame")
	assert_bool(_pods_are_hidden(batched)).is_true()
	for layer in _multimesh_layers(batched):
		assert_bool(layer.visible).is_true()
	assert_int(_visible_estimated_draws(batched)).is_equal(3)

	_set_env("1")
	gate.force_gate = true
	var instanced = auto_free(RingScene.instance())
	add_child(instanced)
	yield(get_tree(), "idle_frame")
	assert_bool(_pods_are_hidden(instanced)).is_false()
	for layer in _multimesh_layers(instanced):
		assert_bool(layer.visible).is_false()
	assert_int(_visible_estimated_draws(instanced)).is_greater(3)

	gate.force_gate = previous_force
	_set_env(previous_env)


func test_interactive_pod_stays_a_separate_node() -> void:
	var gate = _gate()
	var previous_force: bool = gate.force_gate
	var previous_env: String = _set_env("")
	gate.force_gate = true
	var level = auto_free(LevelScene.instance())
	add_child(level)
	yield(get_tree(), "idle_frame")

	var visual: Node = level.get_node_or_null("ScaffoldStreamRoot/Criopods_Visual")
	assert_object(visual).is_not_null()
	# El pod que se abre/anima vive fuera del visual del anillo decorativo.
	var pod: Node = level.get_node_or_null("Criopod_Vert")
	assert_object(pod).is_not_null()
	assert_bool(visual.is_a_parent_of(pod)).is_false()
	# Cada anillo del nivel ensamblado queda en 1 draw por superficie (shell/glass/cards).
	assert_int(_visible_estimated_draws(visual)).is_equal(3)
	for ring_name in ["Criopods3", "Criopods4", "Criopods5", "Criopods6"]:
		var ring: Node = level.get_node_or_null("ScaffoldStreamRoot/Criopods_Visual_%s" % ring_name)
		assert_object(ring).is_not_null()
		assert_int(_visible_estimated_draws(ring)).is_equal(3)

	gate.force_gate = previous_force
	_set_env(previous_env)
