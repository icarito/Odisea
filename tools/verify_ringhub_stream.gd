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

	print("[verify_ringhub] criopods visual (piso de despertar, geometria mergeada)")
	if cri_visual != null:
		# El anillo de despertar se hornea como 3 MeshInstance merged (FD-314 follow-up):
		# su MultiMeshInstance no se dibujaba en el GLES3 mobile del device, mientras
		# los anillos superiores si. Aca ya no debe haber MultiMeshInstance.
		var meshes: Array = []
		var multis: Array = []
		var pending := [cri_visual]
		while not pending.empty():
			var node = pending.pop_back()
			if node is MeshInstance:
				meshes.append(node)
			elif node is MultiMeshInstance:
				multis.append(node)
			for child in node.get_children():
				pending.append(child)
		_check(multis.size() == 0, "sin MultiMeshInstance en el anillo de despertar (%d)" % multis.size())
		_check(meshes.size() == 3, "3 MeshInstance merged (%d)" % meshes.size())
		for mi in meshes:
			var verts := 0
			if mi.mesh != null:
				for s in range(mi.mesh.get_surface_count()):
					verts += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
			_check(verts > 0, "%s: mesh con geometria (%d verts)" % [mi.name, verts])
		_check(int(cri_visual.get("blocked_slot")) == 37, "blocked_slot = 37 grabado")
		_check(cri_visual.has_method("get_blocked_slot"), "expone get_blocked_slot")

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

	print("[verify_ringhub] merge del anillo de despertar")
	# La fuente MultiMesh sigue existiendo (es la entrada del horneado) y el slot de
	# despertar debe mapear a la instancia que el merge omite.
	var src_packed: PackedScene = load("res://core_v2/levels/chunks/ringhub/RingHub_Criopods_visual.tscn")
	if src_packed != null:
		var src: Node = src_packed.instance()
		var shell: MultiMeshInstance = src.get_node_or_null("Criopods1/Shell")
		if shell != null and shell.multimesh != null:
			_check(shell.multimesh.instance_count == 29, "fuente: 29 instancias (%d)" % shell.multimesh.instance_count)
			var aabb: AABB = shell.multimesh.get_aabb()
			_check(aabb.size.x > 25.0 and aabb.size.z > 25.0, "fuente: anillo a radio 12.7 (size %s)" % str(aabb.size))
		_check(src.instance_for_slot(37) == 26, "fuente: slot 37 -> instancia 26 (la que se omite)")
	if cri_visual != null and slots != null:
		# El merge debe cubrir el anillo: el AABB del Shell merged tiene que medir
		# aproximadamente el diametro del anillo (menos el pod omitido).
		var merged_shell: MeshInstance = cri_visual.get_node_or_null("Criopods1/Shell")
		if merged_shell != null and merged_shell.mesh != null:
			var ma: AABB = merged_shell.mesh.get_aabb()
			_check(ma.size.x > 25.0 and ma.size.z > 25.0,
				"merged: anillo completo (size %s)" % str(ma.size))
			_check(abs(ma.position.y - 0.2) < 0.1, "merged: apoyado en el deck (y %.3f)" % ma.position.y)

	print("[verify_ringhub] anillos superiores")
	var expected := {"Criopods3": 23, "Criopods4": 27, "Criopods5": 23, "Criopods6": 28}
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
