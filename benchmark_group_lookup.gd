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

	# Instantiate nodes that ARE in the group
	# Since we can't easily rely on class scripts without loading them,
	# we will simulate the behavior:
	# A node that calls add_to_group in _ready vs _init is what we are changing.
	# But for the benchmark of the LOOKUP, we just need nodes in the group.

	var node_count = 2000
	print("Creating ", node_count, " nodes in 'replay_sync' group...")
	for i in range(node_count):
		var n = Node.new()
		n.add_to_group("replay_sync")
		root.add_child(n)

	print("Running lookup loop...")
	var iterations = 5000
	var time_start = OS.get_ticks_usec()

	var found_count = 0
	for i in range(iterations):
		var nodes = get_nodes_in_group("replay_sync")
		found_count = nodes.size()
		# Simulate access
		if nodes.size() > 0:
			var _x = nodes[0]

	var time_end = OS.get_ticks_usec()
	var duration_ms = (time_end - time_start) / 1000.0
	print("Time taken for ", iterations, " lookups: ", duration_ms, " ms")
	print("Average per lookup: ", duration_ms / iterations, " ms")

	quit()
