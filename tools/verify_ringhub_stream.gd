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
			# FD-314 follow-up: el visual del grupo YA NO es un MeshInstance de
			# grupo (una malla del anillo entero que el frustum nunca podia
			# descartar); viaja adentro de cada _body.tscn de sector, junto con
			# su colision. El grupo no debe tener ningun "Visual" propio.
			_check(group.get_node_or_null("Visual") == null, "Group_%s sin Visual propio" % group_name)

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

	_check(chunk_count == 23, "23 chunks (18 sectores + 5 anillos de criopods): %d" % chunk_count)

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

	print("[verify_ringhub] chunks con colision horneada en compound")
	# Cada chunk body (18 sectores + 5 anillos) usa CompoundChunkBodyV2 con un
	# CompoundBytesV2 valido: UNA shape en vez de las primitivas apiladas. La
	# excepcion es un sector puramente decorativo (visual sin colision propia,
	# ver SECTOR_NO_COLLISION): ese body es un StaticBody liso sin script.
	var body_script := "res://core_v2/levels/chunks/CompoundChunkBodyV2.gd"
	var bytes_script := "res://core_v2/levels/chunks/CompoundBytesV2.gd"
	var visual_script := "res://core_v2/levels/interiors/RingHub_SpiralWalkways_sector_06_body.tscn"
	var dirs := [
		["res://core_v2/levels/chunks/ringhub/", "RingHub_Criopods*_body.tscn"],
		["res://core_v2/levels/interiors/", "RingHub_*_sector_*_body.tscn"],
	]
	var chunks := 0
	var visual_carried := 0
	for pair in dirs:
		var dir := Directory.new()
		if dir.open(pair[0]) != OK:
			_check(false, "abre %s" % pair[0])
			continue
		dir.list_dir_begin(true, true)
		var fname := dir.get_next()
		while fname != "":
			if fname.match(pair[1]):
				chunks += 1
				var full_path := String(pair[0]) + fname
				var chunk_packed: PackedScene = load(full_path)
				if chunk_packed == null:
					_check(false, "carga %s" % fname)
				else:
					var inst: Node = chunk_packed.instance()
					_check(inst is StaticBody, "%s es StaticBody" % fname)
					var mesh_inst: Node = inst.get_node_or_null("Visual")
					if mesh_inst is MeshInstance and (mesh_inst as MeshInstance).mesh != null:
						visual_carried += 1
					if full_path == visual_script:
						_check(inst.get_script() == null, "%s no tiene colision, es visual puro" % fname)
					else:
						_check(inst.get_script() != null and String(inst.get_script().resource_path) == body_script,
							"%s usa CompoundChunkBodyV2" % fname)
						var res: Resource = inst.get("compound")
						_check(res != null and res.get_script() != null and String(res.get_script().resource_path) == bytes_script,
							"%s tiene CompoundBytesV2" % fname)
						var primitives := 0
						var walk := [inst]
						while not walk.empty():
							var n = walk.pop_back()
							if n is CollisionShape:
								primitives += 1
							for c in n.get_children():
								walk.append(c)
						_check(primitives == 0, "%s no apila primitivas (%d)" % [fname, primitives])
						if res != null and "bytes" in res:
							var comp := Box3DCompound.new()
							var bytes: PoolByteArray = res.get("bytes")
							_check(bytes.size() >= 8 and comp.is_valid_compound(bytes), "%s: bytes validos" % fname)
							_check(int(res.get("child_count")) > 0, "%s: child_count > 0" % fname)
			fname = dir.get_next()
		dir.list_dir_end()
	_check(chunks == 23, "23 chunk bodies con compound (%d)" % chunks)
	# FD-314 follow-up: los 18 sectores de scaffold cargan su malla junto con la
	# colision (una sola fuente de verdad); los 5 anillos de criopods siguen con
	# su propio esquema de visual (MultiMesh/merge en el shell, ver arriba).
	_check(visual_carried == 18, "18 sectores llevan su propio Visual (%d)" % visual_carried)

	# 1:1 con las cajas viejas: el anillo de despertar tenia 29 y omite el pod del
	# slot funcional (26), los superiores conservan sus cajas.
	var expected_children := {"RingHub_Criopods": 28, "RingHub_Criopods3": 23, "RingHub_Criopods4": 27,
			"RingHub_Criopods5": 23, "RingHub_Criopods6": 28}
	for ring_name in expected_children.keys():
		var ring_packed2: PackedScene = load("res://core_v2/levels/chunks/ringhub/%s_body.tscn" % ring_name)
		if ring_packed2 == null:
			_check(false, "carga %s" % ring_name)
			continue
		var inst_ring: Node = ring_packed2.instance()
		var res_ring: Resource = inst_ring.get("compound")
		var got := int(res_ring.get("child_count")) if res_ring != null else -1
		_check(got == expected_children[ring_name],
			"%s: %d hijos (%d)" % [ring_name, got, expected_children[ring_name]])

	print("[verify_ringhub] %s" % ("TODO OK" if _failures == 0 else "%d FALLAS" % _failures))
	quit(0 if _failures == 0 else 1)
