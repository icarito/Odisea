extends SceneTree

func _init():
	print("Starting debug script...")
	var scn = load("res://core_v2/levels/BaseTerrace.tscn").instance()
	print("Instantiated BaseTerrace")
	var qodot_map = scn.get_node_or_null("Building/QodotMap")
	if not qodot_map:
		print("No QodotMap found.")
		quit()
		return
		
	print("Finding lights...")
	for child in qodot_map.get_children():
		if "light" in child.name.to_lower():
			print("-- Node: ", child.name)
			if "starts_active" in child:
				print("   - starts_active: ", child.starts_active)
				print("   - is_active: ", child.get("is_active"))
				print("   - anim_progress: ", child.get("anim_progress"))
				print("   - light_energy: ", child.get("light_energy"))
			
			var omni = child.get_node_or_null("OmniLight")
			if omni:
				print("   - OmniLight energy: ", omni.light_energy)
			else:
				print("   - No OmniLight child found!")
				
	quit()
