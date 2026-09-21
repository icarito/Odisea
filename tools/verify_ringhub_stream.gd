extends SceneTree

# Verificador headless de FD-314: carga el shell de RingHub y comprueba que la
# superestructura y los criopods quedaron cableados como espera el streaming.
# No agrega la escena al arbol: no dispara _ready ni depende de autoloads.

const LEVEL := "res://core_v2/levels/RingHub_Level.tscn"

var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  OK   " + msg)
	else:
		_failures += 1
		print("  FAIL " + msg)

func _run() -> void:
	var packed: PackedScene = load(LEVEL)
	if packed == null:
		push_error("[verify_ringhub] no pude cargar %s" % LEVEL)
		quit(1)
		return
	var root: Node = packed.instance()

	print("[verify_ringhub] shell")
	var slots: Node = root.get_node_or_null("Hub/Criopods")
	_check(slots != null, "Hub/Criopods existe")
	if slots != null:
		_check(slots.get_child_count() == 29, "Hub/Criopods tiene 29 slots (%d)" % slots.get_child_count())
		var mesh_count := 0
		var body_count := 0
		var spatial_count := 0
		for child in slots.get_children():
			if child is MeshInstance:
				mesh_count += 1
			if child is Spatial:
				spatial_count += 1
			for sub in child.get_children():
				if sub is StaticBody:
					body_count += 1
		_check(mesh_count == 0, "0 MeshInstance en los slots (%d)" % mesh_count)
		_check(body_count == 0, "0 StaticBody en los slots (%d)" % body_count)
		_check(spatial_count == 29, "29 Spatial en los slots (%d)" % spatial_count)

	var stream: Node = root.get_node_or_null("ScaffoldStreamRoot")
	_check(stream != null, "ScaffoldStreamRoot existe")
	var chunk_count := 0
	var visual_meshes := 0
	var cri_visual: Node = null
	if stream != null:
		var pending := [stream]
		while not pending.empty():
			var node = pending.pop_back()
			if node.get_script() != null and node.has_method("request_load"):
				chunk_count += 1
			for child in node.get_children():
				pending.append(child)
		for group_name in ["SpiralStairs", "HubSpokes", "SpiralWalkways"]:
			var group: Node = stream.get_node_or_null("Group_%s" % group_name)
			_check(group != null, "Group_%s existe" % group_name)
			if group == null:
				continue
			var visual: Node = group.get_node_or_null("Visual")
			if visual is MeshInstance and (visual as MeshInstance).mesh != null:
				visual_meshes += 1

		cri_visual = stream.get_node_or_null("Criopods_Visual")
		_check(stream.get_node_or_null("Chunk_Criopods") != null, "Chunk_Criopods existe")
		_check(cri_visual != null, "Criopods_Visual existe")
		var upper_rings := 0
		for entry in ["Criopods3", "Criopods4", "Criopods5", "Criopods6"]:
			var upper: Node = stream.get_node_or_null("Criopods_Visual_%s" % entry)
			var upper_chunk: Node = stream.get_node_or_null("Chunk_%s" % entry)
			_check(upper != null, "Criopods_Visual_%s existe" % entry)
			_check(upper_chunk != null, "Chunk_%s existe" % entry)
			if upper != null:
				upper_rings += 1
		_check(upper_rings == 4, "4 anillos de criopods superiores (%d)" % upper_rings)

	_check(visual_meshes == 3, "3 visuales de grupo (%d)" % visual_meshes)
	_check(chunk_count == 22, "22 chunks (17 sectores + 5 anillos de criopods): %d" % chunk_count)

	print("[verify_ringhub] criopods visual")
	if cri_visual != null:
		var multi: Array = []
		var pending := [cri_visual]
		while not pending.empty():
			var node = pending.pop_back()
			if node is MultiMeshInstance:
				multi.append(node)
			for child in node.get_children():
				pending.append(child)
		_check(multi.size() == 3, "3 MultiMeshInstance en el visual (%d)" % multi.size())
		for mmi in multi:
			_check(mmi.multimesh != null and mmi.multimesh.instance_count == 29,
				"%s: 29 instancias" % mmi.name)
		_check("slot_to_instance" in cri_visual, "expone slot_to_instance")
		if "slot_to_instance" in cri_visual:
			_check(cri_visual.slot_to_instance.size() == 40, "slot_to_instance cubre 40 slots")
			_check(cri_visual.slot_to_instance[1] == 0, "slot 1 -> instancia 0")

	print("[verify_ringhub] colision de criopods")
	var body_packed: PackedScene = load("res://core_v2/levels/chunks/ringhub/RingHub_Criopods_body.tscn")
	if body_packed != null:
		var body: Node = body_packed.instance()
		var shapes := 0
		for child in body.get_node("Criopods1/StaticBody").get_children():
			if child is CollisionShape:
				shapes += 1
		_check(shapes == 29, "29 cajas de pod (%d)" % shapes)
		_check(String(body.slot_provider_path) == "../../Criopods_Visual", "provider path correcto")
		_check(body.slot_to_pod.size() == 40, "slot_to_pod cubre 40 slots")

	print("[verify_ringhub] alineacion slot <-> instancia MultiMesh")
	if cri_visual != null and slots != null:
		# La escena no esta en el arbol, asi que global_transform no es fiable:
		# ambos lados se comparan en espacio del nodo del anillo (Hub/Criopods y
		# Criopods1 comparten transform).
		var ring_node: Spatial = cri_visual.get_node_or_null("Criopods1")
		var shell: MultiMeshInstance = ring_node.get_node_or_null("Shell") if ring_node != null else null
		var max_delta := 0.0
		var checked := 0
		if shell != null and shell.multimesh != null:
			for child in slots.get_children():
				var item: Spatial = child
				var slot := int(String(item.name).substr(5)) if String(item.name).begins_with("Item_") else -1
				if slot < 0:
					continue
				var index: int = cri_visual.instance_for_slot(slot)
				if index < 0:
					continue
				checked += 1
				var expected: Vector3 = slots.transform * item.transform.origin
				var actual: Vector3 = ring_node.transform * shell.multimesh.get_instance_transform(index).origin
				var delta: float = expected.distance_to(actual)
				if delta > 0.01:
					print("    slot %d -> inst %d esperado %s real %s (delta %.3f)" % [slot, index, str(expected), str(actual), delta])
				max_delta = max(max_delta, delta)
		_check(checked > 0, "slots comparables (%d)" % checked)
		_check(max_delta < 0.001, "slot e instancia coinciden (delta max %.5f m)" % max_delta)

	print("[verify_ringhub] anillos superiores")
	var expected := {"Criopods3": 24, "Criopods4": 27, "Criopods5": 23, "Criopods6": 28}
	for ring_name in expected.keys():
		var ring_packed: PackedScene = load("res://core_v2/levels/chunks/ringhub/RingHub_%s_body.tscn" % ring_name)
		if ring_packed == null:
			_check(false, "carga %s" % ring_name)
			continue
		var inst: Node = ring_packed.instance()
		var shapes := 0
		var walk := [inst]
		while not walk.empty():
			var n = walk.pop_back()
			if n is CollisionShape:
				shapes += 1
			for c in n.get_children():
				walk.append(c)
		_check(shapes == expected[ring_name], "%s: %d cajas (%d)" % [ring_name, shapes, expected[ring_name]])

	print("[verify_ringhub] %s" % ("TODO OK" if _failures == 0 else "%d FALLAS" % _failures))
	quit(0 if _failures == 0 else 1)
