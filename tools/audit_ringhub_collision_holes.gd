extends SceneTree

# Busca agujeros de colision en RingHub: geometria que se DIBUJA como piso y por
# la que sin embargo se cae. Es el sintoma que se reporta jugando ("atravieso
# varias cosas") y que ningun test estructural ve, porque el chunk existe, carga
# y tiene shapes: lo que falta es colision debajo de unos triangulos concretos.
#
# Como funciona: fuerza la carga de TODOS los chunks (nada de streaming, para no
# confundir "lejos" con "roto"), toma los vertices de cada Visual_NN del scaffold
# cuya normal apunta hacia arriba —las superficies caminables— y tira un rayo
# corto hacia abajo en cada uno.
#
# Tres resultados por punto:
#   ok        colision a <= 0.4 m: se pisa donde se ve.
#   bajo      colision entre 0.4 y 2.5 m. NO es un agujero: en una escalera el
#             visual son peldanos y la colision suele ser una rampa por debajo.
#   AGUJERO   nada en 2.5 m. Aca se cae.
#
# La mascara es 65 (capa 1 del suelo/domo + capa 64 del scaffold). Con solo 64
# los puntos que se apoyan en el piso del domo salen como falsos agujeros.
#
# Lo que se sabe de los 13 que quedan (sondeando la escena FUENTE,
# DomeIntro_ScaffoldSource, que tiene sus 118 CollisionShape vivas):
#   - (-19.73, 4.7, -17.77) y (2.73, 9.2, -25.96) SI colisionan en la fuente:
#     esos los perdio el horneado por sector y se arreglan en el baker.
#   - (13.94, 9.2, -21.47) y (-4.70, 22.69, 17.39) NO colisionan ni en la fuente:
#     esa geometria nunca tuvo piso, y es autoria del nivel, no del baker.
# Ojo al mapear un punto global a su sector: _sector_for trabaja en el espacio del
# GRUPO, y Group_SpiralStairs va rotado ~165 grados.
#
# Run: tools/godot --no-window --audio-driver Dummy --path . \
#        -s res://tools/audit_ringhub_collision_holes.gd
# Escribe el detalle en user://ringhub_collision_holes.txt y un resumen por stdout.

const LEVEL := "res://core_v2/levels/RingHub_Level.tscn"
const REPORT := "user://ringhub_collision_holes.txt"
const MASK := 65
const NEAR_DROP := 0.4
const MAX_DROP := 2.5
# Un vertice por cada ~1/400 de la malla alcanza para encontrar tramos enteros sin
# colision; subirlo solo hace el barrido mas lento.
const SAMPLES_PER_SURFACE := 400
const WALKABLE_NORMAL_Y := 0.85

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root: Node = (load(LEVEL) as PackedScene).instance()
	get_root().add_child(root)
	for _i in range(30):
		yield(self, "idle_frame")

	var forced := _force_all_chunks(root)
	for _i in range(30):
		yield(self, "idle_frame")

	var space: PhysicsDirectSpaceState = root.get_viewport().world.direct_space_state
	var report := File.new()
	report.open(REPORT, File.WRITE)
	report.store_line("chunks forzados: %d" % forced)

	var stream: Node = root.get_node_or_null("ScaffoldStreamRoot")
	if stream == null:
		printerr("[holes] RingHub_Level sin ScaffoldStreamRoot")
		quit(1)
		return

	var total := 0
	var holes := 0
	for group in stream.get_children():
		if not String(group.name).begins_with("Group_"):
			continue
		for child in group.get_children():
			if not (child is MeshInstance) or not String(child.name).begins_with("Visual_"):
				continue
			var counts: Array = _probe_visual(child as MeshInstance, space, report,
				String(group.name) + "/" + String(child.name))
			total += counts[0]
			holes += counts[1]

	var summary := "[holes] %d puntos caminables, %d sin colision (%.2f%%)" % [
		total, holes, 100.0 * float(holes) / float(max(total, 1))]
	report.store_line(summary)
	report.close()
	print(summary)
	print("[holes] detalle en %s" % REPORT)
	quit(0)

func _force_all_chunks(root: Node) -> int:
	var forced := 0
	var pending := [root]
	while not pending.empty():
		var current = pending.pop_back()
		if current.get_script() != null and current.has_method("request_load"):
			var scene: PackedScene = current.get("chunk_scene")
			if scene != null:
				current.add_child(scene.instance())
				forced += 1
		for child in current.get_children():
			pending.append(child)
	return forced

# Devuelve [puntos caminables, agujeros].
func _probe_visual(mesh_instance: MeshInstance, space: PhysicsDirectSpaceState,
		report: File, label: String) -> Array:
	if mesh_instance.mesh == null:
		return [0, 0]
	var total := 0
	var near := 0
	var below := 0
	var holes := 0
	for surface in range(mesh_instance.mesh.get_surface_count()):
		var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface)
		var vertices: PoolVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		if normals == null:
			continue
		var step: int = max(1, vertices.size() / SAMPLES_PER_SURFACE)
		for i in range(0, vertices.size(), step):
			if (normals[i] as Vector3).y < WALKABLE_NORMAL_Y:
				continue
			var world: Vector3 = mesh_instance.global_transform.xform(vertices[i])
			total += 1
			var hit: Dictionary = space.intersect_ray(
				world + Vector3.UP * 0.3, world + Vector3.DOWN * MAX_DROP, [], MASK)
			if not hit.has("position"):
				holes += 1
				report.store_line("AGUJERO %-34s %s" % [label, str(world)])
			elif world.y - (hit["position"] as Vector3).y <= NEAR_DROP:
				near += 1
			else:
				below += 1
	if total > 0:
		report.store_line("%-34s n=%3d ok=%3d bajo=%3d AGUJERO=%3d" % [label, total, near, below, holes])
	return [total, holes]
