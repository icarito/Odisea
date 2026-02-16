# Benchmark Limitations and Theoretical Analysis

## Limitation
The local development environment lacks the necessary Godot binaries (`godot` or `godot3-headless`) to execute GDScript benchmarks. As a result, empirical performance measurements (e.g., "before vs. after" execution times) could not be gathered.

## Theoretical Improvement
The optimization addresses the repeated recursive node resolution in `OYS_Interpreter._resolve_node`.

### Before Optimization
The function `_resolve_node` performed the following steps on every call:
1.  `host_node.get_node_or_null(path)` (Relative lookup)
2.  If not found: `host_node.get_tree().current_scene.find_node(path, true, false)` (Recursive search in current scene)
3.  If not found: `host_node.get_tree().root.find_node(path, true, false)` (Recursive search from root)

The `find_node` function with `recursive=true` performs a depth-first search of the scene tree. In a scene with `N` nodes, the worst-case time complexity is **O(N)**.
When `_resolve_node` is called repeatedly (e.g., in a `WHILE` loop checking a property of a prop every frame), this results in **O(K * N)** complexity per frame, where `K` is the number of calls.

### After Optimization
A `_node_cache` dictionary was introduced.
1.  Check `_node_cache[path]`. Complexity: **O(1)** (plus hash overhead).
2.  If found and valid, return immediately.
3.  If not found, perform the original resolution (O(N)) and cache the result.

For repeated calls with the same path, the amortized time complexity drops to **O(1)**. This significantly reduces CPU usage for scripts with loops involving node lookups.

## Proposed Benchmark Script
To verify the improvement in an environment with Godot installed, the following script can be used:

```gdscript
# tests/benchmark_oys_resolve.gd
extends SceneTree

const OYS_Interpreter = preload("res://core_v2/systems/OYS_Interpreter.gd")

func _init():
	print("Starting Benchmark...")

	# Setup a dummy scene tree
	var root = Node.new()
	root.name = "Root"
	get_root().add_child(root)

	var scene = Node.new()
	scene.name = "Scene"
	root.add_child(scene)
	current_scene = scene

	# Create a deep hierarchy
	var parent = scene
	var target_node = null
	for i in range(1000):
		var n = Node.new()
		n.name = "Node_%d" % i
		parent.add_child(n)
		parent = n
		if i == 500:
			target_node = n
			n.name = "TargetProp" # Unique name for find_node

	# Setup Interpreter
	var interp = OYS_Interpreter.new(root)

	# Warmup
	interp._resolve_node("TargetProp")

	# Measure
	var start_time = OS.get_ticks_usec()
	var iterations = 10000

	for i in range(iterations):
		var node = interp._resolve_node("TargetProp")
		if node != target_node:
			printerr("Resolution failed!")
			quit()
			return

	var end_time = OS.get_ticks_usec()
	var duration_ms = (end_time - start_time) / 1000.0

	print("Benchmark Finished.")
	print("Iterations: ", iterations)
	print("Total Time: %.3f ms" % duration_ms)
	print("Avg Time per call: %.3f ms" % (duration_ms / iterations))

	quit()
```

### Verification Logic
1.  **Correctness**: The cache checks `is_instance_valid()` and `is_inside_tree()`, ensuring that freed or removed nodes are not returned.
2.  **Invalidation**: If a cached node becomes invalid, it is removed from the cache, and a fresh resolution is attempted.
