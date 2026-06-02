extends GdUnitTestSuite

func test_mst_generation():
	var mst_gen = load("res://core_v2/systems/ScaffoldMSTGenerator.gd").new()
	mst_gen.apply_params({"grid_width": 8, "grid_depth": 12, "cell_size": 6.0})

	var start_time = OS.get_ticks_usec()
	var grid = mst_gen.generate_grid_data(1234)
	var end_time = OS.get_ticks_usec()

	var duration_ms = (end_time - start_time) / 1000.0
	print("MST Generation took: ", duration_ms, "ms")

	assert_bool(duration_ms < 20.0).is_true()
	assert_int(grid.size()).is_equal(8 * 12)

	var occupied = 0
	for cell in grid:
		if cell != null:
			occupied += 1
			# MST Generator serializes to dicts — use bracket notation (Godot 3)
			var v = cell["variant"]
			var vid = v["id"]
			if vid == "EMPTY":
				continue
			var conn = v["connections"]
			var c_count = 0
			for c in conn:
				if c: c_count += 1
			assert_int(c_count).is_greater(0)
	
	assert_int(occupied).is_greater(10)