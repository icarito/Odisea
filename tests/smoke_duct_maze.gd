extends SceneTree

func _init():
	print("--- Smoke Test: DuctMazeStreamer (v3 Procedural) ---")
	var DuctMazeStreamerScript = load("res://core_v2/systems/DuctMazeSpawner.gd")
	var spawner = DuctMazeStreamerScript.new()

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

	# Verification of tile types
	var radial_count = 0
	var arc_count = 0
	var capsule_count = 0
	var junction_count = 0
	
	for child in spawner.get_children():
		if "DuctRadial" in child.name:
			radial_count += 1
		elif "DuctArc" in child.name:
			arc_count += 1
		elif "CapsuleRoom" in child.name:
			capsule_count += 1
		elif "Junction" in child.name:
			junction_count += 1

	print("DuctRadial count: ", radial_count)
	print("DuctArc count: ", arc_count)
	print("CapsuleRoom count: ", capsule_count)
	print("Junction count: ", junction_count)

	quit(0)
