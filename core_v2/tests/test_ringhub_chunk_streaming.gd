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
	# La garantia es que el pod del slot funcional no aporte colision: el jugador
	# despierta justo ahi dentro. Se comprueba el COMPORTAMIENTO, no como esta
	# representada la colision — el anillo dejo de hornearse a un compound (que
	# omitia el pod en el bake) y ahora son primitivas sueltas que el body suelta
	# en runtime, y la garantia tiene que valer igual en las dos.
	var before := _count_pod_shapes(body)
	assert_int(before).is_greater(0)
	var pod: int = int(body.free_slot(1))
	assert_int(pod).is_greater(-1)
	assert_int(_count_pod_shapes(body)).is_equal(before - 1)
	assert_object(_find_pod_shape(body, pod)).is_null()


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
			# Se mide PRIMERO en la escena fuente: el body que carga el chunk puede
			# venir compactado a un compound de box3d, y ahi medir engana en vez de
			# fallar — CompoundChunkBodyV2 crea su CollisionShape al entrar al arbol
			# y el debug mesh de esa shape es el AABB de TODO el compound, que para
			# una cuna angular envuelve muchisimo aire (daba 18-27 m donde la
			# geometria real llega a 6-23).
			var extent := _source_body_extent(current)
			if extent <= 0.0:
				extent = _chunk_extent(current)
			if extent <= 0.0:
				cortos.append("%s: no se pudo medir la geometria del chunk" % current.name)
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
	var extent := _measure_shapes(instance, chunk, chunk.get("trigger_center"))
	chunk.remove_child(instance)
	instance.queue_free()
	return extent


# Distancia del punto mas lejano de las CollisionShape de `instance` a `center`,
# en el espacio del chunk. Por shape, no por AABB del conjunto: el AABB de una
# cuna angular envuelve muchisimo aire y daria un alcance inflado.
func _measure_shapes(instance: Node, chunk: Node, center: Vector3) -> float:
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


# Alcance de la colision de un chunk medido en su escena FUENTE. El body que
# carga el chunk puede venir compactado a un compound de box3d, que no expone
# shapes; compound_body_src guarda la misma geometria como primitivas sueltas.
# Medir ahi es exacto: el AABB del visual del sector sobreestima muchisimo,
# porque una cuna angular delgada tiene una caja envolvente enorme.
const COMPOUND_SOURCE_DIR := "res://core_v2/levels/chunks/compound_body_src/"

func _source_body_extent(chunk: Node) -> float:
	var packed: PackedScene = chunk.get("chunk_scene")
	if packed == null:
		return 0.0
	var source_path := COMPOUND_SOURCE_DIR + String(packed.resource_path).get_file()
	if not ResourceLoader.exists(source_path):
		return 0.0
	var source: PackedScene = load(source_path) as PackedScene
	if source == null:
		return 0.0
	var instance: Node = source.instance()
	chunk.add_child(instance)
	var extent := _measure_shapes(instance, chunk, chunk.get("trigger_center"))
	chunk.remove_child(instance)
	instance.queue_free()
	return extent


# Cajas de pod (Pod_NN) vivas bajo un cuerpo de anillo de criopods.
func _count_pod_shapes(body: Node) -> int:
	var count := 0
	var pending := [body]
	while not pending.empty():
		var current = pending.pop_back()
		if current is CollisionShape and String(current.name).begins_with("Pod_"):
			count += 1
		for child in current.get_children():
			pending.append(child)
	return count


func _find_pod_shape(body: Node, pod: int):
	var wanted := "Pod_%02d" % pod
	var pending := [body]
	while not pending.empty():
		var current = pending.pop_back()
		if current is CollisionShape and String(current.name) == wanted:
			return current
		for child in current.get_children():
			pending.append(child)
	return null


# ---------------------------------------------------------------------------
# Regresion: un pod sin colision por anillo.
#
# El body de CADA anillo traia horneado el path fijo `../../Criopods_Visual`, el
# visual del anillo de DESPERTAR. Al cargar su chunk leia el bloqueo de ese anillo
# (slot 37) y liberaba la caja de ESE slot en todos los pisos: con el slot fijo 37,
# Criopods4 y Criopods5 perdian un pod; 3 y 6 zafaban solo porque en su layout ese
# slot no tenia pod. El body tiene que leer el visual de SU anillo: los de arriba
# tienen blocked_slot=-1 y no liberan nada.
# ---------------------------------------------------------------------------

const LEVEL_RINGS := [
	{"chunk": "Chunk_Criopods", "visual": "Criopods_Visual"},
	{"chunk": "Chunk_Criopods3", "visual": "Criopods_Visual_Criopods3"},
	{"chunk": "Chunk_Criopods4", "visual": "Criopods_Visual_Criopods4"},
	{"chunk": "Chunk_Criopods5", "visual": "Criopods_Visual_Criopods5"},
	{"chunk": "Chunk_Criopods6", "visual": "Criopods_Visual_Criopods6"},
]

func test_cada_anillo_libera_solo_su_propio_slot_bloqueado() -> void:
	var level = auto_free(RingHubScene.instance())
	add_child(level)
	yield(get_tree(), "idle_frame")
	_load_all_chunks(level)
	for _i in range(8):
		yield(get_tree(), "idle_frame")

	var stream: Node = level.get_node_or_null("ScaffoldStreamRoot")
	assert_object(stream).is_not_null()
	for entry in LEVEL_RINGS:
		var chunk: Node = stream.get_node_or_null(entry["chunk"])
		assert_object(chunk).is_not_null()
		var body: Node = chunk.get_node_or_null("CriopodRingCollision")
		assert_object(body).is_not_null()
		var visual: Node = stream.get_node_or_null(entry["visual"])
		assert_object(visual).is_not_null()
		# El provider del body es el visual del MISMO anillo: con el path del
		# despertar los pisos superiores leian un bloqueo ajeno.
		var provider = body.get_node_or_null(body.slot_provider_path)
		assert_object(provider).is_not_null()
		assert_bool(provider == visual).is_true()

		var slot_to_pod: Array = body.slot_to_pod
		var nonneg := 0
		for pod in slot_to_pod:
			if int(pod) >= 0:
				nonneg += 1
		var blocked := int(provider.get_blocked_slot()) if provider.has_method("get_blocked_slot") else -1
		var expected := nonneg
		if blocked >= 0 and blocked < slot_to_pod.size() and int(slot_to_pod[blocked]) >= 0:
			expected -= 1
		assert_int(_count_pod_shapes(body)).is_equal(expected)


func _load_all_chunks(root: Node) -> void:
	var pending := [root]
	while not pending.empty():
		var current = pending.pop_back()
		if current.get_script() != null and current.has_method("request_load"):
			current.request_load()
		for child in current.get_children():
			pending.append(child)


# ---------------------------------------------------------------------------
# Cada pod que el anillo DIBUJA tiene su caja en el mismo angulo, en los dos
# caminos de representacion (pods instanciados en normal, capas MultiMesh en LOW):
# la colision no depende de cual este activo.
# ---------------------------------------------------------------------------

const RING_SCENES := [
	{
		"ring": "Criopods1",
		"visual_node": "Criopods_Visual",
		"visual_scene": "res://core_v2/levels/chunks/ringhub/RingHub_Criopods_visual.tscn",
		"body_scene": "res://core_v2/levels/chunks/ringhub/RingHub_Criopods_body.tscn",
	},
	{
		"ring": "Criopods3",
		"visual_node": "Criopods_Visual_Criopods3",
		"visual_scene": "res://core_v2/levels/chunks/ringhub/RingHub_Criopods3_visual.tscn",
		"body_scene": "res://core_v2/levels/chunks/ringhub/RingHub_Criopods3_body.tscn",
	},
	{
		"ring": "Criopods4",
		"visual_node": "Criopods_Visual_Criopods4",
		"visual_scene": "res://core_v2/levels/chunks/ringhub/RingHub_Criopods4_visual.tscn",
		"body_scene": "res://core_v2/levels/chunks/ringhub/RingHub_Criopods4_body.tscn",
	},
	{
		"ring": "Criopods5",
		"visual_node": "Criopods_Visual_Criopods5",
		"visual_scene": "res://core_v2/levels/chunks/ringhub/RingHub_Criopods5_visual.tscn",
		"body_scene": "res://core_v2/levels/chunks/ringhub/RingHub_Criopods5_body.tscn",
	},
	{
		"ring": "Criopods6",
		"visual_node": "Criopods_Visual_Criopods6",
		"visual_scene": "res://core_v2/levels/chunks/ringhub/RingHub_Criopods6_visual.tscn",
		"body_scene": "res://core_v2/levels/chunks/ringhub/RingHub_Criopods6_body.tscn",
	},
]

func test_colision_de_cada_anillo_cubre_los_pods_visibles_mismos_angulos() -> void:
	# ODISEA_CRIOPOD_RING_INSTANCED: "1" fuerza pods instanciados (tier normal),
	# "0" fuerza las capas MultiMesh (tier LOW). La caja de colision es la misma.
	var previous := OS.get_environment("ODISEA_CRIOPOD_RING_INSTANCED")
	for entry in RING_SCENES:
		for mode in ["1", "0"]:
			OS.set_environment("ODISEA_CRIOPOD_RING_INSTANCED", mode)
			var root := _spawn_ring_pair(entry)
			add_child(root)
			auto_free(root)
			yield(get_tree(), "idle_frame")
			_assert_ring_coverage(entry, root)
	OS.set_environment("ODISEA_CRIOPOD_RING_INSTANCED", previous)


# Replica el cableado de RingHub_Level alrededor del body: `ScaffoldStreamRoot` con
# el visual hermano (nombre real del nivel) y el body a dos niveles, asi el
# `slot_provider_path` horneado resuelve igual que en el nivel.
func _spawn_ring_pair(entry: Dictionary) -> Node:
	var root := Spatial.new()
	root.name = "ScaffoldStreamRoot"
	var visual: Node = (load(entry["visual_scene"]) as PackedScene).instance()
	visual.name = entry["visual_node"]
	root.add_child(visual)
	var chunk := Spatial.new()
	chunk.name = "Chunk_%s" % entry["ring"]
	root.add_child(chunk)
	var body: Node = (load(entry["body_scene"]) as PackedScene).instance()
	chunk.add_child(body)
	return root


func _assert_ring_coverage(entry: Dictionary, root: Node) -> void:
	var visual: Node = root.get_node_or_null(entry["visual_node"])
	assert_object(visual).is_not_null()
	var chunk: Node = root.get_node_or_null("Chunk_%s" % entry["ring"])
	assert_object(chunk).is_not_null()
	var body: Node = chunk.get_node_or_null("CriopodRingCollision")
	assert_object(body).is_not_null()
	var provider = body.get_node_or_null(body.slot_provider_path)
	assert_object(provider).is_not_null()
	assert_bool(provider == visual).is_true()

	# El body mapea slot -> instancia igual que el visual: la caja del slot S cae
	# donde el pod del slot S. Un corrimiento de slot delataria el bug.
	var slot_to_pod: Array = body.slot_to_pod
	var slot_to_instance: Array = visual.slot_to_instance
	assert_int(slot_to_pod.size()).is_equal(slot_to_instance.size())
	var limit: int = min(slot_to_pod.size(), slot_to_instance.size())
	for k in range(limit):
		assert_int(int(slot_to_pod[k])).is_equal(int(slot_to_instance[k]))

	# Cada pod que el visual dibuja tiene su caja en el MISMO angulo (tolerancia
	# 0.5 grados). Las posiciones de las instancias se leen del .tscn: en el binario
	# headless de CI (platform=server) el buffer del MultiMesh no expone transforms.
	var origins := _visual_instance_origins(entry)
	var pod_shapes := 0
	var seen_angles := []
	for slot in range(slot_to_pod.size()):
		var pod := int(slot_to_pod[slot])
		if pod < 0:
			continue
		var shape = body.get_node_or_null("%s/Pod_%02d" % [String(body.body_path), pod])
		assert_object(shape).is_not_null()
		if shape == null:
			continue
		pod_shapes += 1
		var shape_origin := Vector2(shape.transform.origin.x, shape.transform.origin.z)
		assert_bool(origins.has(pod)).is_true()
		if not origins.has(pod):
			continue
		var vis_origin: Vector2 = origins[pod]
		var diff := _angle_diff_deg(
			rad2deg(atan2(shape_origin.y, shape_origin.x)),
			rad2deg(atan2(vis_origin.y, vis_origin.x)))
		assert_float(diff).is_less(0.5)
		for other in seen_angles:
			assert_float(_angle_diff_deg(rad2deg(atan2(shape_origin.y, shape_origin.x)), other)).is_greater(0.5)
		seen_angles.append(rad2deg(atan2(shape_origin.y, shape_origin.x)))
	assert_int(pod_shapes).is_equal(_count_pod_shapes(body))


# Origen local (x,z) de cada instancia de la capa Shell del visual, leido de la
# `transform_array` del .tscn (12 floats por instancia en TRANSFORM_3D). Devuelve
# indice de instancia -> Vector2. Vacio si no encuentra la capa.
func _visual_instance_origins(entry: Dictionary) -> Dictionary:
	var f := File.new()
	if f.open(ProjectSettings.globalize_path(entry["visual_scene"]), File.READ) != OK:
		return {}
	var txt: String = f.get_as_text()
	f.close()
	var shell_at := txt.find('name="Shell"')
	if shell_at == -1:
		return {}
	var ref_at := txt.find("multimesh = SubResource(", shell_at)
	if ref_at == -1:
		return {}
	var id_start := ref_at + String("multimesh = SubResource(").length()
	var mm_id := txt.substr(id_start, txt.find(")", id_start) - id_start).strip_edges()
	var block_at := txt.find('[sub_resource type="MultiMesh" id=%s]' % mm_id)
	if block_at == -1:
		return {}
	var arr_at := txt.find("transform_array = PoolVector3Array(", block_at)
	if arr_at == -1:
		return {}
	var arr_start := arr_at + String("transform_array = PoolVector3Array(").length()
	var arr_end := txt.find(")", arr_start)
	var values := []
	for token in txt.substr(arr_start, arr_end - arr_start).split(","):
		var t: String = String(token).strip_edges()
		if t != "":
			values.append(float(t))
	var out := {}
	var i := 0
	while i + 11 < values.size():
		out[i / 12] = Vector2(values[i + 9], values[i + 11])
		i += 12
	return out


func _angle_diff_deg(a: float, b: float) -> float:
	var d: float = abs(fmod(a - b, 360.0))
	return d if d <= 180.0 else 360.0 - d

