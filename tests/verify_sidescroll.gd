extends SceneTree

func _init():
	print("Starting SideScrollRig Verification...")

	# Load Zone (which contains rig)
	var zone_res = load("res://core_v2/things/SideScrollZone.tscn")
	if not zone_res:
		print("ERROR: Failed to load SideScrollZone.tscn")
		quit(1)
		return

	var zone = zone_res.instance()
	root.add_child(zone)

	# Verify Structure
	var rig = zone.get_node("SideScrollRig")
	if not rig:
		print("ERROR: SideScrollRig not found in zone!")
		quit(1)
		return

	# Check class using get_script() name or resource_path because 'is SideScrollRig' might fail if class_name not registered in headless
	var script = rig.get_script()
	if not script or not "SideScrollRig" in script.resource_path:
		print("ERROR: Node script is not SideScrollRig!")
		print("Script path: ", script.resource_path if script else "null")
		quit(1)
		return

	print("SideScrollRig found. Default constraint: ", rig.constraint_axis)

	# Verify allow_depth_movement property
	if not "allow_depth_movement" in rig:
		print("ERROR: allow_depth_movement property missing!")
		quit(1)
		return
	print("allow_depth_movement exists. Default: ", rig.allow_depth_movement)
	if rig.allow_depth_movement != false:
		print("ERROR: Default should be false")
		quit(1)
		return

	# Create Mock Player
	var player = Spatial.new()
	player.name = "Player"
	player.add_to_group("player")
	root.add_child(player)
	player.global_transform.origin = Vector3(100, 50, 200) # Arbitrary pos

	# Inject player target manually (usually done by _find_target in _update_rig)
	# We call _update_rig once to trigger finding
	rig._update_rig(0.0)

	if rig._target != player:
		print("ERROR: Rig did not find player target!")
		quit(1)
		return

	print("Rig found player.")

	# Test Position Update (Step 1)
	# Default constraint (1, 1, 0) -> Tracks X, Y. Locks Z.
	# Offset (0, 5, 10)

	# Set Rig initial pos (defines the Z plane)
	rig.global_transform.origin = Vector3(0, 0, 50)

	# Update
	rig._update_rig(1.0)

	var rig_pos = rig.global_transform.origin
	print("Player Pos: ", player.global_transform.origin)
	print("Rig Pos: ", rig_pos)

	# Expected:
	# X = Player.x (100) + Offset.x (0) = 100
	# Y = Player.y (50) + Offset.y (5) = 55
	# Z = Locked (50) (Constraint Z=0, so it keeps current)

	if abs(rig_pos.x - 100.0) > 0.1:
		print("ERROR: X tracking failed. Expected 100, got ", rig_pos.x)
		quit(1)
		return

	if abs(rig_pos.y - 55.0) > 0.1:
		print("ERROR: Y tracking failed. Expected 55, got ", rig_pos.y)
		quit(1)
		return

	if abs(rig_pos.z - 50.0) > 0.1:
		print("ERROR: Z lock failed. Expected 50, got ", rig_pos.z)
		quit(1)
		return

	# Verify Rotation (Case 1: Standard, Tracks X,Y. Looks -Z)
	var forward = -rig.global_transform.basis.z
	print("Rig Forward: ", forward)
	# Expected: Z-Lock (Standard).
	# Offset Z = 10 (Positive).
	# Logic: if offset.z >= 0: look_dir = -Z.
	# Forward should be (0, 0, -1).

	if forward.z > -0.9:
		print("ERROR: Rotation incorrect for Standard Mode. Expected -Z (Look From Front), got ", forward)
		quit(1)
		return

	# Case 2: Z-Scroll (Tracks Y,Z. Locks X)
	print("Testing Z-Scroll Mode...")
	rig.constraint_axis = Vector3(0, 1, 1) # Follow Y, Z. Lock X.
	rig.offset = Vector3(10, 5, 0) # Displaced X (+10)

	# Reset positions
	rig.global_transform.origin = Vector3(50, 0, 0) # Initial X=50
	player.global_transform.origin = Vector3(200, 50, 100)

	# Update
	rig._update_rig(1.0)

	rig_pos = rig.global_transform.origin
	print("Player Pos 2: ", player.global_transform.origin)
	print("Rig Pos 2: ", rig_pos)

	# Expected:
	# X = Locked (50) (Constraint X=0) -> 50.
	# Y = Player.y (50) + Offset.y (5) = 55.
	# Z = Player.z (100) + Offset.z (0) = 100.

	if abs(rig_pos.x - 50.0) > 0.1:
		print("ERROR: X lock failed. Expected 50, got ", rig_pos.x)
		quit(1)
		return

	if abs(rig_pos.z - 100.0) > 0.1:
		print("ERROR: Z tracking failed. Expected 100, got ", rig_pos.z)
		quit(1)
		return

	# Verify Rotation
	# X-Lock. Offset X = 10 (Positive).
	# Logic: if offset.x >= 0: look_dir = -X.
	# Forward should be (-1, 0, 0).

	forward = -rig.global_transform.basis.z
	print("Rig Forward 2: ", forward)

	if forward.x > -0.9:
		print("ERROR: Rotation incorrect for Z-Scroll Mode. Expected -X (Look From Right), got ", forward)
		quit(1)
		return

	print("Verification Successful!")
	quit()
