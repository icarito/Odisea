extends SceneTree

func _init():
	print("Running SideScroll Control Test...")
	
	# 1. Load Pilot
	var Pilot = load("res://core_v2/actors/Pilot_v2.tscn")
	var player = Pilot.instance()
	root.add_child(player)
	
	# 2. Get Components
	var ssl = player.get_node("Logic/SideScroll")
	var cam_rig = player.get_node("CameraRig")
	
	# 3. Enter SideScroll Mode (Lock X=1, Invert=True, Depth=True)
	# enter_mode(axis, value, invert, current_pos, allow_depth)
	ssl.enter_mode(1, 0.0, true, 0.0, true)
	print("Entered SideScroll: Lock X, Invert Side (True)")
	
	# 4. Verify Camera Rig Rotation (Should ideally be rotated 180 deg / facing +X)
	# Default rig faces -Z. Rot 180 -> +Z? No.
	# We suspect rig is NOT rotated, causing inversion.
	var rig_basis = cam_rig.transform.basis
	print("Camera Rig Forward: ", -rig_basis.z)
	
	# 5. Inject Input (Right)
	# We start at (0,0,0)
	var input = {"move_vec": [1.0, 0.0]} # Right
	player.inject_input(input)
	
	# 6. Step Physics
	player.step(1.0, player.external_input) # Step 1 sec
	
	# 7. Check Position
	var pos = player.global_transform.origin
	print("Player Pos after Right Input: ", pos)
	
	# Expected:
	# If Correct (Inverted View looking +X):
	# Right Input -> Screen Right. 
	# Cam Look +X. Screen Right is +Z.
	# So Expect Pos Z > 0.
	
	# If Inverted (Bug):
	# Pos Z < 0.
	
	quit()
