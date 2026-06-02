extends SceneTree

func _init():
	var mst_gen = load("res://core_v2/systems/ScaffoldMSTGenerator.gd").new()
	mst_gen.apply_params({"grid_width": 8, "grid_depth": 12, "cell_size": 6.0})
	
	var start_time = OS.get_ticks_usec()
	var grid = mst_gen.generate_grid_data(1234)
	var end_time = OS.get_ticks_usec()
	
	var duration_ms = (end_time - start_time) / 1000.0
	print("Generation took: ", duration_ms, "ms")
	
	if duration_ms > 5.0:
		print("FAILED: Performance target exceeded (>5ms)")
		quit(1)
	
	if grid.size() != 8 * 12:
		print("FAILED: Grid size mismatch")
		quit(1)
	
	var occupied = 0
	for cell in grid:
		if cell != null:
			occupied += 1
			# Access dict format: cell["variant"]["id"]
			var v = cell["variant"]
			var vid = v["id"]
			if vid == "EMPTY": continue
			var conn = v["connections"]
			var c_count = 0
			for c in conn: if c: c_count += 1
			if c_count == 0:
				print("FAILED: Occupied cell has no connections")
				quit(1)
	
	print("Occupied cells: ", occupied)
	if occupied < 10:
		print("FAILED: Too few occupied cells")
		quit(1)

	print("SUCCESS: MST Generator verified")
	quit(0)
