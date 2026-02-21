extends SceneTree

func _init():
	print("Starting light verification...")

	var scenes = [
		"res://core_v2/props/scifi_lights/FluorescentLightCeiling.tscn",
		"res://core_v2/props/scifi_lights/FluorescentLightWall.tscn",
		"res://core_v2/props/scifi_lights/FluorescentLightFlickering.tscn"
	]

	for scene_path in scenes:
		print("Checking ", scene_path)
		var packed = load(scene_path)
		if not packed:
			print("ERROR: Failed to load ", scene_path)
			quit(1)
			return

		var instance = packed.instance()
		if not instance:
			print("ERROR: Failed to instance ", scene_path)
			quit(1)
			return

		if not instance.get_script().resource_path.ends_with("FluorescentLight.gd"):
			print("ERROR: Script is not FluorescentLight.gd on ", scene_path)
			print("Found: ", instance.get_script().resource_path)
			quit(1)
			return

		# Check properties
		if "Flickering" in scene_path:
			if not instance.flicker_enabled:
				print("ERROR: FluorescentLightFlickering should have flicker_enabled=true")
				quit(1)
				return
		else:
			if instance.flicker_enabled:
				print("ERROR: Standard lights should have flicker_enabled=false by default")
				quit(1)
				return

		print("Verified ", scene_path)
		instance.free()

	print("All lights verified successfully.")
	quit(0)
