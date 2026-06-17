extends SceneTree

# generate_test_hotzone_varied.gd
# Generates a .bin with a VARYING FPS curve (crosses 30/45/60 thresholds) so the
# HotzonePlayer FPS chart, gridlines, and cursor label can be verified visually.

const BINARY_MAGIC := 0x485a4e32

func _init():
	var snapshot = {
		"trigger": "manual",
		"player_id": "test_player",
		"session_id": "test_session",
		"timestamp": OS.get_unix_time(),
		"scene": "TestScene_v2",
		"grid": [0, 0],
		"frames": []
	}

	var n = 180
	for i in range(n):
		# Sweep FPS in a sine from ~20 to ~60 so the curve hits red/yellow/green.
		var phase = float(i) / float(n) * TAU * 2.0
		var fps = 40.0 + 20.0 * sin(phase)  # ranges 20..60
		snapshot["frames"].append({
			"input": {"move_vec": [0, -1] if i < n / 2 else [0, 0], "jump": i == 30},
			"dt": 0.016,
			"pos": [0, 1, 0],
			"fps": fps,
			"t": i * 16
		})

	var data_blob = var2bytes(snapshot)
	var path = "user://test_hotzone_varied.bin"
	var f = File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_32(BINARY_MAGIC)
		f.store_buffer(data_blob)
		f.close()
		print("Varied test hotzone generated at: ", path)
		print("Full path: ", OS.get_user_data_dir() + "/test_hotzone_varied.bin")
	else:
		printerr("Failed to generate test hotzone.")

	quit()
