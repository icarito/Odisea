static func get_scene_aabb(node, aabb = AABB(), parent_transform = Transform(), aabb_valid = false):
	if node is Spatial:
		if not node.visible:
			return {"aabb": aabb, "valid": aabb_valid}
		
		# Accumulate transform
		parent_transform = parent_transform * node.transform
		
		var node_aabb = null
		
		if node is VisualInstance:
			node_aabb = parent_transform.xform(node.get_aabb())
			# print("Found VisualInstance AABB for ", node.name, ": ", node_aabb)
		elif node is CollisionShape and node.shape != null:
			var mesh = node.shape.get_debug_mesh()
			if mesh != null:
				node_aabb = parent_transform.xform(mesh.get_aabb())
				# print("Found CollisionShape AABB for ", node.name, ": ", node_aabb)
		
		if node_aabb != null:
			if not aabb_valid:
				aabb = node_aabb
				aabb_valid = true
			else:
				aabb = aabb.merge(node_aabb)

	for i in node.get_child_count():
		var result = get_scene_aabb(node.get_child(i), aabb, parent_transform, aabb_valid)
		aabb = result.aabb
		aabb_valid = result.valid
	
	# If this is the top recursive call, we should return the AABB only to keep API simple if possible,
	# but we needed to change the signature to support valid flag.
	# To preserve compat with callers expecting just AABB, we might have an issue.
	# But callers are only our plugin.gd.
	# Helper wrapper? No, let's just return the dict or change compat.
	# Actually, to avoid changing signature too much for recursive calls:
	return {"aabb": aabb, "valid": aabb_valid}


static func get_instance_root(node):
	# TODO Could use `owner`?
	while node != null and node.filename == "":
		node = node.get_parent()
	return node


static func get_node_in_parents(node, klass):
	while node != null:
		node = node.get_parent()
		if node != null and node is klass:
			return node
	return null


static func is_self_or_parent_scene(fpath, node):
	while node != null:
		if node.filename == fpath:
			return true
		node = node.get_parent()
	return false
