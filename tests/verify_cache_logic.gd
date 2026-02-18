extends SceneTree

const OYS_Interpreter = preload("res://core_v2/systems/OYS_Interpreter.gd")

func _init():
	print("Starting Cache Verification...")

	# 1. Setup Environment
	var root = Node.new()
	root.name = "Root"
	get_root().add_child(root)

	var scene = Node.new()
	scene.name = "Scene"
	root.add_child(scene)
	current_scene = scene

	var target = Node.new()
	target.name = "TargetProp"
	scene.add_child(target)

	var interp = OYS_Interpreter.new(root)

	# 2. Test Initial Resolution (Cache Miss)
	print("Test 1: Initial Resolution")
	var node1 = interp._resolve_node("TargetProp")
	assert(node1 == target, "Initial resolution failed")

	# 3. Test Cached Resolution (Cache Hit)
	print("Test 2: Cached Resolution")
	var node2 = interp._resolve_node("TargetProp")
	assert(node2 == target, "Cached resolution failed")
	assert(interp._node_cache.has("TargetProp"), "Cache entry missing")
	assert(interp._node_cache["TargetProp"] == target, "Cache entry mismatch")

	# 4. Test Invalidation (Node Freed)
	print("Test 3: Cache Invalidation (Free)")
	target.free()
	# Note: is_instance_valid(target) is now false

	# Create a new target with same name
	var new_target = Node.new()
	new_target.name = "TargetProp"
	scene.add_child(new_target)

	var node3 = interp._resolve_node("TargetProp")
	assert(node3 == new_target, "Re-resolution after free failed")
	assert(interp._node_cache["TargetProp"] == new_target, "Cache update failed")

	# 5. Test Invalidation (Node Removed from Tree)
	print("Test 4: Cache Invalidation (Remove Child)")
	scene.remove_child(new_target)
	# new_target is valid but not in tree

	# Create another target
	var third_target = Node.new()
	third_target.name = "TargetProp"
	scene.add_child(third_target)

	var node4 = interp._resolve_node("TargetProp")
	# Should find third_target because new_target is not in tree
	assert(node4 == third_target, "Re-resolution after remove failed")

	print("Verification Passed!")
	quit()
