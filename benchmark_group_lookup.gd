extends SceneTree

func _init():
	print("Starting benchmark...")

	# Create a dummy root
	var root = Node.new()
	get_root().add_child(root)

	# Instantiate many nodes that are NOT in the group initially
	# (Simulating normal nodes)
	for i in range(100):
		var n = Node.new()
		root.add_child(n)

	var node_count = 2000
	print("Creating ", node_count, " nodes in 'replay_sync' group...")
	for i in range(node_count):
		var n = Node.new()
		n.add_to_group("replay_sync")
		root.add_child(n)

	var iterations = 5000

	# --- BASELINE ---
	print("\nRunning BASELINE (Native get_nodes_in_group) loop...")
	var time_start = OS.get_ticks_usec()

	var found_count = 0
	for i in range(iterations):
		var nodes = get_nodes_in_group("replay_sync")
		found_count = nodes.size()
		if nodes.size() > 0:
			var _x = nodes[0]

	var time_end = OS.get_ticks_usec()
	var duration_baseline = (time_end - time_start) / 1000.0
	print("Time taken for ", iterations, " lookups: ", duration_baseline, " ms")
	print("Average per lookup: ", duration_baseline / iterations, " ms")

	# --- OPTIMIZED ---
	print("\nRunning OPTIMIZED (Cached) loop...")

	# Simulate the cache mechanism
	var cache = get_nodes_in_group("replay_sync")
	var cache_dirty = false

	time_start = OS.get_ticks_usec()

	for i in range(iterations):
		var nodes
		if cache_dirty:
			cache = get_nodes_in_group("replay_sync")
			cache_dirty = false
		nodes = cache

		found_count = nodes.size()
		if nodes.size() > 0:
			var _x = nodes[0]

	time_end = OS.get_ticks_usec()
	var duration_opt = (time_end - time_start) / 1000.0
	print("Time taken for ", iterations, " lookups: ", duration_opt, " ms")
	print("Average per lookup: ", duration_opt / iterations, " ms")

	print("\nSPEEDUP: ", duration_baseline / duration_opt, "x")

	quit()
