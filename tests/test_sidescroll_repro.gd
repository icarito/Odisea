extends SceneTree

func _init():
	print("Running SideScroll Inversion Test (GDScript)...")
	
	# 1. Load Scene (Ensures CameraRig and environment exist)
	var Level = load("res://core_v2/levels/TestScene_v2.tscn")
	var level_instance = Level.instance()
	root.add_child(level_instance)
	
	# 2. Find Pilot
	var player = level_instance.find_node("Pilot", true, false)
	if not player:
		printerr("Pilot not found!")
		quit()
		return
		
	# 3. Setup Camera
	var cam_rig = player.get_node("CameraRig")
	var cam = cam_rig.get_node("SpringArm/Camera")
	cam.current = true
	
	# 4. Get SideScroll Logic
	var ssl = player.get_node("Logic/SideScroll")
	
	# 5. Enter Mode: Lock X (1), Invert (True)
	# enter_mode(axis, value, invert, current_pos, allow_depth)
	ssl.enter_mode(1, 0.0, true, 0.0, true)
	print("Entered SideScroll: Lock X, Invert TRUE")
	
	# Force physics frame to update camera logic
	player._physics_process(0.016)
	
	# 6. Check Camera Basis (Expectation: Facing +X or -X?)
	# My fix applied rotation to CameraRig.
	print("Camera Rig Basis Z (Forward): ", -cam_rig.global_transform.basis.z)
	
	# 7. Inject Right Input
	# We expect this to move player along +Z
	player.inject_input({"move_vec": [1.0, 0.0]})
	
	# Step Physics
	var start_pos = player.global_transform.origin
	for _i in range(10):
		player.step(0.1, player.external_input)
		
	var end_pos = player.global_transform.origin
	var delta = end_pos - start_pos
	
	print("Movement Delta after RIGHT Input: ", delta)
	
	# Check Result
	if delta.z > 0.1:
		print("SUCCESS: Player moved +Z (Right Input -> +Z)")
	elif delta.z < -0.1:
		print("FAILURE: Player moved -Z (Right Input -> -Z) - INVERTED!")
	else:
		print("FAILURE: No movement along Z.")
		
	quit()
