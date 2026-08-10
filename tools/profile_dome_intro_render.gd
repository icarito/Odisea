extends SceneTree

# profile_dome_intro_render.gd — Inventario de coste de dibujo de Dome_Intro por
# subarbol de primer nivel.
#
# El cuello de botella de esta escena en Android son los DRAW CALLS, no los
# vertices. Una draw call por superficie visible, asi que lo que se cuenta aca es
# superficies (no vertices) y cuantos materiales distintos hay: dos superficies
# con el mismo material se pueden batchear, dos con material distinto no.
#
# Se cuenta de forma analitica y no con VisualServer.get_render_info() porque los
# contadores son por-frame y globales a todos los viewports, asi que en headless
# salen inestables (deltas negativos al ocultar un nodo).
#
# Run: godot3-bin --no-window -s tools/profile_dome_intro_render.gd

const SCENE_PATH := "res://core_v2/levels/interiors/Dome_Intro.tscn"

var _materials := {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene_path: String = OS.get_environment("ODISEA_PROFILE_SCENE")
	if scene_path.empty():
		scene_path = SCENE_PATH
	var packed: PackedScene = load(scene_path)
	var root: Node = packed.instance()
	get_root().add_child(root)
	# RadialScatter/SteelGratePlatform construyen diferido; PropDitherManager
	# convierte materiales en un call_deferred posterior.
	for _i in range(120):
		yield(self, "idle_frame")

	var rows := []
	var totals := [0, 0, 0, 0]
	for child in root.get_children():
		var stats := _stats(child)
		if stats[0] == 0 and stats[3] == 0:
			continue
		rows.append([child.name, stats[0], stats[1], stats[2], stats[3]])
		for i in range(4):
			totals[i] += stats[i]
	rows.sort_custom(self, "_by_surfaces")

	print("PROF: escena=%s" % scene_path)
	print("PROF: %-30s %8s %8s %10s %8s" % ["SUBARBOL", "meshes", "surfs", "verts", "mats"])
	for r in rows:
		print("PROF: %-30s %8d %8d %10d %8d" % r)
	print("PROF: %-30s %8d %8d %10d %8d" % ["TOTAL", totals[0], totals[1], totals[2], totals[3]])
	print("PROF: materiales distintos en la escena = %d" % _materials.size())
	quit(0)

func _by_surfaces(a, b) -> bool:
	return a[2] > b[2]

# [meshes, superficies, vertices, materiales distintos del subarbol]
func _stats(node: Node) -> Array:
	var acc := [0, 0, 0, 0]
	var local_materials := {}
	_walk(node, acc, local_materials)
	acc[3] = local_materials.size()
	return acc

func _walk(node: Node, acc: Array, local_materials: Dictionary) -> void:
	if node is MeshInstance:
		var mi := node as MeshInstance
		if mi.mesh != null and mi.visible:
			acc[0] += 1
			acc[1] += mi.mesh.get_surface_count()
			for s in range(mi.mesh.get_surface_count()):
				acc[2] += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PoolVector3Array).size()
				var mat: Material = mi.material_override
				if mat == null:
					mat = mi.get_surface_material(s)
				if mat == null:
					mat = mi.mesh.surface_get_material(s)
				if mat != null:
					local_materials[mat.get_instance_id()] = true
					_materials[mat.get_instance_id()] = true
	elif node is MultiMeshInstance:
		var mm := node as MultiMeshInstance
		if mm.multimesh != null and mm.visible:
			acc[0] += 1
			acc[1] += 1
	for child in node.get_children():
		_walk(child, acc, local_materials)
