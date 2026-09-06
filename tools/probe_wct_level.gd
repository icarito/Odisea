extends SceneTree

func _init() -> void:
	var level: Node = load("res://core_v2/levels/interiors/Dome_Prologue.tscn").instance()
	root.add_child(level)
	var walker := level.find_node("walking_cargo_transporter_rig", true, false)
	if walker == null:
		printerr("walker no encontrado en el nivel")
		quit(1)
		return
	print("walker global:", walker.global_transform)
	var stack := [walker]
	while not stack.empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance:
			var mi := n as MeshInstance
			var aabb := mi.get_aabb()
			var gt := mi.global_transform
			print("%-40s visible=%s mesh=%s aabb_pos=%s aabb_size=%s gpos=%s" % [
				n.get_path_to(walker) if false else n.name,
				str(mi.visible) + "/" + str(mi.is_visible_in_tree()),
				"ok" if mi.mesh != null else "NULL",
				str(aabb.position.snapped(Vector3(0.1, 0.1, 0.1))),
				str(aabb.size.snapped(Vector3(0.1, 0.1, 0.1))),
				str(gt.origin.snapped(Vector3(0.01, 0.01, 0.01)))])
		for c in n.get_children():
			stack.push_back(c)
	quit(0)
