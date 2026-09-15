extends SceneTree

# inspect_glb_dome.gd — imprime la estructura de nodos del GLB importado.
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://assets/models/dome_terrace_v2/DomeTerraceV2.glb")
	var root: Node = scene.instance()
	_walk(root, 0)
	quit(0)

func _walk(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	if node is MeshInstance and (node as MeshInstance).mesh != null:
		var mi := node as MeshInstance
		var mats := []
		for s in range(mi.mesh.get_surface_count()):
			var m := mi.mesh.surface_get_material(s)
			if m == null:
				m = mi.get_surface_material(s)
			mats.append(m.resource_name if m != null else "NULL")
		print("%s[mi] %s xf.origin=%s xf.basis.scale~%s mesh=%s surfs=%d mats=%s verts0=%s" % [
			pad, node.name, mi.transform.origin,
			mi.transform.basis.get_scale(), mi.mesh.resource_name,
			mi.mesh.get_surface_count(), mats,
			mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() if mi.mesh.get_surface_count() > 0 else -1])
	else:
		var extra := ""
		if node is Spatial:
			extra = " origin=%s" % (node as Spatial).transform.origin
		print("%s[node] %s (%s)%s" % [pad, node.name, node.get_class(), extra])
	for child in node.get_children():
		_walk(child, depth + 1)
