extends SceneTree

# generate_test_hotzone.gd
# Generates a dummy .bin file to test HotzonePlayer.

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

	for i in range(120):
		snapshot["frames"].append({
			"input": {"move_vec": [0, -1] if i < 60 else [0, 0], "jump": i == 30},
			"dt": 0.016,
			"pos": [0, 1, 0],
			"fps": 60.0,
			"t": i * 16
		})

	var data_blob = var2bytes(snapshot)
	var path = "user://test_hotzone.bin"
	var f = File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_32(BINARY_MAGIC)
		f.store_buffer(data_blob)
		f.close()
		print("Test hotzone generated at: ", path)
		print("Run with: godot3-bin --scene core_v2/tools/HotzonePlayer.tscn --replay-file ", OS.get_user_data_dir() + "/test_hotzone.bin")
	else:
		printerr("Failed to generate test hotzone.")

	quit()
