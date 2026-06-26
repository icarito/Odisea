extends SceneTree

func _init():
	print("--- STARTING DUCT ASSET SMOKE TEST ---")

	var assets = [
		"res://core_v2/props/duct/DuctCross.tscn",
		"res://core_v2/props/duct/DuctTee.tscn",
		"res://core_v2/props/duct/CapsuleRoom.tscn",
		"res://core_v2/props/duct/DuctGateValve.tscn"
	]

	var success = true
	for path in assets:
		print("Testing: ", path)
		var scene = load(path)
		if not scene:
			print("  [ERROR] Failed to load scene: ", path)
			success = false
			continue

		var instance = scene.instance()
		if not instance:
			print("  [ERROR] Failed to instance scene: ", path)
			success = false
			continue

		print("  [OK] Loaded and instanced: ", path)

		if instance.has_method("setup"):
			print("  [INFO] Found setup() on ", instance.name)

		instance.free()

	if success:
		print("--- SMOKE TEST COMPLETED SUCCESSFULLY ---")
		quit(0)
	else:
		print("--- SMOKE TEST FAILED ---")
		quit(1)
