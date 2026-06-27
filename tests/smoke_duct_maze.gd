extends SceneTree

func _init():
	print("--- Smoke Test: DuctMazeStreamer ---")
	var DuctMazeStreamerScript = load("res://core_v2/systems/DuctMazeSpawner.gd")
	var spawner = DuctMazeStreamerScript.new()

	# Mock duct_tiles with dummy Spatial scenes so they can be instanced
	var dummy_scene = PackedScene.new()
	var spatial = Spatial.new()
	dummy_scene.pack(spatial)

	spawner.duct_tiles = {
		"E": dummy_scene,
		"W": dummy_scene,
		"C": dummy_scene,
		"T": dummy_scene,
		"X": dummy_scene,
		"S": dummy_scene
	}
	spawner.capsule_scene = dummy_scene

	print("Generating maze...")
	spawner.generate()
	print("Maze generated successfully!")

	var children_count = spawner.get_child_count()
	print("Spawner children count: ", children_count)

	if children_count > 0:
		print("SUCCESS: Spawner produced children.")
	else:
		print("FAILURE: Spawner produced no children.")
		quit(1)
		return

	# Check for DuctArc (MeshInstance)
	var arc_count = 0
	for child in spawner.get_children():
		if child is MeshInstance:
			arc_count += 1

	print("DuctArc (MeshInstance) count: ", arc_count)

	quit(0)
