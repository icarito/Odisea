extends GdUnitTestSuite

# FD-314: cobertura del streaming de la superestructura de RingHub.
#
# El shell de RingHub ya no trae la colision del scaffold en el arranque: cada
# sector entra como StreamedSceneChunkV2 cuando el jugador se acerca. Estos tests
# fijan el contrato del componente y el cableado del shell sin depender de la
# cinematica de despertar (cubierta por test_ringhub_wakeup.gd) ni del replay
# (cubierto por ringhub_level.oys -> test_replay, que ya corre RingHub).

const RingHubScene = preload("res://core_v2/levels/RingHub_Level.tscn")
const ChunkScript = preload("res://core_v2/levels/chunks/StreamedSceneChunkV2.gd")
const HubSpokeBody = preload("res://core_v2/levels/interiors/RingHub_HubSpokes_sector_00_body.tscn")
const CriopodVisual = preload("res://core_v2/levels/chunks/ringhub/RingHub_Criopods_visual.tscn")
const CriopodBody = preload("res://core_v2/levels/chunks/ringhub/RingHub_Criopods_body.tscn")


func _count_static_bodies(node: Node) -> int:
	var total := 0
	var pending := [node]
	while not pending.empty():
		var current = pending.pop_back()
		if current is StaticBody:
			total += 1
		for child in current.get_children():
			pending.append(child)
	return total


func test_shell_has_no_scaffold_collision_and_has_sector_visuals() -> void:
	var level = auto_free(RingHubScene.instance())
	add_child(level)
	yield(get_tree(), "idle_frame")

	var slots: Node = level.get_node_or_null("Hub/Criopods")
	assert_object(slots).is_not_null()
	# El anillo decorativo ya no aporta colision al shell: los pods quedan como
	# Spatial vacios que RingHubWakeup usa para elegir el slot de despertar.
	assert_int(_count_static_bodies(slots)).is_equal(0)

	var stream: Node = level.get_node_or_null("ScaffoldStreamRoot")
	assert_object(stream).is_not_null()
	var visuals := 0
	var chunks := 0
	var pending := [stream]
	while not pending.empty():
		var current = pending.pop_back()
		if current.get_script() != null and current.has_method("request_load"):
			chunks += 1
		for child in current.get_children():
			pending.append(child)
	# El visual del scaffold es uno POR SECTOR (Visual_NN) y vive siempre en el shell:
	# la malla de grupo abarcaba los 360 grados y el frustum no la podia descartar.
	# No va adentro del chunk: ese streamea por distancia (trigger_radius 15) y en un
	# domo donde se ve hasta 35 m eso borra el andamiaje del otro lado del anillo.
	for group_name in ["SpiralStairs", "HubSpokes", "SpiralWalkways"]:
		var group = stream.get_node_or_null("Group_%s" % group_name)
		if group == null:
			continue
		for child in group.get_children():
			if child is MeshInstance and (child as MeshInstance).mesh != null \
					and String(child.name).begins_with("Visual_"):
				visuals += 1
	assert_int(visuals).is_equal(18)
	# 18 sectores del scaffold + 5 anillos de criopods (piso 1 + pisos 2-5).
	# 18, no 17: SpiralWalkways sector 6 tenia malla visible y ningun cuerpo de
	# colision porque el baker repartia las shapes por el origen de cada una y
	# ninguna nacia en ese sector. Ver test_todo_visual_tiene_chunk_de_colision.
	assert_int(chunks).is_equal(23)
	# Los pisos 2-5 tambien llevan su anillo de criopods decorativos.
	for ring_name in ["Criopods3", "Criopods4", "Criopods5", "Criopods6"]:
		assert_object(stream.get_node_or_null("Criopods_Visual_%s" % ring_name)).is_not_null()
		assert_object(stream.get_node_or_null("Chunk_%s" % ring_name)).is_not_null()
	assert_object(level.get_node_or_null("ScaffoldStreamRoot/Criopods_Visual")).is_not_null()
	assert_bool(level.get_node_or_null("ScaffoldStreamRoot/Chunk_Criopods") != null).is_true()


func test_pilot_scale_matches_world_scale() -> void:
	# El hub esta a 1:1 (igual que Dome_Base); un Pilot escalado hacia que los
	# andamios y las barandas se vieran 1.5x mas altos.
	var level = auto_free(RingHubScene.instance())
	add_child(level)
	yield(get_tree(), "idle_frame")
	var pilot: Spatial = level.get_node("Pilot")
	assert_float(pilot.scale.x).is_equal_approx(1.0, 0.001)
	assert_float(pilot.scale.y).is_equal_approx(1.0, 0.001)
	assert_float(pilot.scale.z).is_equal_approx(1.0, 0.001)


func test_hub_tower_has_all_five_floor_rings() -> void:
	var level = auto_free(RingHubScene.instance())
	add_child(level)
	yield(get_tree(), "idle_frame")

	# Floor_1 es Hub/RingFloor; el ascenso necesita los otros cuatro.
	assert_object(level.get_node_or_null("Hub/RingFloor")).is_not_null()
	for level_index in [2, 3, 4, 5]:
		var node: Spatial = level.get_node_or_null("Hub/Floor_%d" % level_index)
		assert_object(node).is_not_null()
		assert_float(node.global_transform.origin.y).is_equal(4.5 * level_index)
		# El piso tiene que quedar construido (deck dibujable + colision) o el
		# ascenso por la escalera no tiene donde pararse.
		var combined: MeshInstance = node.get_node_or_null("CombinedMesh")
		assert_object(combined).is_not_null()
		assert_object(combined.mesh).is_not_null()
		assert_object(node.get_node_or_null("StaticBody")).is_not_null()


func test_chunk_loads_within_radius_and_releases_when_far() -> void:
	var player := Spatial.new()
	add_child(auto_free(player))

	var chunk: Spatial = ChunkScript.new()
	chunk.chunk_scene = HubSpokeBody
	chunk.trigger_center = Vector3.ZERO
	chunk.trigger_radius = 5.0
	chunk.release_margin = 2.0
	chunk.wait_for_startup_gate = false
	add_child(auto_free(chunk))
	chunk.player_path = chunk.get_path_to(player)

	assert_bool(chunk.is_chunk_loaded()).is_false()

	player.global_transform.origin = Vector3(0, 0, 0)
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	assert_bool(chunk.is_chunk_loaded()).is_true()
	assert_int(chunk.get_child_count()).is_equal(1)
	assert_int(_count_static_bodies(chunk)).is_equal(1)

	# Lejos y fuera del margen: el mundo fisico vuelve a quedar liviano.
	player.global_transform.origin = Vector3(100, 0, 0)
	yield(get_tree(), "physics_frame")
	yield(get_tree(), "physics_frame")
	assert_bool(chunk.is_chunk_loaded()).is_false()
	assert_int(_count_static_bodies(chunk)).is_equal(0)


func test_criopod_blocking_hides_instance_and_drops_its_box() -> void:
	var visual = auto_free(CriopodVisual.instance())
	add_child(visual)
	yield(get_tree(), "idle_frame")

	# slot 1 tiene pod decorativo (instancia 0) segun el layout horneado.
	assert_int(visual.instance_for_slot(1)).is_equal(0)
	assert_int(visual.hidden_instance_count()).is_equal(0)
	visual.block_slot(1)
	assert_int(visual.get_blocked_slot()).is_equal(1)
	assert_int(visual.hidden_instance_count()).is_equal(1)

	var body = auto_free(CriopodBody.instance())
	add_child(body)
	yield(get_tree(), "idle_frame")
	# La colision del anillo va horneada en UN compound que ya omite el pod del
	# slot funcional (29 cajas -> 28 hijos): no hay primitivas que liberar en
	# runtime, el compound es inmutable.
	var res: Resource = body.get("compound")
	assert_object(res).is_not_null()
	assert_int(int(res.get("child_count"))).is_equal(28)
	var shapes := 0
	for child in body.get_children():
		if child is CollisionShape:
			shapes += 1
			assert_object(child.shape).is_not_null()
	assert_int(shapes).is_equal(1)


func test_criopod_block_is_per_instance_and_reversible() -> void:
	var a = auto_free(CriopodVisual.instance())
	var b = auto_free(CriopodVisual.instance())
	add_child(a)
	add_child(b)
	yield(get_tree(), "idle_frame")

	# Los MultiMesh del .tscn vienen compartidos entre instancias de la escena;
	# el visual los duplica al entrar para aislar el bloqueo.
	assert_bool(a._layers[0].multimesh == b._layers[0].multimesh).is_false()

	a.block_slot(1)
	assert_int(a.hidden_instance_count()).is_equal(1)
	assert_int(b.hidden_instance_count()).is_equal(0)
	assert_int(b.get_blocked_slot()).is_equal(-1)

	a.unblock_slot(1)
	assert_int(a.hidden_instance_count()).is_equal(0)
	assert_int(a.get_blocked_slot()).is_equal(-1)

	# Cambiar de slot no deja el anterior oculto.
	a.block_slot(1)
	a.block_slot(2)
	assert_int(a.hidden_instance_count()).is_equal(1)
	assert_int(a.get_blocked_slot()).is_equal(2)
	assert_bool(a._hidden.has(a.instance_for_slot(2))).is_true()
	assert_bool(a._hidden.has(a.instance_for_slot(1))).is_false()


# El trigger es una esfera alrededor del CENTROIDE del chunk, pero su geometria se
# extiende mucho mas: con trigger_radius 15 y pasarelas que llegan a 27 m quedaba una
# corona donde el jugador pisa la malla y el chunk todavia no cargo — se atravesaba el
# piso estando encima. El radio tiene que cubrir la geometria que el chunk trae, asi
# que se compara contra ella y no contra un numero fijo: un re-bake que agrande un
# sector sin subir su radio vuelve a abrir el agujero, y en silencio.
func test_trigger_radius_cubre_la_geometria_del_chunk() -> void:
	var level = auto_free(RingHubScene.instance())
	add_child(level)
	yield(get_tree(), "idle_frame")

	var cortos := []
	var pending := [level]
	while not pending.empty():
		var current = pending.pop_back()
		if current.get_script() != null and current.has_method("request_load"):
			var extent := _chunk_extent(current)
			if extent <= 0.0:
				# Los anillos de criopods traen su colision en UN compound de Box3D
				# (CompoundChunkBodyV2), que no expone CollisionShape: medirlos por
				# shapes daba 0 y el chunk pasaba siempre. Se miden contra el visual
				# que les corresponde, que es el sintoma real — se ve y se atraviesa.
				extent = _sibling_visual_extent(current)
			if extent <= 0.0:
				cortos.append("%s: no se pudo medir ni por colision ni por visual" % current.name)
			elif float(current.get("trigger_radius")) < extent:
				cortos.append("%s: r=%.1f < geometria %.1f" % [
					current.name, current.get("trigger_radius"), extent])
		for child in current.get_children():
			pending.append(child)
	assert_array(cortos).is_empty()


# Radio que envuelve la colision del chunk, medido desde trigger_center en el espacio
# del propio chunk: el mismo en el que _physics_process compara la distancia.
func _chunk_extent(chunk: Node) -> float:
	var packed: PackedScene = chunk.get("chunk_scene")
	if packed == null:
		return 0.0
	var instance: Node = packed.instance()
	chunk.add_child(instance)
	var center: Vector3 = chunk.get("trigger_center")
	var to_local: Transform = chunk.global_transform.affine_inverse()
	var worst := 0.0
	var pending := [instance]
	while not pending.empty():
		var current = pending.pop_back()
		if current is CollisionShape and (current as CollisionShape).shape != null:
			var box: AABB = (current as CollisionShape).shape.get_debug_mesh().get_aabb()
			var xform: Transform = to_local * (current as CollisionShape).global_transform
			for corner in range(8):
				worst = max(worst, (xform.xform(box.get_endpoint(corner)) - center).length())
		for child in current.get_children():
			pending.append(child)
	chunk.remove_child(instance)
	instance.queue_free()
	return worst


# Cada sector que se DIBUJA tiene que tener su chunk de colision. El visual vive
# fijo en el shell y la colision streamea, asi que un sector con Visual_NN y sin
# Chunk_NN es geometria que se ve y nunca colisiona, a ninguna distancia — se
# atraviesa el piso estando encima. Asi estuvo SpiralWalkways/06, y el conteo
# global de chunks no lo delataba porque cuadraba con el total equivocado.
func test_todo_visual_tiene_chunk_de_colision() -> void:
	var level = auto_free(RingHubScene.instance())
	add_child(level)
	yield(get_tree(), "idle_frame")

	var stream: Node = level.get_node_or_null("ScaffoldStreamRoot")
	assert_object(stream).is_not_null()
	var huerfanos := []
	for group in stream.get_children():
		if not String(group.name).begins_with("Group_"):
			continue
		for child in group.get_children():
			var child_name := String(child.name)
			if not child_name.begins_with("Visual_"):
				continue
			if not (child is MeshInstance) or (child as MeshInstance).mesh == null:
				continue
			var sector := child_name.substr(7, child_name.length() - 7)
			if group.get_node_or_null("Chunk_%s" % sector) == null:
				huerfanos.append("%s/%s sin Chunk_%s" % [group.name, child_name, sector])
	assert_array(huerfanos).is_empty()


# Alcance del visual que acompania a un chunk, desde su trigger_center. Para los
# anillos de criopods el visual es un hermano "Criopods_Visual*" del mismo nombre;
# para los sectores de scaffold es el "Visual_NN" dentro del grupo.
func _sibling_visual_extent(chunk: Node) -> float:
	var parent: Node = chunk.get_parent()
	if parent == null:
		return 0.0
	var chunk_name := String(chunk.name)
	var visual: Node = null
	if chunk_name.begins_with("Chunk_Criopods"):
		var suffix := chunk_name.substr(6, chunk_name.length() - 6)
		visual = parent.get_node_or_null("Criopods_Visual_%s" % suffix)
		if visual == null and suffix == "Criopods":
			visual = parent.get_node_or_null("Criopods_Visual")
	else:
		visual = parent.get_node_or_null("Visual_%s" % chunk_name.substr(6, chunk_name.length() - 6))
	if visual == null:
		return 0.0
	var center: Vector3 = chunk.to_global(chunk.get("trigger_center"))
	var box := AABB()
	var first := true
	var pending := [visual]
	while not pending.empty():
		var current = pending.pop_back()
		if current is VisualInstance:
			var a: AABB = (current as VisualInstance).get_transformed_aabb()
			box = a if first else box.merge(a)
			first = false
		for child in current.get_children():
			pending.append(child)
	if first:
		return 0.0
	var worst := 0.0
	for corner in range(8):
		worst = max(worst, (box.get_endpoint(corner) - center).length())
	return worst
